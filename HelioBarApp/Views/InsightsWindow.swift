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

    @MainActor func showWindow() {
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

/// Ranked list of apps by stress level.
struct StressRankingList: View {
    let stats: [AppStressStats]

    var body: some View {
        if stats.isEmpty {
            Text("No data for this period")
                .font(Theme.captionFont)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            VStack(spacing: 6) {
                ForEach(stats, id: \.bundleID) { stat in
                    StressRankingRow(stat: stat)
                }
            }
        }
    }
}

private struct StressRankingRow: View {
    let stat: AppStressStats

    var body: some View {
        HStack(spacing: 8) {
            // Delta indicator dot
            Circle()
                .fill(deltaColor)
                .frame(width: 8, height: 8)

            Text(stat.appName)
                .font(Theme.captionFont)
                .lineLimit(1)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(stat.avgHR)) bpm avg")
                    .font(Theme.captionFont)
                if stat.deltaFromBaseline > 0 {
                    Text("+\(String(format: "%.0f", stat.deltaFromBaseline)) from baseline")
                        .font(Theme.captionFont)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .cardSurface()
    }

    private var deltaColor: Color {
        if stat.deltaFromBaseline > 10 { return Theme.high }
        if stat.deltaFromBaseline > 5  { return Theme.elevated }
        return Theme.resting
    }
}
