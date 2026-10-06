# Work Stress Correlation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Track HR alongside active macOS app every 15 seconds; show which apps correlate with elevated heart rate via baseline comparison.

**Architecture:** HelioCore gains ActivitySample (model), ActivityStore (SQLite via GRDB), ActivityTracker (15s polling), and StressAnalyzer (pure functions for insights). HelioBarApp adds menu bar stress dot, popover summary row, settings section, and a separate insights window with charts.

**Tech Stack:** Swift 6, SwiftUI, GRDB.swift (SQLite), NSWorkspace (frontmost app detection)

**Spec:** `docs/superpowers/specs/2026-10-06-work-stress-correlation-design.md`

## Global Constraints

- macOS 14+ (existing platform floor)
- Swift 6 strict concurrency (`@MainActor` isolation where needed)
- GRDB.swift 6.x for SQLite
- All activity data stored locally in app sandbox, never transmitted
- Feature disabled by default (opt-in via Settings)
- Tracking only active when HR connected

## Review Focus

1. **Empty database queries** — `samples(from:to:)` with no data should return empty array, not crash
2. **Baseline with no resting samples** — user always elevated should fallback to overall avg - 10 bpm, not nil/crash
3. **App without bundle ID** — some system processes lack bundle ID; skip sample, don't crash
4. **Screen sleep/wake** — tracking should pause on sleep, resume on wake without duplicate timers
5. **Concurrent database access** — GRDB handles this, but verify no race conditions in tests

---

## File Structure

```
HelioCore/
├── Package.swift                           (MODIFY: add GRDB dependency)
├── Sources/HelioCore/
│   ├── Models.swift                        (existing)
│   ├── ActivitySample.swift                (NEW: model + GRDB record)
│   ├── ActivityStore.swift                 (NEW: SQLite storage)
│   ├── StressAnalyzer.swift                (NEW: pure insight functions)
│   └── ActivityTracker.swift               (NEW: 15s polling)
└── Tests/HelioCoreTests/
    ├── StressAnalyzerTests.swift           (NEW)
    └── ActivityStoreTests.swift            (NEW)

HelioBarApp/
├── AppModel.swift                          (MODIFY: wire ActivityTracker)
├── MenuBarIcon.swift                       (MODIFY: add stress dot)
└── Views/
    ├── MenuContentView.swift               (MODIFY: add StressSummaryRow)
    ├── SettingsView.swift                  (MODIFY: add Activity section)
    ├── InsightsWindow.swift                (NEW: window controller + content)
    └── Components/
        ├── StressSummaryRow.swift          (NEW)
        ├── TimelineChart.swift             (NEW)
        ├── StressRankingList.swift         (NEW)
        └── ComparisonCard.swift            (NEW)
```

---

## Task 1: Add GRDB Dependency

**Files:**
- Modify: `HelioCore/Package.swift`

**Interfaces:**
- Consumes: nothing
- Produces: GRDB available as import in HelioCore targets

- [ ] **Step 1: Update Package.swift with GRDB dependency**

```swift
// HelioCore/Package.swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HelioCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HelioCore", targets: ["HelioCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
    ],
    targets: [
        .target(
            name: "HelioCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(name: "HelioCoreTests", dependencies: ["HelioCore"]),
    ]
)
```

- [ ] **Step 2: Verify dependency resolves**

Run: `cd HelioCore && swift package resolve`
Expected: Package resolves successfully, GRDB downloaded

- [ ] **Step 3: Verify build succeeds**

Run: `cd HelioCore && swift build`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add HelioCore/Package.swift
git commit -m "chore(HelioCore): add GRDB.swift dependency for SQLite storage"
```

---

## Task 2: Create ActivitySample Model

**Files:**
- Create: `HelioCore/Sources/HelioCore/ActivitySample.swift`
- Test: `HelioCore/Tests/HelioCoreTests/ActivitySampleTests.swift`

**Interfaces:**
- Consumes: `HRZone` from Models.swift
- Produces: `ActivitySample` struct with GRDB `FetchableRecord` and `PersistableRecord` conformance

- [ ] **Step 1: Write test for ActivitySample creation and coding**

```swift
// HelioCore/Tests/HelioCoreTests/ActivitySampleTests.swift
import Testing
import Foundation
@testable import HelioCore

@Suite("ActivitySample")
struct ActivitySampleTests {
    @Test("creates sample with all fields")
    func createSample() {
        let now = Date()
        let sample = ActivitySample(
            timestamp: now,
            hr: 85,
            bundleID: "com.apple.Safari",
            appName: "Safari",
            hrZone: .elevated
        )
        
        #expect(sample.timestamp == now)
        #expect(sample.hr == 85)
        #expect(sample.bundleID == "com.apple.Safari")
        #expect(sample.appName == "Safari")
        #expect(sample.hrZone == .elevated)
    }
    
