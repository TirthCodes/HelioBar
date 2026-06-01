import Foundation
import Observation

/// Single source of truth the UI binds to. No I/O — sources push into it.
@MainActor
@Observable
public final class HealthStore {
    public var liveHR: Int?
    public var hrStatus: SourceStatus = .idle
    public var stress: StressReading?
    public var readiness: ReadinessReading?
    public var cloudStatus: SourceStatus = .idle
    public var lastSync: Date?

    public init() {}

    public func updateHR(_ bpm: Int) {
        liveHR = bpm
        hrStatus = .live
    }

    public func hrDisconnected() {
        hrStatus = .stale
    }

    public func updateCloud(stress: StressReading,
                            readiness: ReadinessReading,
                            at date: Date) {
        self.stress = stress
        self.readiness = readiness
        self.lastSync = date
        self.cloudStatus = .live
    }

    public func cloudFailed(_ message: String) {
        cloudStatus = .error(message)
    }

    public var hrZone: HRZone? {
        liveHR.map(HRZone.zone(for:))
    }
}
