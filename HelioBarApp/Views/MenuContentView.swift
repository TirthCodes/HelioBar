import SwiftUI
import HelioCore

struct MenuContentView: View {
    let store: HealthStore
    var onSettings: () -> Void
    @State private var breathing = false

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
    }

    private var main: some View {
        VStack(spacing: Theme.md) {
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

            HStack(spacing: Theme.sm) {
                IconButton(systemName: "wind", help: "Breathe", tint: .blue) { breathing = true }
                IconButton(systemName: "arrow.counterclockwise", help: "Reset session") { store.resetSession() }
                IconButton(systemName: "gearshape", help: "Settings", action: onSettings)
                IconButton(systemName: "power", help: "Quit") { NSApplication.shared.terminate(nil) }
            }
        }
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
    return MenuContentView(store: s, onSettings: {}).background(.black)
}

#Preview("idle") {
    MenuContentView(store: HealthStore(), onSettings: {}).background(.black)
}
#endif
