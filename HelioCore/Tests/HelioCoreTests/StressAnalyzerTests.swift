// HelioCore/Tests/HelioCoreTests/StressAnalyzerTests.swift
import Testing
import Foundation
@testable import HelioCore

@Suite("StressAnalyzer")
struct StressAnalyzerTests {

    func makeSample(hr: Int, bundleID: String, appName: String, zone: HRZone, offsetSeconds: Double = 0) -> ActivitySample {
        ActivitySample(
            timestamp: Date(timeIntervalSince1970: 1000 + offsetSeconds),
            hr: hr,
            bundleID: bundleID,
            appName: appName,
            hrZone: zone
        )
    }

    @Test("computeBaseline returns average of resting samples")
    func baseline() {
        let samples = [
            makeSample(hr: 65, bundleID: "a", appName: "A", zone: .resting),
            makeSample(hr: 70, bundleID: "b", appName: "B", zone: .resting),
            makeSample(hr: 95, bundleID: "c", appName: "C", zone: .elevated), // excluded
            makeSample(hr: 75, bundleID: "d", appName: "D", zone: .resting),
        ]

        let baseline = StressAnalyzer.computeBaseline(samples: samples)

        #expect(baseline == 70.0) // (65 + 70 + 75) / 3
    }

    @Test("computeBaseline with no resting samples falls back")
    func baselineNoResting() {
        let samples = [
            makeSample(hr: 90, bundleID: "a", appName: "A", zone: .elevated),
            makeSample(hr: 100, bundleID: "b", appName: "B", zone: .high),
        ]

        let baseline = StressAnalyzer.computeBaseline(samples: samples)

        // Fallback: overall avg (95) - 10 = 85
        #expect(baseline == 85.0)
    }

    @Test("rankByStress sorts by deltaFromBaseline descending")
    func rankByStress() {
        let samples = [
            // App A: 2 samples, avg 90
            makeSample(hr: 85, bundleID: "com.a", appName: "A", zone: .elevated, offsetSeconds: 0),
            makeSample(hr: 95, bundleID: "com.a", appName: "A", zone: .elevated, offsetSeconds: 15),
            // App B: 2 samples, avg 70
            makeSample(hr: 68, bundleID: "com.b", appName: "B", zone: .resting, offsetSeconds: 30),
            makeSample(hr: 72, bundleID: "com.b", appName: "B", zone: .resting, offsetSeconds: 45),
            // App C: 2 samples, avg 80
            makeSample(hr: 78, bundleID: "com.c", appName: "C", zone: .elevated, offsetSeconds: 60),
            makeSample(hr: 82, bundleID: "com.c", appName: "C", zone: .elevated, offsetSeconds: 75),
        ]

        let stats = StressAnalyzer.rankByStress(samples: samples, baseline: 70)

        #expect(stats.count == 3)
        #expect(stats[0].appName == "A") // +20 from baseline
        #expect(stats[1].appName == "C") // +10 from baseline
        #expect(stats[2].appName == "B") // +0 from baseline

        #expect(stats[0].deltaFromBaseline == 20.0)
        #expect(stats[0].avgHR == 90.0)
        #expect(stats[0].maxHR == 95)
        #expect(stats[0].totalSamples == 2)
    }

    @Test("buildTimeline merges consecutive same-app samples")
    func timeline() {
        let samples = [
            makeSample(hr: 70, bundleID: "com.a", appName: "A", zone: .resting, offsetSeconds: 0),
            makeSample(hr: 72, bundleID: "com.a", appName: "A", zone: .resting, offsetSeconds: 15),
            makeSample(hr: 74, bundleID: "com.a", appName: "A", zone: .resting, offsetSeconds: 30),
            // Switch to B
            makeSample(hr: 85, bundleID: "com.b", appName: "B", zone: .elevated, offsetSeconds: 45),
            makeSample(hr: 88, bundleID: "com.b", appName: "B", zone: .elevated, offsetSeconds: 60),
        ]

        let timeline = StressAnalyzer.buildTimeline(samples: samples, mergeThreshold: 60)

        #expect(timeline.count == 2)
        #expect(timeline[0].appName == "A")
        #expect(timeline[0].avgHR == 72.0) // (70+72+74)/3
        #expect(timeline[1].appName == "B")
        #expect(timeline[1].avgHR == 86.5) // (85+88)/2
    }

    @Test("compare calculates week-over-week change")
    func compare() {
        let current = [
            AppStressStats(bundleID: "com.a", appName: "A", totalSamples: 10, avgHR: 85, maxHR: 95, timeInElevated: 100, elevatedRatio: 0.5, deltaFromBaseline: 15),
        ]
        let previous = [
            AppStressStats(bundleID: "com.a", appName: "A", totalSamples: 10, avgHR: 80, maxHR: 90, timeInElevated: 80, elevatedRatio: 0.4, deltaFromBaseline: 10),
        ]

        let comparisons = StressAnalyzer.compare(current: current, previous: previous)

        #expect(comparisons.count == 1)
        #expect(comparisons[0].changePercent == 25.0) // (0.5 - 0.4) / 0.4 * 100
    }
}
