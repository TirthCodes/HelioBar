import XCTest
@testable import HelioCore

@MainActor
final class HealthStoreTests: XCTestCase {
    func test_startsIdle() {
        let s = HealthStore()
        XCTAssertNil(s.liveHR)
        XCTAssertEqual(s.hrStatus, .idle)
    }

    func test_updateHRSetsValueAndLive() {
        let s = HealthStore(); s.updateHR(72)
        XCTAssertEqual(s.liveHR, 72)
        XCTAssertEqual(s.hrStatus, .live)
        XCTAssertEqual(s.hrZone, .resting)
    }

    func test_hrDisconnectedKeepsValueButGoesStale() {
        let s = HealthStore(); s.updateHR(72); s.hrDisconnected()
        XCTAssertEqual(s.liveHR, 72)
        XCTAssertEqual(s.hrStatus, .stale)
    }

    func test_hrFailedSetsError() {
        let s = HealthStore(); s.hrFailed("Bluetooth is off")
        XCTAssertEqual(s.hrStatus, .error("Bluetooth is off"))
    }

    func test_batteryStartsUnknownAndUpdatesPercentage() {
        let s = HealthStore()
        XCTAssertNil(s.batteryPercent)

        s.updateBattery(percent: 15)
        XCTAssertEqual(s.batteryPercent, 15)
    }

    func test_batteryPercentIsClampedToValidRange() {
        let s = HealthStore()
        s.updateBattery(percent: -1)
        XCTAssertEqual(s.batteryPercent, 0)

        s.updateBattery(percent: 101)
        XCTAssertEqual(s.batteryPercent, 100)
    }

    func test_zoneThresholdsByPercentMax() {
        let s = HealthStore()   // default maxHR 190
        s.updateHR(80);  XCTAssertEqual(s.hrZone, .resting)   // 42%
        s.updateHR(120); XCTAssertEqual(s.hrZone, .elevated)  // 63%
        s.updateHR(160); XCTAssertEqual(s.hrZone, .high)      // 84%
    }
    func test_percentMax() {
        let s = HealthStore(); s.maxHR = 200; s.updateHR(100)
        XCTAssertEqual(s.percentMax, 50)
    }
    func test_customMaxHRChangesZone() {
        let s = HealthStore(); s.maxHR = 150   // lower max -> same bpm is a higher zone
        s.updateHR(100)                         // 67%
        XCTAssertEqual(s.hrZone, .elevated)
    }

    func test_sessionStatsTrackMinAvgMax() {
        let s = HealthStore()
        [60, 80, 100].forEach { s.updateHR($0) }
        XCTAssertEqual(s.sessionMin, 60)
        XCTAssertEqual(s.sessionMax, 100)
        XCTAssertEqual(s.sessionAvg, 80)
        XCTAssertEqual(s.recent, [60, 80, 100])
    }
    func test_resetSessionClearsStats() {
        let s = HealthStore()
        s.updateHR(90); s.resetSession()
        XCTAssertNil(s.sessionMin); XCTAssertNil(s.sessionAvg)
        XCTAssertTrue(s.recent.isEmpty)
        XCTAssertEqual(s.zoneFraction(.elevated), 0)
    }
    func test_zoneFraction() {
        let s = HealthStore()                  // maxHR 190
        s.updateHR(70); s.updateHR(70); s.updateHR(120)   // 2 resting (37%), 1 elevated (63%)
        XCTAssertEqual(s.zoneFraction(.resting), 2.0/3.0, accuracy: 0.001)
        XCTAssertEqual(s.zoneFraction(.elevated), 1.0/3.0, accuracy: 0.001)
    }
    func test_trendRisingFalling() {
        let s = HealthStore()
        [70,70,70,70,70,70].forEach { s.updateHR($0) }
        XCTAssertEqual(s.hrTrend, .steady)
        s.updateHR(90)
        XCTAssertEqual(s.hrTrend, .rising)
    }
}
