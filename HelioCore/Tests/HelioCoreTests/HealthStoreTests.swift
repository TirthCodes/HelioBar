import XCTest
@testable import HelioCore

@MainActor
final class HealthStoreTests: XCTestCase {
    func test_startsIdle() {
        let store = HealthStore()
        XCTAssertNil(store.liveHR)
        XCTAssertEqual(store.hrStatus, .idle)
        XCTAssertEqual(store.cloudStatus, .idle)
    }

    func test_updateHRSetsValueAndLive() {
        let store = HealthStore()
        store.updateHR(72)
        XCTAssertEqual(store.liveHR, 72)
        XCTAssertEqual(store.hrStatus, .live)
        XCTAssertEqual(store.hrZone, .resting)
    }

    func test_hrDisconnectedKeepsValueButGoesStale() {
        let store = HealthStore()
        store.updateHR(72)
        store.hrDisconnected()
        XCTAssertEqual(store.liveHR, 72)        // last value retained
        XCTAssertEqual(store.hrStatus, .stale)
    }

    func test_updateCloudSetsMetricsAndSync() {
        let store = HealthStore()
        let when = Date(timeIntervalSince1970: 1_000)
        store.updateCloud(stress: StressReading(value: 34, label: "Relaxed"),
                          readiness: ReadinessReading(value: 81),
                          at: when)
        XCTAssertEqual(store.stress, StressReading(value: 34, label: "Relaxed"))
        XCTAssertEqual(store.readiness, ReadinessReading(value: 81))
        XCTAssertEqual(store.lastSync, when)
        XCTAssertEqual(store.cloudStatus, .live)
    }

    func test_cloudFailureDoesNotTouchHR() {
        let store = HealthStore()
        store.updateHR(80)
        store.cloudFailed("401")
        XCTAssertEqual(store.liveHR, 80)               // HR untouched
        XCTAssertEqual(store.hrStatus, .live)
        XCTAssertEqual(store.cloudStatus, .error("401"))
    }
}
