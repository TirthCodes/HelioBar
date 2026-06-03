import Foundation
import Observation

/// Single source of truth the UI binds to. Fed by the BLE heart-rate monitor.
@MainActor
@Observable
public final class HealthStore {
    public var liveHR: Int?
    public var hrStatus: SourceStatus = .idle
    public var batteryPercent: Int?
    public var maxHR: Int = 190

    // Session analytics
    public private(set) var recent: [Int] = []          // for sparkline
    public private(set) var sessionMin: Int?
    public private(set) var sessionMax: Int?
    public private(set) var zoneCounts: [HRZone: Int] = [:]
    private var sessionSum = 0
    private var sessionCount = 0
    private let recentCap = 150

    public init() {}

    public func updateHR(_ bpm: Int) {
        liveHR = bpm
        hrStatus = .live
        recent.append(bpm)
        if recent.count > recentCap { recent.removeFirst(recent.count - recentCap) }
        sessionMin = Swift.min(sessionMin ?? bpm, bpm)
        sessionMax = Swift.max(sessionMax ?? bpm, bpm)
        sessionSum += bpm
        sessionCount += 1
        zoneCounts[HRZone.zone(for: bpm, maxHR: maxHR), default: 0] += 1
    }

    public func hrDisconnected() { hrStatus = .stale }
    public func hrFailed(_ message: String) { hrStatus = .error(message) }
    public func updateBattery(percent: Int) {
        batteryPercent = Swift.min(100, Swift.max(0, percent))
    }

    public func resetSession() {
        recent = []; sessionMin = nil; sessionMax = nil
        sessionSum = 0; sessionCount = 0; zoneCounts = [:]
    }

    public var hrZone: HRZone? { liveHR.map { HRZone.zone(for: $0, maxHR: maxHR) } }

    /// Current HR as a percentage of max HR.
    public var percentMax: Int? {
        liveHR.map { Int((Double($0) / Double(Swift.max(maxHR, 1)) * 100).rounded()) }
    }

    public var sessionAvg: Int? {
        sessionCount == 0 ? nil : Int((Double(sessionSum) / Double(sessionCount)).rounded())
    }

    public enum Trend: Sendable { case rising, falling, steady }
    public var hrTrend: Trend? {
        guard recent.count >= 6, let last = recent.last else { return nil }
        let window = recent.suffix(6)
        let avg = Double(window.reduce(0, +)) / Double(window.count)
        if Double(last) > avg + 2 { return .rising }
        if Double(last) < avg - 2 { return .falling }
        return .steady
    }

    /// Fraction (0...1) of session samples spent in the given zone.
    public func zoneFraction(_ zone: HRZone) -> Double {
        let total = zoneCounts.values.reduce(0, +)
        return total == 0 ? 0 : Double(zoneCounts[zone] ?? 0) / Double(total)
    }
}
