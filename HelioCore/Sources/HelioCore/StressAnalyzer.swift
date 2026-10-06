import Foundation

/// Computed per-app stress statistics.
public struct AppStressStats: Sendable, Equatable {
    public let bundleID: String
    public let appName: String
    public let totalSamples: Int
    public let avgHR: Double
    public let maxHR: Int
    public let timeInElevated: TimeInterval
    public let elevatedRatio: Double
    public let deltaFromBaseline: Double

    public init(
        bundleID: String,
        appName: String,
        totalSamples: Int,
        avgHR: Double,
        maxHR: Int,
        timeInElevated: TimeInterval,
        elevatedRatio: Double,
        deltaFromBaseline: Double
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.totalSamples = totalSamples
        self.avgHR = avgHR
        self.maxHR = maxHR
        self.timeInElevated = timeInElevated
        self.elevatedRatio = elevatedRatio
        self.deltaFromBaseline = deltaFromBaseline
    }
}

/// Timeline segment for visualization.
public struct TimelineSegment: Sendable, Equatable {
    public let start: Date
    public let end: Date
    public let appName: String
    public let avgHR: Double
    public let zone: HRZone

    public init(start: Date, end: Date, appName: String, avgHR: Double, zone: HRZone) {
        self.start = start
        self.end = end
        self.appName = appName
        self.avgHR = avgHR
        self.zone = zone
    }
}

/// Week-over-week comparison.
public struct AppStressComparison: Sendable, Equatable {
    public let bundleID: String
    public let appName: String
    public let currentElevatedRatio: Double
    public let previousElevatedRatio: Double
    public let changePercent: Double

    public init(bundleID: String, appName: String, currentElevatedRatio: Double, previousElevatedRatio: Double, changePercent: Double) {
        self.bundleID = bundleID
        self.appName = appName
        self.currentElevatedRatio = currentElevatedRatio
        self.previousElevatedRatio = previousElevatedRatio
        self.changePercent = changePercent
    }
}

/// Pure functions for computing stress insights.
public enum StressAnalyzer {

    /// Compute resting baseline HR. Returns avg of resting samples,
    /// or overall avg - 10 if no resting samples exist.
    public static func computeBaseline(samples: [ActivitySample]) -> Double? {
        guard !samples.isEmpty else { return nil }

        let restingSamples = samples.filter { $0.hrZone == .resting }

        if !restingSamples.isEmpty {
            let sum = restingSamples.map(\.hr).reduce(0, +)
            return Double(sum) / Double(restingSamples.count)
        } else {
            // Fallback: overall avg - 10
            let sum = samples.map(\.hr).reduce(0, +)
            return Double(sum) / Double(samples.count) - 10
        }
    }

    /// Rank apps by delta from baseline (most stress-inducing first).
    public static func rankByStress(
        samples: [ActivitySample],
        baseline: Double? = nil
    ) -> [AppStressStats] {
        guard !samples.isEmpty else { return [] }

        let effectiveBaseline = baseline ?? computeBaseline(samples: samples) ?? 70

        // Group by bundleID
        var grouped: [String: [ActivitySample]] = [:]
        for sample in samples {
            grouped[sample.bundleID, default: []].append(sample)
        }

        var stats: [AppStressStats] = []

        for (bundleID, appSamples) in grouped {
            let appName = appSamples.first?.appName ?? bundleID
            let totalSamples = appSamples.count
            let sumHR = appSamples.map(\.hr).reduce(0, +)
            let avgHR = Double(sumHR) / Double(totalSamples)
            let maxHR = appSamples.map(\.hr).max() ?? 0

            let elevatedCount = appSamples.filter { $0.hrZone != .resting }.count
            let elevatedRatio = Double(elevatedCount) / Double(totalSamples)
            let timeInElevated = Double(elevatedCount) * 15.0 // 15 seconds per sample

            let deltaFromBaseline = avgHR - effectiveBaseline

            stats.append(AppStressStats(
                bundleID: bundleID,
                appName: appName,
                totalSamples: totalSamples,
                avgHR: avgHR,
                maxHR: maxHR,
                timeInElevated: timeInElevated,
                elevatedRatio: elevatedRatio,
                deltaFromBaseline: deltaFromBaseline
            ))
        }

        // Sort by deltaFromBaseline descending
        return stats.sorted { $0.deltaFromBaseline > $1.deltaFromBaseline }
    }

