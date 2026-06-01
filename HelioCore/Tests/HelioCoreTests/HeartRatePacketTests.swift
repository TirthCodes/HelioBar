import XCTest
@testable import HelioCore

final class HeartRatePacketTests: XCTestCase {
    func test_parses8BitBPM() {
        XCTAssertEqual(HeartRatePacket.parse(Data([0x00, 0x48]))?.bpm, 72)
    }
    func test_parses16BitBPM() {
        XCTAssertEqual(HeartRatePacket.parse(Data([0x01, 0x2C, 0x01]))?.bpm, 300)
    }
    func test_returnsNilForEmpty() {
        XCTAssertNil(HeartRatePacket.parse(Data()))
    }
    func test_returnsNilWhenTruncated8Bit() {
        XCTAssertNil(HeartRatePacket.parse(Data([0x00])))
    }
    func test_noRRWhenFlagUnset() {
        XCTAssertEqual(HeartRatePacket.parse(Data([0x00, 0x50]))?.rrIntervals, [])
    }
    func test_parsesRRIntervals() {
        // flags 0x10 (RR present, 8-bit HR), bpm 0x50=80, RR raw 0x0400=1024 -> 1.0s
        let s = HeartRatePacket.parse(Data([0x10, 0x50, 0x00, 0x04]))
        XCTAssertEqual(s?.bpm, 80)
        XCTAssertEqual(s?.rrIntervals, [1.0])
    }
    func test_skipsEnergyExpendedBeforeRR() {
        // flags 0x18 (energy-expended + RR, 8-bit), bpm 0x50, energy 0xFFFF, RR 0x0200=512 -> 0.5s
        let s = HeartRatePacket.parse(Data([0x18, 0x50, 0xFF, 0xFF, 0x00, 0x02]))
        XCTAssertEqual(s?.bpm, 80)
        XCTAssertEqual(s?.rrIntervals, [0.5])
    }
}
