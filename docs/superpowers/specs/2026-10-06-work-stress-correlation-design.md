# Work Stress Correlation — Design Spec

**Date:** 2026-10-06  
**Status:** Approved  
**Author:** Claude + Khiem

## Overview

Add activity tracking to HelioBar: record which macOS app is active alongside heart rate every 15 seconds. Provide insights showing which apps correlate with elevated HR ("stress").

### Goals

- Track HR + frontmost app every 15 seconds when HR connected
- Store data locally (SQLite), unlimited retention, user manages deletion
- Show stress indicator in menu bar when elevated
- Show summary in popover with link to detailed insights
- Detailed insights window: app ranking, timeline, comparisons, export

### Non-Goals

- Calendar integration (removed from scope)
- Cloud sync
- Automatic categorization of apps

## Data Model

```swift
/// Stored every 15 seconds when HR connected
public struct ActivitySample: Codable, Sendable {
    public let timestamp: Date
    public let hr: Int
    public let bundleID: String      // "com.tinyspeck.slackmacgap"
    public let appName: String       // "Slack"
    public let hrZone: HRZone        // .resting / .elevated / .high
}

/// Computed insights (not stored)
public struct AppStressStats: Sendable {
    public let bundleID: String
    public let appName: String
    public let totalSamples: Int
    public let avgHR: Double
    public let maxHR: Int
    public let timeInElevated: TimeInterval  // seconds in elevated/high zone
    public let elevatedRatio: Double         // 0.0 - 1.0
    public let deltaFromBaseline: Double     // e.g., +14.2 means 14 bpm above resting baseline
}

/// For timeline visualization
public struct TimelineSegment: Sendable {
    public let start: Date
    public let end: Date
    public let appName: String
    public let avgHR: Double
    public let zone: HRZone
}

/// Week-over-week comparison
public struct AppStressComparison: Sendable {
    public let bundleID: String
    public let appName: String
    public let currentElevatedRatio: Double
    public let previousElevatedRatio: Double
    public var changePercent: Double  // positive = more stress
}
```

## Storage

### Database

**Location:** `~/Library/Containers/com.heliobar/Data/Library/Application Support/activity.db`

**Schema:**

```sql
CREATE TABLE samples (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp INTEGER NOT NULL,
    hr INTEGER NOT NULL,
    bundle_id TEXT NOT NULL,
    app_name TEXT NOT NULL,
    hr_zone INTEGER NOT NULL
);

CREATE INDEX idx_samples_timestamp ON samples(timestamp);
CREATE INDEX idx_samples_bundle_id ON samples(bundle_id);
```

### ActivityStore API

```swift
@MainActor
public final class ActivityStore {
    /// Record a single sample
    func record(_ sample: ActivitySample) async
    
    /// Query samples in date range
    func samples(from: Date, to: Date) async -> [ActivitySample]
    
    /// Compute per-app stats for date range
    func appStats(from: Date, to: Date) async -> [AppStressStats]
    
    /// Build timeline segments for visualization
    func timeline(from: Date, to: Date) async -> [TimelineSegment]
    
    /// Delete all stored data
    func deleteAll() async
    
    /// Delete samples before given date
    func deleteBefore(_ date: Date) async
    
    /// Export to CSV file, returns file URL
    func exportCSV(from: Date, to: Date) async -> URL
    
    /// Total storage size in bytes
    var storageSizeBytes: Int64 { get async }
}
```

### Implementation

Use **GRDB.swift** as SQLite wrapper:
- Clean Swift API
- Migration support
- SPM-compatible
- Well-maintained

Add to `HelioCore/Package.swift`:
```swift
.package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0")
```

## Activity Tracking

### ActivityTracker

```swift
@MainActor
public final class ActivityTracker {
    private let store: ActivityStore
    private let healthStore: HealthStore
    private var timer: Timer?
    
    public var isTracking: Bool { timer != nil }
    
    /// Start 15-second polling
    public func start()
    
    /// Stop tracking
    public func stop()
}
```

### Polling Logic

Every 15 seconds:

```swift
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
    
    Task { await store.record(sample) }
}
```

### Edge Cases

| Scenario | Behavior |
|----------|----------|
| No HR connected | Skip sample (no app-only tracking) |
| Screen locked / sleep | Pause tracking via NSWorkspace notifications |
| HelioBar frontmost | Record normally |
| App without bundle ID | Skip sample |

### Privacy Note

