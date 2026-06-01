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

    func test_zoneThresholds() {
        let s = HealthStore()
        s.updateHR(80);  XCTAssertEqual(s.hrZone, .resting)
        s.updateHR(100); XCTAssertEqual(s.hrZone, .elevated)
        s.updateHR(150); XCTAssertEqual(s.hrZone, .high)
    }
}
