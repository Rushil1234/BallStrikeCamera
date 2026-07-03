// Golden tests for the app's pure logic, compiled straight from source with
// swiftc (no Xcode test target). A failed check exits nonzero for CI.

import Foundation
import CoreLocation

var failures = 0
func check(_ ok: Bool, _ label: String) {
    if ok { print("PASS  \(label)") } else { failures += 1; print("FAIL  \(label)") }
}

// ---------- FlightArcModel ----------

let driver = FlightArcModel.trajectory(ballSpeedMph: 150, vlaDeg: 12, hlaDeg: 0, backspinRpm: 2600, sidespinRpm: 0)
let driverLand = driver.last!
let driverApex = driver.map(\.heightFt).max() ?? 0
check((190...260).contains(Int(driverLand.downrangeYd)), "driver carry \(Int(driverLand.downrangeYd))yd in 190...260")
check((80...130).contains(Int(driverApex)), "driver apex \(Int(driverApex))ft in 80...130")
check(abs(driverLand.offlineYd) < 1, "no sidespin -> straight (\(driverLand.offlineYd))")

let sevenIron = FlightArcModel.trajectory(ballSpeedMph: 120, vlaDeg: 16.5, hlaDeg: 0, backspinRpm: 6500, sidespinRpm: 0)
check((150...190).contains(Int(sevenIron.last!.downrangeYd)), "7i carry \(Int(sevenIron.last!.downrangeYd))yd in 150...190")

let fade = FlightArcModel.trajectory(ballSpeedMph: 150, vlaDeg: 12, hlaDeg: 0, backspinRpm: 2600, sidespinRpm: 800)
check(fade.last!.offlineYd > 10, "positive sidespin curves right (\(fade.last!.offlineYd))")

check(FlightArcModel.trajectory(ballSpeedMph: 0, vlaDeg: 12, hlaDeg: 0, backspinRpm: 0, sidespinRpm: 0).isEmpty,
      "zero speed -> empty trajectory")

// ---------- ClubAnalyticsService ----------

func shot(_ idx: Int, yards: Double, category: ShotClub.ClubCategory = .iron) -> TrackedShot {
    var s = TrackedShot(
        roundId: UUID(), holeNumber: 1, shotIndex: idx, userId: UUID(),
        startCoordinate: Coordinate(latitude: 33.5, longitude: -82.0),
        endCoordinate: Coordinate(latitude: 33.5, longitude: -82.0)
    )
    s.club = ShotClub(clubId: nil, name: "7 Iron", category: category)
    s.distanceYards = yards
    return s
}

let cluster = [148.0, 152, 150, 149, 151, 400].enumerated().map { shot($0.offset, yards: $0.element) }
let analytics = ClubAnalyticsService.aggregate(cluster)
if let iron = analytics[.iron] {
    check(iron.sampleCount == 5, "outlier rejected (kept \(iron.sampleCount)/6)")
    check((148...152).contains(Int(iron.avgTotalYds)), "avg total \(Int(iron.avgTotalYds)) in 148...152")
    check(iron.lateralStdDevYds == nil && iron.missBiasYds == nil,
          "lateral metrics explicitly unavailable (nil), not fake zero")
} else {
    check(false, "iron analytics present")
}

let sparse = [150.0, 151, 149].enumerated().map { shot($0.offset, yards: $0.element) }
check(ClubAnalyticsService.aggregate(sparse)[.iron] == nil, "below minSamples -> no analytics")

// ---------- DistanceEstimator fallback (aero-integrated, no trained model) ----------

let est = DistanceEstimator()
let full = est.estimate(ballSpeedMph: 150, vlaDegrees: 12, hlaDegrees: 0, flightModel: nil, backspinRpm: 2600)
check((190...260).contains(Int(full.carryYards ?? 0)),
      "estimator fallback carry \(Int(full.carryYards ?? 0))yd in 190...260 (was vacuum*0.75)")
check(full.method.hasPrefix("aero_integrated"), "fallback method is aero_integrated (\(full.method))")

let chip = est.estimate(ballSpeedMph: 40, vlaDegrees: 30, hlaDegrees: 0, flightModel: nil, backspinRpm: nil)
check((15...45).contains(Int(chip.carryYards ?? 0)), "40mph chip carry \(Int(chip.carryYards ?? 0))yd in 15...45")

let putt = est.estimate(ballSpeedMph: 6, vlaDegrees: 0.5, hlaDegrees: 0, flightModel: nil, backspinRpm: nil)
check(putt.method == "putt_rolling_physics" && putt.carryYards == nil,
      "putt bypasses flight model (\(putt.method))")

// ---------- result ----------
print(failures == 0 ? "ALL LOGIC TESTS PASSED" : "\(failures) LOGIC TEST(S) FAILED")
exit(failures == 0 ? 0 : 1)
