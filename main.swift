// Glaze — the camera sees you look away from the screen → every screen glazes over (frosted glass).
// Frames stay in memory, nothing is stored or sent. Hotkeys are listed in registerHotkey().
import Cocoa
import AVFoundation
import Vision
import Carbon.HIToolbox

// Look-away thresholds and calibration live in Calib.swift
let FPS          = 4.0    // frames analysed per second (2 felt sluggish on turns)
let ON_DELAY_S   = 1.0    // looked away this long → blur (2 s felt slow; the old 0.9 s complaint was the head-down misfire, since removed)
let MIN_FACE_W   = 0.04   // ignore detections narrower than 4% of frame
let DEBUG = ProcessInfo.processInfo.environment["GLAZE_DEBUG"] != nil

// MARK: - Frosted overlay, one window per screen
final class Frost {
    private var windows: [NSWindow] = []
    private(set) var shown = false
    init() {
        build()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in self.build() }
    }
    func build() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map { s in
            let w = NSWindow(contentRect: s.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = .screenSaver
            w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
            w.ignoresMouseEvents = true
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            let v = NSVisualEffectView(frame: NSRect(origin: .zero, size: s.frame.size))
            v.material = .fullScreenUI; v.blendingMode = .behindWindow; v.state = .active   // light frosted glass, follows light/dark mode
            v.autoresizingMask = [.width, .height]
            w.contentView = v
            w.alphaValue = shown ? 1 : 0
            if shown { w.orderFrontRegardless() }
            return w
        }
    }
    func set(_ on: Bool) {
        guard on != shown else { return }
        shown = on
        if on { windows.forEach { $0.alphaValue = 0; $0.orderFrontRegardless() } }
        NSAnimationContext.runAnimationGroup({ c in c.duration = 0.2; self.windows.forEach { $0.animator().alphaValue = on ? 1 : 0 } },
                                            completionHandler: { if !self.shown { self.windows.forEach { $0.orderOut(nil) } } })
    }
}

// MARK: - Camera: is the largest face turned away (or missing)?
final class Watcher: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onAway: ((Bool) -> Void)?
    var onError: (() -> Void)?
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "glaze.cam")
    private var configured = false, running = false
    private var lastFrame = Date.distantPast, awaySince: Date? = nil
    private var away = false
    private var calib = Calib()
    private var snoozed = false   // after Esc: stay clear until the next facing frame
    func snooze() { queue.async { self.snoozed = true; self.awaySince = nil; self.setAway(false) } }
    private var sink: (((Double, Double)?) -> Void)?   // set during calibration: frames go here, blur logic paused
    func setCalib(_ c: Calib) { queue.async { self.calib = c } }
    func setSink(_ f: (((Double, Double)?) -> Void)?) { queue.async { self.sink = f; self.awaySince = nil; self.setAway(false) } }

    func start() {
        guard !running else { return }
        AVCaptureDevice.requestAccess(for: .video) { ok in
            DispatchQueue.main.async { ok ? self.run() : self.onError?() }
        }
    }
    private func run() {
        if !configured {
            guard let dev = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: dev) else { onError?(); return }
            session.beginConfiguration()
            session.sessionPreset = .vga640x480
            if session.canAddInput(input) { session.addInput(input) }
            let out = AVCaptureVideoDataOutput()
            out.alwaysDiscardsLateVideoFrames = true
            out.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(out) { session.addOutput(out) }
            session.commitConfiguration()
            configured = true
        }
        running = true
        queue.async { self.session.startRunning() }
    }
    func stop() {
        guard running else { return }
        running = false
        queue.async { self.session.stopRunning(); self.awaySince = nil; self.setAway(false) }
    }
    func captureOutput(_ o: AVCaptureOutput, didOutput sb: CMSampleBuffer, from c: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastFrame) >= 1.0 / FPS, let px = CMSampleBufferGetImageBuffer(sb) else { return }
        lastFrame = now
        let req = VNDetectFaceRectanglesRequest()
        req.revision = VNDetectFaceRectanglesRequestRevision3   // rev3 reports yaw
        do { try VNImageRequestHandler(cvPixelBuffer: px, orientation: .up, options: [:]).perform([req]) }
        catch { if DEBUG { FileHandle.standardError.write("vision error: \(error)\n".data(using: .utf8)!) }; return }
        let owner = (req.results ?? []).filter { $0.boundingBox.width >= MIN_FACE_W }.max { $0.boundingBox.width < $1.boundingBox.width }
        let yaw = owner?.yaw.map { $0.doubleValue * 180 / .pi }
        let pitch = owner?.pitch.map { $0.doubleValue * 180 / .pi }
        let angles = yaw.flatMap { y in pitch.map { (y, $0) } }
        if let sink = sink { DispatchQueue.main.async { sink(angles) }; return }
        // no face (or no angles) = not looking
        let turned = angles.map { calib.isAway(yaw: $0.0, pitch: $0.1, wasAway: away) } ?? true
        if snoozed { if !turned { snoozed = false }; return }
        if DEBUG { FileHandle.standardError.write("yaw=\(yaw.map { String(format: "%.0f", $0) } ?? "-") pitch=\(pitch.map { String(format: "%.0f", $0) } ?? "-") away=\(away)\n".data(using: .utf8)!) }
        if turned {
            if awaySince == nil { awaySince = now }
            if now.timeIntervalSince(awaySince!) >= ON_DELAY_S { setAway(true) }
        } else {
            awaySince = nil
            setAway(false)   // clear on the first facing frame
        }
    }
    private func setAway(_ a: Bool) {
        guard a != away else { return }
        away = a
        DispatchQueue.main.async { self.onAway?(a) }
    }
}