    @Test("encodes and decodes via Codable")
    func codable() throws {
        let sample = ActivitySample(
            timestamp: Date(timeIntervalSince1970: 1000),
            hr: 72,
            bundleID: "com.test.app",
            appName: "TestApp",
            hrZone: .resting
        )
        
        let data = try JSONEncoder().encode(sample)
        let decoded = try JSONDecoder().decode(ActivitySample.self, from: data)
        
        #expect(decoded.hr == 72)
        #expect(decoded.bundleID == "com.test.app")
        #expect(decoded.hrZone == .resting)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd HelioCore && swift test --filter ActivitySampleTests`
Expected: FAIL with "cannot find 'ActivitySample' in scope"

- [ ] **Step 3: Implement ActivitySample**

```swift
// HelioCore/Sources/HelioCore/ActivitySample.swift
import Foundation
import GRDB

/// A single activity sample recorded every 15 seconds.
public struct ActivitySample: Codable, Sendable, Equatable {
    public var id: Int64?
    public let timestamp: Date
    public let hr: Int
    public let bundleID: String
    public let appName: String
    public let hrZone: HRZone
    
    public init(
        id: Int64? = nil,
        timestamp: Date,
        hr: Int,
        bundleID: String,
        appName: String,
        hrZone: HRZone
    ) {
        self.id = id
        self.timestamp = timestamp
        self.hr = hr
        self.bundleID = bundleID
        self.appName = appName
        self.hrZone = hrZone
    }
}

// MARK: - GRDB Record

extension ActivitySample: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "samples" }
    
    enum Columns: String, ColumnExpression {
        case id, timestamp, hr, bundleID = "bundle_id", appName = "app_name", hrZone = "hr_zone"
    }
    
    public init(row: Row) {
        id = row[Columns.id]
        timestamp = Date(timeIntervalSince1970: row[Columns.timestamp])
        hr = row[Columns.hr]
        bundleID = row[Columns.bundleID]
        appName = row[Columns.appName]
        hrZone = HRZone(rawValue: row[Columns.hrZone]) ?? .resting
    }
    
    public func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.timestamp] = timestamp.timeIntervalSince1970
        container[Columns.hr] = hr
        container[Columns.bundleID] = bundleID
        container[Columns.appName] = appName
        container[Columns.hrZone] = hrZone.rawValue
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd HelioCore && swift test --filter ActivitySampleTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add HelioCore/Sources/HelioCore/ActivitySample.swift HelioCore/Tests/HelioCoreTests/ActivitySampleTests.swift
git commit -m "feat(HelioCore): add ActivitySample model with GRDB record support"
```

---

## Task 3: Create ActivityStore

**Files:**
- Create: `HelioCore/Sources/HelioCore/ActivityStore.swift`
- Test: `HelioCore/Tests/HelioCoreTests/ActivityStoreTests.swift`

**Interfaces:**
- Consumes: `ActivitySample`
- Produces: `ActivityStore` class with `record(_:)`, `samples(from:to:)`, `deleteAll()`, `deleteBefore(_:)`, `exportCSV(from:to:)`, `storageSizeBytes`

- [ ] **Step 1: Write tests for ActivityStore**

```swift
// HelioCore/Tests/HelioCoreTests/ActivityStoreTests.swift
import Testing
import Foundation
@testable import HelioCore

@Suite("ActivityStore")
struct ActivityStoreTests {
    
    func makeStore() async throws -> ActivityStore {
        try await ActivityStore(inMemory: true)
    }
    
    @Test("records and retrieves samples")
    func recordAndRetrieve() async throws {
        let store = try await makeStore()
        let now = Date()
        
        let sample = ActivitySample(
            timestamp: now,
            hr: 80,
            bundleID: "com.test.app",
            appName: "Test",
            hrZone: .elevated
        )
        
        await store.record(sample)
        
        let retrieved = await store.samples(
            from: now.addingTimeInterval(-60),
            to: now.addingTimeInterval(60)
        )
        
        #expect(retrieved.count == 1)
        #expect(retrieved[0].hr == 80)
        #expect(retrieved[0].bundleID == "com.test.app")
    }
    
    @Test("returns empty array for empty date range")
    func emptyRange() async throws {
        let store = try await makeStore()
        let now = Date()
        
        let sample = ActivitySample(
            timestamp: now,
            hr: 75,
            bundleID: "com.test",
            appName: "Test",
            hrZone: .resting
        )
        await store.record(sample)
        
        // Query range that excludes the sample
        let retrieved = await store.samples(
            from: now.addingTimeInterval(100),
            to: now.addingTimeInterval(200)
        )
        
        #expect(retrieved.isEmpty)
    }
    
    @Test("deleteAll removes all samples")
    func deleteAll() async throws {
        let store = try await makeStore()
        let now = Date()
        
        for i in 0..<5 {
            let sample = ActivitySample(
                timestamp: now.addingTimeInterval(Double(i)),
                hr: 70 + i,
                bundleID: "com.test",
                appName: "Test",
                hrZone: .resting
            )
            await store.record(sample)
        }
        
        await store.deleteAll()
        
        let retrieved = await store.samples(
            from: .distantPast,
            to: .distantFuture
        )
        #expect(retrieved.isEmpty)
    }
    
    @Test("deleteBefore removes old samples only")
    func deleteBefore() async throws {
        let store = try await makeStore()
        let now = Date()
        
        // Old sample
        await store.record(ActivitySample(
            timestamp: now.addingTimeInterval(-100),
            hr: 70,
            bundleID: "com.old",
            appName: "Old",
            hrZone: .resting
        ))
        
        // New sample
        await store.record(ActivitySample(
            timestamp: now,
            hr: 80,
            bundleID: "com.new",
            appName: "New",
            hrZone: .elevated
        ))
        
        await store.deleteBefore(now.addingTimeInterval(-50))
        
        let retrieved = await store.samples(from: .distantPast, to: .distantFuture)
        #expect(retrieved.count == 1)
        #expect(retrieved[0].bundleID == "com.new")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd HelioCore && swift test --filter ActivityStoreTests`
Expected: FAIL with "cannot find 'ActivityStore' in scope"

- [ ] **Step 3: Implement ActivityStore**

```swift
// HelioCore/Sources/HelioCore/ActivityStore.swift
import Foundation
import GRDB

/// SQLite-backed storage for activity samples.
@MainActor
public final class ActivityStore: Sendable {
    private let dbQueue: DatabaseQueue
    
    /// Initialize with file-based database at default location.
    public init() async throws {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dbURL = appSupport.appendingPathComponent("activity.db")
        
        try FileManager.default.createDirectory(
            at: appSupport,
            withIntermediateDirectories: true
        )
        
        dbQueue = try DatabaseQueue(path: dbURL.path)
        try await migrate()
    }
    
    /// Initialize with in-memory database for testing.
    public init(inMemory: Bool) async throws {
        dbQueue = try DatabaseQueue()
        try await migrate()
    }
    
    private func migrate() async throws {
        try dbQueue.write { db in
            try db.create(table: "samples", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .double).notNull()
                t.column("hr", .integer).notNull()
                t.column("bundle_id", .text).notNull()
                t.column("app_name", .text).notNull()
                t.column("hr_zone", .text).notNull()
            }
            
            try db.create(
                index: "idx_samples_timestamp",
                on: "samples",
                columns: ["timestamp"],
                ifNotExists: true
            )
            try db.create(
                index: "idx_samples_bundle_id",
                on: "samples",
                columns: ["bundle_id"],
                ifNotExists: true
            )
        }
    }
    
    /// Record a single sample.
    public func record(_ sample: ActivitySample) async {
        do {
            try dbQueue.write { db in
                var mutable = sample
                try mutable.insert(db)
            }
        } catch {
            print("ActivityStore.record error: \(error)")
        }
    }
    
    /// Query samples in date range, ordered by timestamp.
    public func samples(from start: Date, to end: Date) async -> [ActivitySample] {
        do {
            return try dbQueue.read { db in
                try ActivitySample
                    .filter(ActivitySample.Columns.timestamp >= start.timeIntervalSince1970)
                    .filter(ActivitySample.Columns.timestamp <= end.timeIntervalSince1970)
                    .order(ActivitySample.Columns.timestamp)
                    .fetchAll(db)
            }
        } catch {
            print("ActivityStore.samples error: \(error)")
            return []
        }
    }
    
    /// Delete all stored data.
    public func deleteAll() async {
        do {
            try dbQueue.write { db in
                try ActivitySample.deleteAll(db)
            }
        } catch {
            print("ActivityStore.deleteAll error: \(error)")
        }
    }
    
    /// Delete samples before given date.
    public func deleteBefore(_ date: Date) async {
        do {
            try dbQueue.write { db in
                try ActivitySample
                    .filter(ActivitySample.Columns.timestamp < date.timeIntervalSince1970)
                    .deleteAll(db)
            }
        } catch {
            print("ActivityStore.deleteBefore error: \(error)")
        }
    }
    
    /// Export samples to CSV, returns file URL.
    public func exportCSV(from start: Date, to end: Date) async -> URL? {
        let samples = await samples(from: start, to: end)
        guard !samples.isEmpty else { return nil }
        
        let formatter = ISO8601DateFormatter()
        var csv = "timestamp,hr,bundle_id,app_name,hr_zone\n"
        
        for s in samples {
            csv += "\(formatter.string(from: s.timestamp)),\(s.hr),\"\(s.bundleID)\",\"\(s.appName)\",\(s.hrZone.rawValue)\n"
        }
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("heliobar-export-\(Date().timeIntervalSince1970).csv")
        
        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            print("ActivityStore.exportCSV error: \(error)")
            return nil
        }
    }
    
    /// Total storage size in bytes.
    public var storageSizeBytes: Int64 {
        get async {
            do {
                return try dbQueue.read { db in
                    let row = try Row.fetchOne(db, sql: "SELECT page_count * page_size as size FROM pragma_page_count(), pragma_page_size()")
                    return row?["size"] ?? 0
                }
            } catch {
                return 0
            }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd HelioCore && swift test --filter ActivityStoreTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add HelioCore/Sources/HelioCore/ActivityStore.swift HelioCore/Tests/HelioCoreTests/ActivityStoreTests.swift
git commit -m "feat(HelioCore): add ActivityStore with SQLite persistence via GRDB"
```

---

## Task 4: Create StressAnalyzer

**Files:**
- Create: `HelioCore/Sources/HelioCore/StressAnalyzer.swift`
- Test: `HelioCore/Tests/HelioCoreTests/StressAnalyzerTests.swift`

**Interfaces:**
- Consumes: `ActivitySample`, `HRZone`
- Produces: `AppStressStats`, `TimelineSegment`, `AppStressComparison`, `StressAnalyzer` with static functions `computeBaseline(_:)`, `rankByStress(_:baseline:)`, `buildTimeline(_:mergeThreshold:)`, `compare(current:previous:)`

- [ ] **Step 1: Write tests for StressAnalyzer**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd HelioCore && swift test --filter StressAnalyzerTests`
Expected: FAIL with "cannot find 'StressAnalyzer' in scope"

- [ ] **Step 3: Implement StressAnalyzer and data types**

```swift
// HelioCore/Sources/HelioCore/StressAnalyzer.swift
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
            
            let changePercent: Double
            if prev.elevatedRatio > 0 {
                changePercent = ((curr.elevatedRatio - prev.elevatedRatio) / prev.elevatedRatio) * 100
            } else if curr.elevatedRatio > 0 {
                changePercent = 100 // From 0 to something = 100% increase
            } else {
                changePercent = 0
            }
            
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd HelioCore && swift test --filter StressAnalyzerTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add HelioCore/Sources/HelioCore/StressAnalyzer.swift HelioCore/Tests/HelioCoreTests/StressAnalyzerTests.swift
git commit -m "feat(HelioCore): add StressAnalyzer with baseline calculation and ranking"
```

---

## Task 5: Create ActivityTracker

**Files:**
- Create: `HelioCore/Sources/HelioCore/ActivityTracker.swift`

**Interfaces:**
- Consumes: `ActivityStore`, `HealthStore`, `ActivitySample`, `HRZone`
- Produces: `ActivityTracker` class with `start()`, `stop()`, `isTracking: Bool`

- [ ] **Step 1: Implement ActivityTracker**

```swift
// HelioCore/Sources/HelioCore/ActivityTracker.swift
import Foundation
import AppKit

/// Polls the frontmost app every 15 seconds and records alongside HR.
@MainActor
public final class ActivityTracker {
    private let store: ActivityStore
    private let healthStore: HealthStore
    private var timer: Timer?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    
    public var isTracking: Bool { timer != nil }
    
    public init(store: ActivityStore, healthStore: HealthStore) {
        self.store = store
        self.healthStore = healthStore
    }
    
    /// Start 15-second polling.
    public func start() {
        guard timer == nil else { return }
        
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        
        // Immediately record first sample
        tick()
        
        // Observe sleep/wake
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.pauseForSleep()
        }
        
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resumeAfterWake()
        }
    }
    