Tracking only runs when HR is connected. No HR = no app tracking. This ties the feature to its purpose (correlating HR with apps) and prevents pure activity surveillance.

## Stress Analysis

### StressAnalyzer

Pure functions, no state:

```swift
public struct StressAnalyzer {
    /// Compute resting baseline HR from samples
    public static func computeBaseline(
        samples: [ActivitySample]
    ) -> Double?
    
    /// Rank apps by delta from baseline (most stress-inducing first)
    public static func rankByStress(
        samples: [ActivitySample],
        baseline: Double? = nil  // auto-computed if nil
    ) -> [AppStressStats]
    
    /// Build timeline segments, merging consecutive same-app samples
    public static func buildTimeline(
        samples: [ActivitySample],
        mergeThreshold: TimeInterval = 60
    ) -> [TimelineSegment]
    
    /// Compare two periods
    public static func compare(
        current: [AppStressStats],
        previous: [AppStressStats]
    ) -> [AppStressComparison]
    
    /// Average HR by hour of day (0-23)
    public static func hourlyPattern(
        samples: [ActivitySample]
    ) -> [Int: Double]
}
```

### Baseline Calculation

Baseline = average HR across all samples where `hrZone == .resting`. This represents user's typical calm state while working.

```swift
public static func computeBaseline(samples: [ActivitySample]) -> Double? {
    let restingSamples = samples.filter { $0.hrZone == .resting }
    guard !restingSamples.isEmpty else { return nil }
    return Double(restingSamples.map(\.hr).reduce(0, +)) / Double(restingSamples.count)
}
```

If no resting samples exist (user always elevated), fallback to overall average minus 10 bpm as rough estimate.

### Ranking Algorithm

1. Compute baseline from all samples
2. Group samples by `bundleID`
3. For each app:
   - Count total samples
   - Count samples where `hrZone != .resting`
   - Compute `elevatedRatio = elevatedSamples / totalSamples`
   - Compute `avgHR`, `maxHR`, `timeInElevated` (samples × 15s)
   - Compute `deltaFromBaseline = avgHR - baseline`
4. Sort by `deltaFromBaseline` descending (apps that raise HR most)

### Timeline Merging

Consecutive samples with same `bundleID` within 60 seconds merge into one `TimelineSegment`. Prevents fragmented visualization.

## UI Components

### Menu Bar Enhancement

Add stress indicator dot when tracking + elevated:

```swift
// In MenuBarIcon
HStack(spacing: 2) {
    Text("♥").foregroundStyle(zoneColor)
    Text("\(hr)").monospacedDigit()
    Text(trendArrow)
    
    // Stress dot: visible when tracking AND not resting
    if isTracking && hrZone != .resting {
        Circle()
            .fill(hrZone == .high ? Theme.high : Theme.elevated)
            .frame(width: 6, height: 6)
    }
}
```

### Popover Summary Row

New component in `MenuContentView`, below `BatteryPill`:

```swift
StressSummaryRow(
    topApp: "Slack",           // #1 stress app today
    elevatedMinutes: 42,       // total elevated time today
    appsTracked: 5,            // unique apps today
    onTap: { openInsightsWindow() }
)
```

Visual: `📊 Slack (42m elevated) · 5 apps`

Only shown when `activityTrackingEnabled && hasDataToday`.

### Insights Window

Separate `NSWindow` with SwiftUI content. Opens from popover summary row tap or Settings button.

**Layout:**

```
┌─────────────────────────────────────────────────┐
│  Stress Insights                    [Today ▾]   │
├─────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────┐   │
│  │  TimelineChart                          │   │
│  │  (HR line + colored app segments)       │   │
│  └─────────────────────────────────────────┘   │
│                                                 │
│  Apps by Stress              This Week vs Last │
│  ┌──────────────────┐       ┌────────────────┐ │
│  │ StressRankingList│       │ ComparisonCard │ │
│  │ 1. Slack   +18bpm│       │ Slack   ↑ 12%  │ │
│  │ 2. Zoom    +12bpm│       │ Zoom    ↓  5%  │ │
│  │ 3. VSCode   +3bpm│       │ VSCode  ━  0%  │ │
│  └──────────────────┘       └────────────────┘ │
│                                                 │
│  Baseline: 68 bpm (your resting average)       │
│                                                 │
│  [Export CSV]              [Clear Data...]     │
└─────────────────────────────────────────────────┘
```

**Components:**

