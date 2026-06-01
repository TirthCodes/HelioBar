import Foundation

/// Heart-rate zone for menu bar tinting.
public enum HRZone: String, Sendable {
    case resting, elevated, high

    public static func zone(for bpm: Int) -> HRZone {
        switch bpm {
        case ..<90:    return .resting
        case 90..<130: return .elevated
        default:       return .high
        }
    }
}

/// Heart-rate source freshness for honest UI rendering.
public enum SourceStatus: Equatable, Sendable {
    case idle               // never received data
    case live               // streaming
    case stale              // had data, now dropped
    case error(String)      // failure with message
}
