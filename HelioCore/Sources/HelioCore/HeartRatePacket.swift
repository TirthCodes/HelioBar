import Foundation

public struct HeartRateSample: Equatable, Sendable {
    public let bpm: Int
    public let rrIntervals: [Double]   // seconds
    public init(bpm: Int, rrIntervals: [Double]) {
        self.bpm = bpm; self.rrIntervals = rrIntervals
    }
}

/// Parses a BLE Heart Rate Measurement (0x2A37) value.
/// flags bit0: 16-bit HR; bit3: energy-expended present (skip 2 bytes); bit4: RR intervals present.
public enum HeartRatePacket {
    public static func parse(_ data: Data) -> HeartRateSample? {
        let b = [UInt8](data)
        guard let flags = b.first else { return nil }
        var i = 1
        let bpm: Int
        if flags & 0x01 != 0 {
            guard b.count >= 3 else { return nil }
            bpm = Int(b[1]) | (Int(b[2]) << 8); i = 3
        } else {
            guard b.count >= 2 else { return nil }
            bpm = Int(b[1]); i = 2
        }
        if flags & 0x08 != 0 { i += 2 }              // skip energy-expended uint16
        var rr: [Double] = []
        if flags & 0x10 != 0 {                       // RR intervals, units of 1/1024 s
            while i + 2 <= b.count {
                let raw = Int(b[i]) | (Int(b[i+1]) << 8)
                rr.append(Double(raw) / 1024.0)
                i += 2
            }
        }
        return HeartRateSample(bpm: bpm, rrIntervals: rr)
    }
}