| Component | Description |
|-----------|-------------|
| `TimelineChart` | HR sparkline with colored background segments per app |
| `StressRankingList` | Vertical bar chart, sorted by elevated time |
| `ComparisonCard` | Week-over-week change with arrows |
| Date picker | Today / This Week / This Month / Custom range |

**Window specs:**
- Size: 500×600, resizable
- Style: `.titled`, `.closable`, `.miniaturizable`
- Title: "Stress Insights"

### Settings Section

Add to `SettingsView`:

```swift
Section {
    Toggle("Track app activity", isOn: $activityTrackingEnabled)
    Text("Records which app is active alongside your heart rate")
        .font(.caption).foregroundStyle(.secondary)
    
    if activityTrackingEnabled {
        HStack {
            Text("Data stored")
            Spacer()
            Text(dataStoredSize)  // "2.4 MB"
                .foregroundStyle(.secondary)
        }
        
        Button("View Insights") { openInsightsWindow() }
        Button("Export All Data...") { exportCSV() }
        Button("Delete All Data...", role: .destructive) { confirmDelete() }
    }
} header: {
    Label("Activity Tracking", systemImage: "chart.bar.fill")
}
```

**Settings keys:**
- `activityTrackingEnabled: Bool` — default `false` (opt-in)

## File Structure

```
HelioCore/
├── Sources/HelioCore/
│   ├── Models.swift              (existing, add new types)
│   ├── HealthStore.swift         (existing)
│   ├── ActivitySample.swift      (NEW)
│   ├── ActivityStore.swift       (NEW - SQLite)
│   ├── ActivityTracker.swift     (NEW - polling)
│   └── StressAnalyzer.swift      (NEW - insights)
├── Tests/HelioCoreTests/
│   ├── ActivityStoreTests.swift  (NEW)
│   ├── ActivityTrackerTests.swift(NEW)
│   └── StressAnalyzerTests.swift (NEW)
└── Package.swift                 (add GRDB dependency)

HelioBarApp/
├── AppModel.swift                (wire up ActivityTracker)
├── MenuBarIcon.swift             (add stress dot)
├── Views/
│   ├── MenuContentView.swift     (add StressSummaryRow)
│   ├── SettingsView.swift        (add Activity section)
│   ├── InsightsWindow.swift      (NEW)
│   └── Components/
│       ├── StressSummaryRow.swift    (NEW)
│       ├── TimelineChart.swift       (NEW)
│       ├── StressRankingList.swift   (NEW)
│       └── ComparisonCard.swift      (NEW)
```

## Dependencies

Add to `HelioCore/Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0")
],
targets: [
    .target(
        name: "HelioCore",
        dependencies: [
            .product(name: "GRDB", package: "GRDB.swift")
        ]
    ),
]
```

## Testing Strategy

### Unit Tests (HelioCore)

| Test | Coverage |
|------|----------|
| `ActivityStoreTests` | CRUD operations, date range queries, export |
| `StressAnalyzerTests` | Ranking algorithm, timeline merging, comparisons |
| `ActivityTrackerTests` | Start/stop, mock NSWorkspace |

### Integration Tests

- Full flow: tracker records → store persists → analyzer computes → correct stats
- Migration: empty DB → first write → schema created

### Manual Testing

- [ ] Enable tracking, use Mac normally, check samples recorded
- [ ] Open insights window, verify data matches
- [ ] Export CSV, verify format
- [ ] Delete all data, confirm cleared
- [ ] Disable tracking, verify no new samples
- [ ] Sleep/wake Mac, verify tracking pauses/resumes

## Migration & Rollout

1. Feature ships **disabled by default** (opt-in)
2. No migration needed for existing users (new SQLite DB)
3. Settings toggle enables tracking + shows insights UI

## Privacy Considerations

- All data stored locally in app sandbox
- No network requests related to activity tracking
- Tracking only active when HR connected (purposeful tie)
- User can export/delete all data at any time
- Full app names stored (user accepted this tradeoff for better insights)

## Open Questions

None — all decisions made during brainstorming.

## Appendix: Storage Estimates

| Timeframe | Samples | Storage |
|-----------|---------|---------|
| 1 day (8h work) | ~1,920 | ~150 KB |
| 1 week | ~9,600 | ~750 KB |
| 1 month | ~38,400 | ~3 MB |
| 1 year | ~460,800 | ~35 MB |

SQLite with indexes, uncompressed. Acceptable for local storage.