    /// Stop tracking.
    public func stop() {
        timer?.invalidate()
        timer = nil
        
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
            self.sleepObserver = nil
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }
    
    private func tick() {
        // Skip if no HR connected
        guard let hr = healthStore.liveHR else { return }
        
        // Get frontmost app
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else { return }
        
        let sample = ActivitySample(
            timestamp: Date(),
            hr: hr,
            bundleID: bundleID,
            appName: app.localizedName ?? bundleID,
            hrZone: HRZone.zone(for: hr, maxHR: healthStore.maxHR)
        )
        
        Task {
            await store.record(sample)
        }
    }
    
    private func pauseForSleep() {
        timer?.invalidate()
        timer = nil
    }
    
    private func resumeAfterWake() {
        guard sleepObserver != nil else { return } // Only if we were tracking
        
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }
}
```

- [ ] **Step 2: Verify build succeeds**

Run: `cd HelioCore && swift build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add HelioCore/Sources/HelioCore/ActivityTracker.swift
git commit -m "feat(HelioCore): add ActivityTracker with 15s polling and sleep/wake handling"
```

---

## Task 6: Add Stress Dot to Menu Bar

**Files:**
- Modify: `HelioBarApp/MenuBarIcon.swift`

**Interfaces:**
- Consumes: `HealthStore.hrZone`, `ActivityTracker.isTracking`
- Produces: Stress indicator dot in menu bar when tracking + elevated

- [ ] **Step 1: Read current MenuBarIcon implementation**

Run: `cat HelioBarApp/MenuBarIcon.swift`

- [ ] **Step 2: Add stress dot to MenuBarIcon**

Add `isTracking: Bool` parameter and render dot when tracking and not resting:

```swift
// In MenuBarIcon.swift, modify the body to include:

