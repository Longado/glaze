// Run: swiftc Calib.swift tests/main.swift -o /tmp/calibcheck && /tmp/calibcheck
func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }

// Baseline = medians of the screen samples
let c = makeCalib(screen: [(2, 3), (1, 4), (3, 2), (2, 3), (0, 5), (2, 3)])!
assert(near(c.baseYaw, 2) && near(c.basePitch, 3))

// Head down (typing, measured up to ~16°, even phone ~27°) never frosts
assert(!c.isAway(yaw: 2, pitch: 3 + 27, wasAway: false), "head down is not away")
assert(!c.isAway(yaw: 2, pitch: 3 + 16, wasAway: true), "head down clears a frost too")

// Turning sideways still frosts, with hysteresis
assert(c.isAway(yaw: 2 + 45, pitch: 3, wasAway: false))
assert(c.isAway(yaw: 2 + 22, pitch: 3, wasAway: false), "a moderate 22° turn frosts")
assert(!c.isAway(yaw: 2 + 16, pitch: 3, wasAway: false), "16° is under the on threshold")
assert(c.isAway(yaw: 2 + 16, pitch: 3, wasAway: true), "…but over the off threshold")
assert(!c.isAway(yaw: 2 - 8, pitch: 3, wasAway: false), "facing-screen wobble stays clear")

// Head up frosts; small upward wobble (e.g. −5) doesn't
assert(c.isAway(yaw: 2, pitch: 3 - 14, wasAway: false))
assert(!c.isAway(yaw: 2, pitch: 3 - 5, wasAway: false))

// External monitor: facing the screen reads 35° of yaw → that becomes the zero
let side = makeCalib(screen: [(35, 0), (34, 1), (36, 0), (35, 0)])!
assert(!side.isAway(yaw: 36, pitch: 0, wasAway: false), "facing the side monitor is not away")
assert(side.isAway(yaw: 0, pitch: 0, wasAway: false), "looking at the laptop instead is 35° off → away")

// Face lost for most of the step → refuse, caller keeps the old calibration
assert(makeCalib(screen: [(1, 1), (2, 2)]) == nil)
print("calib check: all passed")
