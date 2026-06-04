import XCTest
@testable import HelioCore

final class BatteryAlertEngineTests: XCTestCase {
    func test_disabledNeverFires() {
        let e = BatteryAlertEngine(config: .init(enabled: false, threshold: 20))
        XCTAssertFalse(e.evaluate(percent: 10))
    }

    func test_firesOnceWhenBatteryFallsAtOrBelowThreshold() {
        let e = BatteryAlertEngine(config: .init(enabled: true, threshold: 20))
        XCTAssertFalse(e.evaluate(percent: 50))
        XCTAssertTrue(e.evaluate(percent: 20))
        XCTAssertFalse(e.evaluate(percent: 15))
    }

    func test_risingAboveThresholdRearmsAlert() {
        let e = BatteryAlertEngine(config: .init(enabled: true, threshold: 20))
        XCTAssertTrue(e.evaluate(percent: 10))
        XCTAssertFalse(e.evaluate(percent: 15))
        XCTAssertFalse(e.evaluate(percent: 21))
        XCTAssertTrue(e.evaluate(percent: 20))
    }
}
