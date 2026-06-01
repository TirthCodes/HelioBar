import Foundation
import Observation

/// Single source of truth the UI binds to. Fed by the BLE heart-rate monitor.
@MainActor
@Observable
public final class HealthStore {
    public var liveHR: Int?
    public var hrStatus: SourceStatus = .idle

    public init() {}

    public func updateHR(_ bpm: Int) {
        liveHR = bpm
        hrStatus = .live
    }

    public func hrDisconnected() { hrStatus = .stale }

    public func hrFailed(_ message: String) { hrStatus = .error(message) }

    public var hrZone: HRZone? { liveHR.map(HRZone.zone(for:)) }
}