// After the trend arrow, add:
if isTracking && zone != .resting && zone != nil {
    Circle()
        .fill(zone == .high ? Theme.high : Theme.elevated)
        .frame(width: 6, height: 6)
}
```

- [ ] **Step 3: Verify build succeeds**

Run: `swift build` (from project root)
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add HelioBarApp/MenuBarIcon.swift
git commit -m "feat(MenuBar): add stress indicator dot when tracking and elevated"
```

---

## Task 7: Create StressSummaryRow Component

**Files:**
- Create: `HelioBarApp/Views/Components/StressSummaryRow.swift`

**Interfaces:**
- Consumes: `Theme` colors and fonts
- Produces: `StressSummaryRow` view with `topApp: String?`, `elevatedMinutes: Int`, `appsTracked: Int`, `onTap: () -> Void`

- [ ] **Step 1: Implement StressSummaryRow**

```swift
// HelioBarApp/Views/Components/StressSummaryRow.swift
import SwiftUI

/// Compact stress summary shown in the popover.
struct StressSummaryRow: View {
    let topApp: String?
    let elevatedMinutes: Int
    let appsTracked: Int
    var onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(Theme.elevated)
                
                if let topApp, elevatedMinutes > 0 {
                    Text("\(topApp) (\(elevatedMinutes)m elevated)")
                        .lineLimit(1)
                } else {
                    Text("No stress data yet")
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if appsTracked > 0 {
                    Text("\(appsTracked) apps")
                        .foregroundStyle(.secondary)
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .font(Theme.captionFont)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .cardSurface()
        }
        .buttonStyle(.plain)
    }
}

#if !SWIFT_PACKAGE
#Preview("with data") {
    StressSummaryRow(topApp: "Slack", elevatedMinutes: 42, appsTracked: 5, onTap: {})
        .padding()
        .background(.black)
}

#Preview("no data") {
    StressSummaryRow(topApp: nil, elevatedMinutes: 0, appsTracked: 0, onTap: {})
        .padding()
        .background(.black)
}
#endif
```