// MARK: - App
final class App: NSObject, NSApplicationDelegate {
    let frost = Frost()
    let watcher = Watcher()
    var status: NSStatusItem!
    var paused = false, camError = false
    var calibrating = false
    var calibRun = 0              // bumps on cancel so pending calibration steps drop out
    var escRef: EventHotKeyRef?   // Esc is grabbed only while frosted or calibrating, so other apps keep it
    func syncEsc() {
        let want = frost.shown || calibrating
        if want, escRef == nil {
            RegisterEventHotKey(UInt32(kVK_Escape), 0, EventHotKeyID(signature: 0x4C4B424C, id: 4), GetApplicationEventTarget(), 0, &escRef)
        } else if !want, let r = escRef { UnregisterEventHotKey(r); escRef = nil }
    }
    func esc() {
        if calibrating { calibRun += 1; watcher.setSink(nil); prompt.orderOut(nil); calibrating = false }
        if frost.shown { watcher.snooze(); frost.set(false) }
        refreshIcon()
    }
    lazy var prompt: NSPanel = {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 120), styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        p.title = "Glaze calibration"; p.level = .floating; p.center()
        let l = NSTextField(labelWithString: "")
        l.font = .systemFont(ofSize: 24, weight: .medium); l.alignment = .center
        l.frame = NSRect(x: 0, y: 35, width: 460, height: 40)
        p.contentView?.addSubview(l)
        return p
    }()
    func say(_ t: String) { (prompt.contentView?.subviews.first as? NSTextField)?.stringValue = t }

    func applicationDidFinishLaunching(_ n: Notification) {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.addItem(withTitle: "Pause / Resume  (⌃⌥X)", action: #selector(togglePause), keyEquivalent: "")
        menu.addItem(withTitle: "Preview frost (2 s)  (⌃⌥B)", action: #selector(preview), keyEquivalent: "")
        menu.addItem(withTitle: "Calibrate — face the screen  (⌃⌥K)", action: #selector(calibrate), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit  (⌃⌥Q)", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        status.menu = menu

        watcher.onAway = { [weak self] a in self?.frost.set(a); self?.refreshIcon() }
        watcher.onError = { [weak self] in self?.camError = true; self?.refreshIcon() }
        registerHotkey()
        // camera off while the screen is locked or asleep
        let ws = NSWorkspace.shared.notificationCenter, dn = DistributedNotificationCenter.default()
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { _ in self.watcher.stop() }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { _ in self.resume() }
        dn.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in self.watcher.stop() }
        dn.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in self.resume() }
        if let d = UserDefaults.standard.data(forKey: "calib"), let c = try? JSONDecoder().decode(Calib.self, from: d) { watcher.setCalib(c) }
        watcher.start()
        refreshIcon()
        if ProcessInfo.processInfo.environment["GLAZE_PREVIEW"] != nil { preview() }
    }
    func resume() { if !paused { watcher.start() } }
    func refreshIcon() {
        syncEsc()
        status.button?.title = paused ? "◐ ⏸" : camError ? "◐ ✗" : frost.shown ? "◐ ●" : "◐"
    }
    @objc func togglePause() {
        paused.toggle()
        if paused { watcher.stop(); frost.set(false) } else { watcher.start() }
        refreshIcon()
    }
    @objc func preview() {
        frost.set(true); syncEsc()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.frost.set(false); self.syncEsc() }
    }
    // Look at the screen: 1 s to settle (discarded) + 3 s of samples. Frost is suspended meanwhile.
    @objc func calibrate() {
        guard !calibrating, !paused, !camError else { return }
        calibrating = true; calibRun += 1
        let run = calibRun
        prompt.orderFrontRegardless(); syncEsc()
        let steps = ["Face the screen, sit as usual"]
        var got: [[(Double, Double)]] = []
        func step(_ i: Int) {
            guard run == calibRun else { return }   // cancelled with Esc
            guard i < steps.count else { return finish(got) }
            var buf: [(Double, Double)] = [], collecting = false
            say("\(steps[i])   ·   Esc to cancel")
            watcher.setSink { a in if collecting, let a = a { buf.append(a) } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { collecting = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { got.append(buf); step(i + 1) }
        }
        step(0)
    }
    func finish(_ got: [[(Double, Double)]]) {
        watcher.setSink(nil)
        if let c = makeCalib(screen: got[0]) {
            watcher.setCalib(c)
            if let d = try? JSONEncoder().encode(c) { UserDefaults.standard.set(d, forKey: "calib") }
            say("Done")
            if DEBUG { FileHandle.standardError.write("calib \(c) samples=\(got[0].count)\n".data(using: .utf8)!) }
        } else {
            say("Couldn't see your face, kept the old setting")
            if DEBUG { FileHandle.standardError.write("calib failed samples=\(got[0].count)\n".data(using: .utf8)!) }
        }
        let run = calibRun
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { guard run == self.calibRun else { return }; self.prompt.orderOut(nil); self.calibrating = false; self.syncEsc() }
    }
    // Right-click on the Dock icon; macOS appends Quit itself
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let m = NSMenu()
        m.addItem(withTitle: paused ? "Resume" : "Pause", action: #selector(togglePause), keyEquivalent: "")
        m.addItem(withTitle: "Calibrate — face the screen", action: #selector(calibrate), keyEquivalent: "")
        m.addItem(withTitle: "Preview frost", action: #selector(preview), keyEquivalent: "")
        m.items.forEach { $0.target = self }
        return m
    }
    @objc func quit() { watcher.stop(); frost.set(false); NSApp.terminate(nil) }

    // Global hotkey via Carbon (no Accessibility permission needed)
    func registerHotkey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // menu-bar icon can hide behind the notch, so every action has a hotkey. ⌃⌥X pause, ⌃⌥K calibrate, ⌃⌥B preview, ⌃⌥Q quit.
        InstallEventHandler(GetApplicationEventTarget(), { _, evt, _ -> OSStatus in
            var hk = EventHotKeyID()
            GetEventParameter(evt, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            switch hk.id { case 1: app.togglePause(); case 2: app.calibrate(); case 3: app.preview(); case 4: app.esc(); case 5: app.quit(); default: break }
            return noErr
        }, 1, &spec, nil, nil)
        var ref: EventHotKeyRef?
        for (id, key) in [(1, kVK_ANSI_X), (2, kVK_ANSI_K), (3, kVK_ANSI_B), (5, kVK_ANSI_Q)] {
            RegisterEventHotKey(UInt32(key), UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x4C4B424C, id: UInt32(id)), GetApplicationEventTarget(), 0, &ref)
        }
    }
}

let app = App()
NSApplication.shared.setActivationPolicy(.regular)   // Dock icon: the menu-bar item hides behind the notch, right-click Dock → Quit
NSApplication.shared.delegate = app
NSApplication.shared.run()
