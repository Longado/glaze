// Calibration: where "facing the screen" is. Away = turned sideways or head up; head down (typing) never counts.
// No face at all is handled in main.swift. Angles in degrees, yaw signed, pitch + = head down.
import Foundation

// ponytail: fixed, measured from the calibrated baseline; calibrate these too if they misfire.
// Measured facing-screen wobble: yaw mostly within ±14, pitch below −5 in 5 of 219 frames; 2 s delay absorbs single spikes
let LOOK_ON_DEG  = 20.0   // |yaw − base| above this → away (30 missed moderate turns)
let LOOK_OFF_DEG = 12.0   // below this → back (hysteresis)
let UP_ON_DEG    = 10.0   // pitch more than this above base (head up) → away
let UP_OFF_DEG   = 5.0
let MIN_SAMPLES  = 3      // 3 s at 4 fps gives ~12; floor for "the face was seen at all"

struct Calib: Codable, Equatable {
    var baseYaw = 0.0, basePitch = 0.0

    func isAway(yaw: Double, pitch: Double, wasAway: Bool) -> Bool {
        let y = abs(yaw - baseYaw), up = basePitch - pitch
        return wasAway ? (y > LOOK_OFF_DEG || up > UP_OFF_DEG) : (y > LOOK_ON_DEG || up > UP_ON_DEG)
    }
}

func median(_ a: [Double]) -> Double {
    let s = a.sorted(), n = s.count
    return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
}

/// screen: (yaw, pitch) while facing the screen. nil when too few face samples — caller keeps the old calibration.
func makeCalib(screen: [(Double, Double)]) -> Calib? {
    guard screen.count >= MIN_SAMPLES else { return nil }
    return Calib(baseYaw: median(screen.map { $0.0 }), basePitch: median(screen.map { $0.1 }))
}