- [ ] **Step 2: Verify build succeeds**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add HelioBarApp/Views/Components/StressSummaryRow.swift
git commit -m "feat(UI): add StressSummaryRow component for popover"
```

---

## Task 8: Add Activity Tracking Settings Section

**Files:**
- Modify: `HelioBarApp/Views/SettingsView.swift`

**Interfaces:**
- Consumes: `@AppStorage("activityTrackingEnabled")`, `ActivityStore.storageSizeBytes`
- Produces: Settings section with toggle, storage size, View Insights / Export / Delete buttons

- [ ] **Step 1: Add Activity Tracking section to SettingsView**

Add new section after the existing sections:

```swift
// Add to SettingsView.swift

@AppStorage("activityTrackingEnabled") private var activityTrackingEnabled = false
@State private var storageSizeText = "Calculating..."
@State private var showDeleteConfirmation = false

// Add this Section to the Form body:
Section {
    Toggle("Track app activity", isOn: $activityTrackingEnabled)
    Text("Records which app is active alongside your heart rate")
        .font(.caption).foregroundStyle(.secondary)
    
    if activityTrackingEnabled {
        HStack {
            Text("Data stored")
            Spacer()
            Text(storageSizeText)
                .foregroundStyle(.secondary)
        }
        
        Button("View Insights") {
            // Will wire up in Task 11
            NotificationCenter.default.post(name: .openInsightsWindow, object: nil)
        }
        
        Button("Export All Data...") {
            // Will wire up in Task 11
            NotificationCenter.default.post(name: .exportActivityData, object: nil)
        }
        
        Button("Delete All Data...", role: .destructive) {
            showDeleteConfirmation = true
        }
        .confirmationDialog("Delete all activity data?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                NotificationCenter.default.post(name: .deleteActivityData, object: nil)
            }
        } message: {
            Text("This cannot be undone.")
        }
    }
} header: {
    Label("Activity Tracking", systemImage: "chart.bar.fill")
}

// Add notification names at top of file or in extension:
extension Notification.Name {
    static let openInsightsWindow = Notification.Name("openInsightsWindow")
    static let exportActivityData = Notification.Name("exportActivityData")
    static let deleteActivityData = Notification.Name("deleteActivityData")
}
```

- [ ] **Step 2: Verify build succeeds**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add HelioBarApp/Views/SettingsView.swift
git commit -m "feat(Settings): add Activity Tracking section with toggle and data management"
```

---

## Task 9: Create InsightsWindow with TimelineChart

**Files:**
- Create: `HelioBarApp/Views/InsightsWindow.swift`
- Create: `HelioBarApp/Views/Components/TimelineChart.swift`

**Interfaces:**
- Consumes: `ActivityStore`, `StressAnalyzer`, `TimelineSegment`, `Theme`
- Produces: `InsightsWindowController` class with `showWindow()`, `InsightsView` SwiftUI view, `TimelineChart` component

- [ ] **Step 1: Implement TimelineChart**

```swift
// HelioBarApp/Views/Components/TimelineChart.swift
import SwiftUI
import HelioCore

/// HR timeline with colored segments per app.
struct TimelineChart: View {
    let segments: [TimelineSegment]
    let samples: [ActivitySample]
    
    var body: some View {
        GeometryReader { geo in
            if samples.count >= 2 {
                ZStack(alignment: .bottom) {
                    // App segment backgrounds
                    segmentBackgrounds(in: geo)
                    
                    // HR line
                    hrLine(in: geo)
                }
            } else {
                Text("Collecting data...")
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    @ViewBuilder
    private func segmentBackgrounds(in geo: GeometryProxy) -> some View {
        let timeRange = timeRange
        guard timeRange.duration > 0 else { return }
        
        ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
            let startX = xPosition(for: segment.start, in: geo, range: timeRange)
            let endX = xPosition(for: segment.end, in: geo, range: timeRange)
            
            Rectangle()
                .fill(Theme.color(for: segment.zone).opacity(0.15))
                .frame(width: max(endX - startX, 2))
                .position(x: startX + (endX - startX) / 2, y: geo.size.height / 2)
        }
    }
    
    @ViewBuilder
    private func hrLine(in geo: GeometryProxy) -> some View {
        let range = timeRange
        let hrRange = hrRange
        
        Path { path in
            var first = true
            for sample in samples.sorted(by: { $0.timestamp < $1.timestamp }) {
                let x = xPosition(for: sample.timestamp, in: geo, range: range)
                let y = yPosition(for: sample.hr, in: geo, range: hrRange)
                
                if first {
                    path.move(to: CGPoint(x: x, y: y))
                    first = false
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .stroke(Theme.elevated, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
    
    private var timeRange: (start: Date, end: Date, duration: TimeInterval) {
        guard let first = samples.min(by: { $0.timestamp < $1.timestamp }),
              let last = samples.max(by: { $0.timestamp < $1.timestamp }) else {
            return (Date(), Date(), 0)
        }
        return (first.timestamp, last.timestamp, last.timestamp.timeIntervalSince(first.timestamp))
    }
    
    private var hrRange: (min: Int, max: Int) {
        let hrs = samples.map(\.hr)
        return (hrs.min() ?? 60, hrs.max() ?? 100)
    }
    
    private func xPosition(for date: Date, in geo: GeometryProxy, range: (start: Date, end: Date, duration: TimeInterval)) -> CGFloat {
        guard range.duration > 0 else { return 0 }
        let offset = date.timeIntervalSince(range.start)
        return geo.size.width * (offset / range.duration)
    }
    
    private func yPosition(for hr: Int, in geo: GeometryProxy, range: (min: Int, max: Int)) -> CGFloat {
        let span = max(range.max - range.min, 1)
        let normalized = Double(hr - range.min) / Double(span)
        return geo.size.height * (1 - normalized)
    }
}
```