    /// Build timeline segments, merging consecutive same-app samples.
    public static func buildTimeline(
        samples: [ActivitySample],
        mergeThreshold: TimeInterval = 60
    ) -> [TimelineSegment] {
        guard !samples.isEmpty else { return [] }

        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        var segments: [TimelineSegment] = []

        var currentSamples: [ActivitySample] = [sorted[0]]

        for sample in sorted.dropFirst() {
            let last = currentSamples.last!
            let gap = sample.timestamp.timeIntervalSince(last.timestamp)

            if sample.bundleID == last.bundleID && gap <= mergeThreshold {
                currentSamples.append(sample)
            } else {
                // Finalize current segment
                segments.append(makeSegment(from: currentSamples))
                currentSamples = [sample]
            }
        }

        // Finalize last segment
        if !currentSamples.isEmpty {
            segments.append(makeSegment(from: currentSamples))
        }

        return segments
    }

    private static func makeSegment(from samples: [ActivitySample]) -> TimelineSegment {
        let avgHR = Double(samples.map(\.hr).reduce(0, +)) / Double(samples.count)
        let dominantZone = samples.map(\.hrZone).max { zoneOrder($0) < zoneOrder($1) } ?? .resting

        return TimelineSegment(
            start: samples.first!.timestamp,
            end: samples.last!.timestamp,
            appName: samples.first!.appName,
            avgHR: avgHR,
            zone: dominantZone
        )
    }

    private static func zoneOrder(_ zone: HRZone) -> Int {
        switch zone {
        case .resting: return 0
        case .elevated: return 1
        case .high: return 2
        }
    }

    /// Compare two periods (e.g., this week vs last week).
    public static func compare(
        current: [AppStressStats],
        previous: [AppStressStats]
    ) -> [AppStressComparison] {
        var comparisons: [AppStressComparison] = []

        let previousMap = Dictionary(uniqueKeysWithValues: previous.map { ($0.bundleID, $0) })

        for curr in current {
            guard let prev = previousMap[curr.bundleID] else { continue }

            let rawChange: Double
            if prev.elevatedRatio > 0 {
                rawChange = ((curr.elevatedRatio - prev.elevatedRatio) / prev.elevatedRatio) * 100
            } else if curr.elevatedRatio > 0 {
                rawChange = 100 // From 0 to something = 100% increase
            } else {
                rawChange = 0
            }
            // Round to 1 decimal to avoid floating-point drift
            let changePercent = (rawChange * 10).rounded() / 10

            comparisons.append(AppStressComparison(
                bundleID: curr.bundleID,
                appName: curr.appName,
                currentElevatedRatio: curr.elevatedRatio,
                previousElevatedRatio: prev.elevatedRatio,
                changePercent: changePercent
            ))
        }

        return comparisons.sorted { abs($0.changePercent) > abs($1.changePercent) }
    }

    /// Average HR by hour of day (0-23).
    public static func hourlyPattern(samples: [ActivitySample]) -> [Int: Double] {
        var grouped: [Int: [Int]] = [:]
        let calendar = Calendar.current

        for sample in samples {
            let hour = calendar.component(.hour, from: sample.timestamp)
            grouped[hour, default: []].append(sample.hr)
        }

        var result: [Int: Double] = [:]
        for (hour, hrs) in grouped {
            result[hour] = Double(hrs.reduce(0, +)) / Double(hrs.count)
        }

        return result
    }
}
