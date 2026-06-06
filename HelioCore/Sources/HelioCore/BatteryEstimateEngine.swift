import Foundation

public enum BatteryEstimate: Equatable, Sendable {
    case calibrating
    case ready(TimeInterval)
}

public struct BatterySample: Equatable, Sendable {
    public let percent: Int
    public let date: Date

    public init(percent: Int, date: Date) {
        self.percent = Swift.min(100, Swift.max(0, percent))
        self.date = date
    }
}

/// Estimates battery time remaining from observed percentage drops.
public final class BatteryEstimateEngine {
    private let minCalibrationDuration: TimeInterval
    private let minPercentDrop: Int
    private let maxSamples: Int
    private var samples: [BatterySample] = []

    public init(
        minCalibrationDuration: TimeInterval = 3 * 60 * 60,
        minPercentDrop: Int = 2,
        maxSamples: Int = 48
    ) {
        self.minCalibrationDuration = minCalibrationDuration
        self.minPercentDrop = minPercentDrop
        self.maxSamples = maxSamples
    }

    @discardableResult
    public func record(percent: Int, date: Date = Date()) -> BatteryEstimate {
        let sample = BatterySample(percent: percent, date: date)

        if let last = samples.last {
            if sample.percent > last.percent {
                samples = [sample]
                return .calibrating
            }
            if sample.percent == last.percent {
                return estimate(currentPercent: sample.percent, now: sample.date)
            }
        }

        samples.append(sample)
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
        return estimate(currentPercent: sample.percent, now: sample.date)
    }

    public func estimate(currentPercent: Int, now: Date = Date()) -> BatteryEstimate {
        guard let first = samples.first, let last = samples.last else { return .calibrating }
        let observedDuration = now.timeIntervalSince(first.date)
        let observedDrop = first.percent - last.percent

        guard observedDuration >= minCalibrationDuration,
              observedDrop >= minPercentDrop else {
            return .calibrating
        }

        let secondsPerPercent = observedDuration / Double(observedDrop)
        return .ready(Double(Swift.max(0, currentPercent)) * secondsPerPercent)
    }
}
