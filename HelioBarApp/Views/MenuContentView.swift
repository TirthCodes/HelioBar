import SwiftUI
import HelioCore

struct MenuContentView: View {
    let store: HealthStore
    let updater: UpdateChecker
    var onSettings: () -> Void
    @State private var breathing = false
    @AppStorage("activityTrackingEnabled") private var activityTrackingEnabled = false
    @State private var topStressApp: String?
    @State private var elevatedMinutes: Int = 0
    @State private var appsTracked: Int = 0

    var body: some View {
        Group {
            if breathing {
                BreathingView(store: store) { breathing = false }
            } else {
                main
            }
        }
        .padding(Theme.lg)
        .frame(width: 300)
        .background(.black.opacity(0.001))   // ensures the hosting view fills the popover
        .onReceive(NotificationCenter.default.publisher(for: .startBreathing)) { _ in
            breathing = true
        }
    }

    private var main: some View {
        VStack(spacing: Theme.md) {
            if let release = updater.available {
                UpdateBanner(
                    release: release,
                    onDownload: { updater.openDownload() },
                    onDismiss: { updater.dismiss(release) }
                )
            }
            HeartRateRing(
                bpm: store.liveHR,
                fraction: Double(store.percentMax ?? 0) / 100,
                percentMax: store.percentMax,
                zone: store.hrZone,
                trend: store.hrTrend,
                status: store.hrStatus
            )
            StatusBadge(status: store.hrStatus)

            card(title: "Last 2 min") {
                HRSparkline(values: store.recent).frame(height: 46)
            }

            HStack(spacing: Theme.sm) {
                StatCard(label: "min", value: store.sessionMin, tint: Theme.resting)
                StatCard(label: "avg", value: store.sessionAvg)
                StatCard(label: "max", value: store.sessionMax, tint: Theme.high)
            }

            card(title: "Time in zone") {
                ZoneBar(
                    fractions: [
                        (.resting,  store.zoneFraction(.resting)),
                        (.elevated, store.zoneFraction(.elevated)),
                        (.high,     store.zoneFraction(.high)),
                    ],
                    isEmpty: store.zoneCounts.isEmpty
                )
            }

            BatteryPill(percent: store.batteryPercent, estimate: store.batteryEstimate)

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

            HStack(spacing: Theme.sm) {
                IconButton(systemName: "wind", help: "Breathe", tint: .blue) { breathing = true }
                IconButton(systemName: "arrow.counterclockwise", help: "Reset session") { store.resetSession() }
                IconButton(systemName: "gearshape", help: "Settings", action: onSettings)
                IconButton(systemName: "power", help: "Quit") { NSApplication.shared.terminate(nil) }
            }
        }
    }

    private func loadStressSummary() async {
        guard let store = (NSApp.delegate as? AppDelegate)?.model.activityStore else { return }
        let today = Calendar.current.startOfDay(for: Date())
        let samples = await store.samples(from: today, to: Date())
        let stats = StressAnalyzer.rankByStress(samples: samples)
        topStressApp = stats.first?.appName
        elevatedMinutes = Int(stats.map(\.timeInElevated).reduce(0, +) / 60)
        appsTracked = stats.count
    }

    @ViewBuilder
    private func card<Content: View>(title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(Theme.cardTitleFont).foregroundStyle(.tertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .cardSurface()
    }
}

#if !SWIFT_PACKAGE
#Preview("live") {
    let s = HealthStore()
    [62,65,70,68,72,80,95,110,90,75,72,71].forEach { s.updateHR($0) }
    return MenuContentView(store: s, updater: UpdateChecker(), onSettings: {}).background(.black)
}

#Preview("idle") {
    MenuContentView(store: HealthStore(), updater: UpdateChecker(), onSettings: {}).background(.black)
}
#endif
