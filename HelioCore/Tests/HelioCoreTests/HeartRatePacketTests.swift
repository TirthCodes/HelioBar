import XCTest
@testable import HelioCore

final class HeartRatePacketTests: XCTestCase {
    func test_parses8BitBPM() {
        // flags=0x00 (8-bit), value=0x48 (72)
        XCTAssertEqual(HeartRatePacket.parse(Data([0x00, 0x48])), 72)
    }

    func test_parses16BitBPM() {
        // flags=0x01 (16-bit), value little-endian 0x012C (300)
        XCTAssertEqual(HeartRatePacket.parse(Data([0x01, 0x2C, 0x01])), 300)
    }

    func test_ignoresOtherFlagBits() {
        // flags=0x10 (some other bit set), still 8-bit, value 0x50 (80)
        XCTAssertEqual(HeartRatePacket.parse(Data([0x10, 0x50])), 80)
    }

    func test_returnsNilForEmpty() {
        XCTAssertNil(HeartRatePacket.parse(Data()))
    }

    func test_returnsNilWhenTruncated8Bit() {
        XCTAssertNil(HeartRatePacket.parse(Data([0x00])))
    }

    func test_returnsNilWhenTruncated16Bit() {
        XCTAssertNil(HeartRatePacket.parse(Data([0x01, 0x2C])))
    }
}
