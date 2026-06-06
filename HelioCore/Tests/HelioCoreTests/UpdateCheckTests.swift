import XCTest
@testable import HelioCore

final class UpdateCheckTests: XCTestCase {
    func test_newerPatch() { XCTAssertTrue(isVersion("2.0.10", newerThan: "2.0.9")) }
    func test_newerMinor() { XCTAssertTrue(isVersion("2.1.0", newerThan: "2.0.0")) }
    func test_newerMajor() { XCTAssertTrue(isVersion("3.0.0", newerThan: "2.9.9")) }
    func test_equalIsNotNewer() { XCTAssertFalse(isVersion("2.0.0", newerThan: "2.0.0")) }
    func test_olderIsNotNewer() { XCTAssertFalse(isVersion("2.0.0", newerThan: "2.1.0")) }
    func test_stripsLeadingV() { XCTAssertTrue(isVersion("v2.1.0", newerThan: "2.0.0")) }
    func test_stripsLeadingVOnCurrent() { XCTAssertFalse(isVersion("v2.0.0", newerThan: "v2.0.0")) }
    func test_shorterPadsWithZero() { XCTAssertFalse(isVersion("2.1", newerThan: "2.1.0")) }
    func test_shorterIsOlder() { XCTAssertTrue(isVersion("2.1.1", newerThan: "2.1")) }
    func test_emptyLatestIsNotNewer() { XCTAssertFalse(isVersion("", newerThan: "2.0.0")) }
    func test_garbageLatestIsNotNewer() { XCTAssertFalse(isVersion("abc", newerThan: "2.0.0")) }
}