- [ ] **Step 2: Implement InsightsWindow**

```swift
// HelioBarApp/Views/InsightsWindow.swift
import SwiftUI
import AppKit
import HelioCore

/// Window controller for the Insights window.
final class InsightsWindowController {
    private var window: NSWindow?
    private let store: ActivityStore
    
    init(store: ActivityStore) {
        self.store = store
    }
    
    func showWindow() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        
        let contentView = InsightsView(store: store)
        let hostingController = NSHostingController(rootView: contentView)
        
        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "Stress Insights"
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        newWindow.setContentSize(NSSize(width: 500, height: 600))
        newWindow.minSize = NSSize(width: 400, height: 400)
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        
        self.window = newWindow
    }
}

/// Date range options for insights.
enum InsightsDateRange: String, CaseIterable {
    case today = "Today"
    case thisWeek = "This Week"
    case thisMonth = "This Month"
    
    var dateRange: (start: Date, end: Date) {
        let now = Date()
        let calendar = Calendar.current
        
        switch self {
        case .today:
            let start = calendar.startOfDay(for: now)
            return (start, now)
        case .thisWeek:
            let start = calendar.date(byAdding: .day, value: -7, to: now)!
            return (start, now)
        case .thisMonth:
            let start = calendar.date(byAdding: .month, value: -1, to: now)!
            return (start, now)
        }
    }
}

/// Main insights view content.
struct InsightsView: View {
    let store: ActivityStore
    
    @State private var dateRange: InsightsDateRange = .today
    @State private var samples: [ActivitySample] = []
    @State private var stats: [AppStressStats] = []
    @State private var timeline: [TimelineSegment] = []
    @State private var baseline: Double?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Stress Insights")
                    .font(.headline)
                Spacer()
                Picker("", selection: $dateRange) {
                    ForEach(InsightsDateRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(spacing: 16) {
                    // Timeline
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TIMELINE")
                            .font(Theme.cardTitleFont)
                            .foregroundStyle(.secondary)
                        
                        TimelineChart(segments: timeline, samples: samples)
                            .frame(height: 120)
                            .cardSurface()
                    }
                    
                    // Baseline
                    if let baseline {
                        HStack {
                            Text("Baseline:")
                            Text("\(Int(baseline)) bpm")
                                .fontWeight(.semibold)
                            Text("(your resting average)")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .font(Theme.captionFont)
                    }
                    
                    // App ranking
                    VStack(alignment: .leading, spacing: 8) {
                        Text("APPS BY STRESS")
                            .font(Theme.cardTitleFont)
                            .foregroundStyle(.secondary)
                        
                        StressRankingList(stats: stats)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 400, minHeight: 400)
        .task(id: dateRange) {
            await loadData()
        }
    }
    
    private func loadData() async {
        let range = dateRange.dateRange
        samples = await store.samples(from: range.start, to: range.end)
        baseline = StressAnalyzer.computeBaseline(samples: samples)
        stats = StressAnalyzer.rankByStress(samples: samples, baseline: baseline)
        timeline = StressAnalyzer.buildTimeline(samples: samples)
    }
}
```

- [ ] **Step 3: Verify build succeeds**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add HelioBarApp/Views/InsightsWindow.swift HelioBarApp/Views/Components/TimelineChart.swift
git commit -m "feat(UI): add InsightsWindow with TimelineChart"
```

---

## Task 10: Create StressRankingList and ComparisonCard

**Files:**
- Create: `HelioBarApp/Views/Components/StressRankingList.swift`
- Create: `HelioBarApp/Views/Components/ComparisonCard.swift`

**Interfaces:**
- Consumes: `AppStressStats`, `AppStressComparison`, `Theme`
- Produces: `StressRankingList` view, `ComparisonCard` view

- [ ] **Step 1: Implement StressRankingList**

```swift
// HelioBarApp/Views/Components/StressRankingList.swift
import SwiftUI
import HelioCore

/// Vertical list of apps ranked by stress (delta from baseline).
struct StressRankingList: View {
    let stats: [AppStressStats]
    
    var body: some View {
        VStack(spacing: 8) {
            if stats.isEmpty {
                Text("No data yet")
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            } else {
                ForEach(Array(stats.prefix(10).enumerated()), id: \.element.bundleID) { index, stat in
                    StressRankingRow(rank: index + 1, stat: stat, maxDelta: stats.first?.deltaFromBaseline ?? 1)
                }
            }
        }
        .cardSurface()
    }
}

