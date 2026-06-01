import Foundation

/// Parses a BLE Heart Rate Measurement characteristic value (UUID 0x2A37).
/// Spec: first byte is flags; bit 0 = 0 → 8-bit BPM, bit 0 = 1 → 16-bit LE BPM.
public enum HeartRatePacket {
    public static func parse(_ data: Data) -> Int? {
        guard let flags = data.first else { return nil }
        let base = data.startIndex
        let is16Bit = (flags & 0x01) != 0
        if is16Bit {
            guard data.count >= 3 else { return nil }
            let lo = UInt16(data[base + 1])
            let hi = UInt16(data[base + 2])
            return Int(lo | (hi << 8))
        } else {
            guard data.count >= 2 else { return nil }
            return Int(data[base + 1])
        }
    }
}