struct StressRankingRow: View {
    let rank: Int
    let stat: AppStressStats
    let maxDelta: Double
    
    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank).")
                .font(Theme.captionFont)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)
            
            Text(stat.appName)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Delta bar
            GeometryReader { geo in
                let normalizedWidth = maxDelta > 0 ? max(stat.deltaFromBaseline / maxDelta, 0) : 0
                RoundedRectangle(cornerRadius: 2)
                    .fill(deltaColor)
                    .frame(width: geo.size.width * normalizedWidth)
            }
            .frame(width: 60, height: 8)
            
            Text(deltaText)
                .font(Theme.captionFont.monospacedDigit())
                .foregroundStyle(deltaColor)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    private var deltaText: String {
        let delta = Int(stat.deltaFromBaseline.rounded())
        return delta >= 0 ? "+\(delta) bpm" : "\(delta) bpm"
    }
    
    private var deltaColor: Color {
        if stat.deltaFromBaseline > 15 {
            return Theme.high
        } else if stat.deltaFromBaseline > 5 {
            return Theme.elevated
        } else {
            return Theme.resting
        }
    }
}

#if !SWIFT_PACKAGE
#Preview {
    StressRankingList(stats: [
        AppStressStats(bundleID: "com.slack", appName: "Slack", totalSamples: 100, avgHR: 88, maxHR: 105, timeInElevated: 900, elevatedRatio: 0.6, deltaFromBaseline: 18),
        AppStressStats(bundleID: "com.zoom", appName: "Zoom", totalSamples: 50, avgHR: 82, maxHR: 98, timeInElevated: 450, elevatedRatio: 0.5, deltaFromBaseline: 12),
        AppStressStats(bundleID: "com.vscode", appName: "VS Code", totalSamples: 200, avgHR: 73, maxHR: 85, timeInElevated: 300, elevatedRatio: 0.1, deltaFromBaseline: 3),
    ])
    .padding()
    .background(.black)
}
#endif
```

- [ ] **Step 2: Implement ComparisonCard**

```swift
// HelioBarApp/Views/Components/ComparisonCard.swift
import SwiftUI
import HelioCore

/// Week-over-week comparison card.
struct ComparisonCard: View {
    let comparisons: [AppStressComparison]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("THIS WEEK VS LAST")
                .font(Theme.cardTitleFont)
                .foregroundStyle(.secondary)
            
            if comparisons.isEmpty {
                Text("Not enough data for comparison")
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(comparisons.prefix(5), id: \.bundleID) { comparison in
                    ComparisonRow(comparison: comparison)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardSurface()
    }
}

struct ComparisonRow: View {
    let comparison: AppStressComparison
    
    var body: some View {
        HStack {
            Text(comparison.appName)
                .lineLimit(1)
            
            Spacer()
            
            HStack(spacing: 4) {
                Image(systemName: arrowIcon)
                    .foregroundStyle(changeColor)
                
                Text(changeText)
                    .font(Theme.captionFont.monospacedDigit())
                    .foregroundStyle(changeColor)
            }
        }
    }
    
    private var arrowIcon: String {
        if comparison.changePercent > 5 {
            return "arrow.up"
        } else if comparison.changePercent < -5 {
            return "arrow.down"
        } else {
            return "minus"
        }
    }
    
    private var changeColor: Color {
        if comparison.changePercent > 5 {
            return Theme.high
        } else if comparison.changePercent < -5 {
            return Theme.resting
        } else {
            return .secondary
        }
    }
    
    private var changeText: String {
        let pct = Int(abs(comparison.changePercent).rounded())
        return "\(pct)%"
    }
}

#if !SWIFT_PACKAGE
#Preview {
    ComparisonCard(comparisons: [
        AppStressComparison(bundleID: "com.slack", appName: "Slack", currentElevatedRatio: 0.5, previousElevatedRatio: 0.4, changePercent: 25),
        AppStressComparison(bundleID: "com.zoom", appName: "Zoom", currentElevatedRatio: 0.3, previousElevatedRatio: 0.35, changePercent: -14),
        AppStressComparison(bundleID: "com.vscode", appName: "VS Code", currentElevatedRatio: 0.1, previousElevatedRatio: 0.1, changePercent: 0),
    ])
    .padding()
    .background(.black)
}
#endif
```

- [ ] **Step 3: Verify build succeeds**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add HelioBarApp/Views/Components/StressRankingList.swift HelioBarApp/Views/Components/ComparisonCard.swift
git commit -m "feat(UI): add StressRankingList and ComparisonCard components"
```

---

## Task 11: Wire Up in AppModel and MenuContentView

**Files:**
- Modify: `HelioBarApp/AppModel.swift`
- Modify: `HelioBarApp/Views/MenuContentView.swift`

**Interfaces:**
- Consumes: All previously created components
- Produces: Full integration: tracking starts/stops based on settings, popover shows summary, insights window opens

- [ ] **Step 1: Add ActivityTracker to AppModel**

```swift
// In AppModel.swift, add:

import HelioCore

// Add properties:
private(set) var activityStore: ActivityStore?
private var activityTracker: ActivityTracker?
private var insightsController: InsightsWindowController?

// In start(), add after monitor setup:
Task {
    do {
        let store = try await ActivityStore()
        self.activityStore = store
        self.activityTracker = ActivityTracker(store: store, healthStore: self.store)
        self.insightsController = InsightsWindowController(store: store)
        
        // Start tracking if enabled
        if UserDefaults.standard.bool(forKey: "activityTrackingEnabled") {
            self.activityTracker?.start()
        }
        
        // Observe settings changes
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateTrackingState()
        }
        
        // Observe window/export/delete requests
        NotificationCenter.default.addObserver(
            forName: .openInsightsWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.insightsController?.showWindow()
        }
        
        NotificationCenter.default.addObserver(
            forName: .deleteActivityData,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.activityStore?.deleteAll() }
        }
    } catch {
        print("Failed to initialize ActivityStore: \(error)")
    }
}

// Add helper method:
private func updateTrackingState() {
    let enabled = UserDefaults.standard.bool(forKey: "activityTrackingEnabled")
    if enabled && !(activityTracker?.isTracking ?? false) {
        activityTracker?.start()
    } else if !enabled && (activityTracker?.isTracking ?? false) {
        activityTracker?.stop()
    }
}

// Add public accessor:
var isActivityTracking: Bool {
    activityTracker?.isTracking ?? false
}
```

- [ ] **Step 2: Add StressSummaryRow to MenuContentView**

```swift
// In MenuContentView.swift, add after BatteryPill:

@State private var topStressApp: String?
@State private var elevatedMinutes: Int = 0
@State private var appsTracked: Int = 0
@AppStorage("activityTrackingEnabled") private var activityTrackingEnabled = false

// In body, after BatteryPill:
if activityTrackingEnabled {
    StressSummaryRow(
        topApp: topStressApp,
        elevatedMinutes: elevatedMinutes,
        appsTracked: appsTracked,
        onTap: {
            NotificationCenter.default.post(name: .openInsightsWindow, object: nil)
        }
    )
    .task {
        await loadStressSummary()
    }
}

// Add helper:
private func loadStressSummary() async {
    guard let store = (NSApp.delegate as? AppDelegate)?.model.activityStore else { return }
    
    let today = Calendar.current.startOfDay(for: Date())
    let samples = await store.samples(from: today, to: Date())
    let stats = StressAnalyzer.rankByStress(samples: samples)
    
    topStressApp = stats.first?.appName
    elevatedMinutes = Int(stats.map(\.timeInElevated).reduce(0, +) / 60)
    appsTracked = stats.count
}
```

- [ ] **Step 3: Update MenuBarIcon call to include isTracking**

In the file that creates MenuBarIcon, pass the tracking state:

```swift
MenuBarIcon(
    hr: store.liveHR,
    zone: store.hrZone,
    trend: store.hrTrend,
    isTracking: model.isActivityTracking
)
```

- [ ] **Step 4: Verify build succeeds**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 5: Manual test**

- [ ] Launch app, go to Settings, enable Activity Tracking
- [ ] Verify tracking indicator appears in menu bar when HR elevated
- [ ] Verify StressSummaryRow appears in popover
- [ ] Click summary row, verify Insights window opens
- [ ] Use Mac for a few minutes, verify data populates

- [ ] **Step 6: Commit**

```bash
git add HelioBarApp/AppModel.swift HelioBarApp/Views/MenuContentView.swift HelioBarApp/MenuBarIcon.swift
git commit -m "feat: wire up ActivityTracker in AppModel and add StressSummaryRow to popover"
```

---

## Task 12: Final Integration and Polish

**Files:**
- Various minor fixes based on testing

**Interfaces:**
- Consumes: All components
- Produces: Working, polished feature

- [ ] **Step 1: Run full test suite**

Run: `cd HelioCore && swift test`
Expected: All tests pass

- [ ] **Step 2: Build release**

Run: `./scripts/install-and-run.sh`
Expected: App builds, installs, and launches

- [ ] **Step 3: End-to-end manual test**

- [ ] Fresh launch with no activity data
- [ ] Enable tracking in Settings
- [ ] Use Mac normally for 2-3 minutes
- [ ] Check popover shows stress summary
- [ ] Open Insights window
- [ ] Verify timeline and ranking populate
- [ ] Export CSV, verify file contents
- [ ] Delete all data, verify cleared
- [ ] Disable tracking, verify no new samples

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat: complete Work Stress Correlation feature

- Track HR + active app every 15s when HR connected
- SQLite storage via GRDB with unlimited local retention
- Menu bar stress indicator dot when elevated
- Popover summary row linking to insights
- Insights window with timeline, app ranking, baseline comparison
- Settings: toggle, export, delete data

Implements spec: docs/superpowers/specs/2026-10-06-work-stress-correlation-design.md"
```

---

## Summary

| Task | Component | Tests |
|------|-----------|-------|
| 1 | GRDB dependency | Build check |
| 2 | ActivitySample model | ActivitySampleTests |
| 3 | ActivityStore | ActivityStoreTests |
| 4 | StressAnalyzer | StressAnalyzerTests |
| 5 | ActivityTracker | Build check |
| 6 | Menu bar stress dot | Manual |
| 7 | StressSummaryRow | Preview |
| 8 | Settings section | Manual |
| 9 | InsightsWindow + TimelineChart | Manual |
| 10 | StressRankingList + ComparisonCard | Preview |
| 11 | Full wiring | Integration |
| 12 | Polish | E2E manual |

Total: 12 tasks, ~2-3 hours estimated implementation time.
