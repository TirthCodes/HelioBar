import SwiftUI
import HelioCore

struct MenuContentView: View {
    let store: HealthStore
    var onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            hrRow
            Sparkline(values: store.recent)
                .frame(height: 38)
            statsRow
            zoneBar
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 240)
    }

    private var hrRow: some View {
        HStack {
            Image(systemName: "heart.fill").foregroundStyle(.red)
            Text(store.liveHR.map { "\($0) bpm" } ?? "—")
                .font(.title3).bold()
                .opacity(store.hrStatus == .stale ? 0.5 : 1)
            if let t = store.hrTrend { trendIcon(t) }
            Spacer()
            badge
        }
    }

    @ViewBuilder private func trendIcon(_ t: HealthStore.Trend) -> some View {
        switch t {
        case .rising:  Image(systemName: "arrow.up.right").foregroundStyle(.orange)
        case .falling: Image(systemName: "arrow.down.right").foregroundStyle(.blue)
        case .steady:  Image(systemName: "arrow.right").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var badge: some View {
        switch store.hrStatus {
        case .live:
            Label("live", systemImage: "circle.fill").foregroundStyle(.green).font(.caption)
        case .stale:
            Label("reconnecting", systemImage: "circle.fill").foregroundStyle(.secondary).font(.caption)
        case .idle:
            Text("enable Heart Rate Push").font(.caption).foregroundStyle(.secondary)
        case .error(let m):
            Text(m).font(.caption).foregroundStyle(.orange)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 14) {
            stat("min", store.sessionMin)
            stat("avg", store.sessionAvg)
            stat("max", store.sessionMax)
            Spacer()
        }
    }

    private func stat(_ label: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value.map(String.init) ?? "—").font(.callout).monospacedDigit()
        }
    }

    private var zoneBar: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach([HRZone.resting, .elevated, .high], id: \.self) { z in
                    Rectangle()
                        .fill(zoneColor(z))
                        .frame(width: max(0, geo.size.width * store.zoneFraction(z)))
                }
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
        .opacity(store.zoneCounts.isEmpty ? 0.15 : 1)
    }

    private func zoneColor(_ z: HRZone) -> Color {
        switch z { case .resting: return .green; case .elevated: return .orange; case .high: return .red }
    }

    private var footer: some View {
        HStack {
            Button("Reset") { store.resetSession() }
            Spacer()
            Button("Settings…", action: onSettings)
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}

/// Tiny line chart of recent HR values.
private struct Sparkline: View {
    let values: [Int]
    var body: some View {
        GeometryReader { geo in
            if values.count >= 2 {
                let lo = Double(values.min()!), hi = Double(values.max()!)
                let range = Swift.max(hi - lo, 1)
                Path { p in
                    for (i, v) in values.enumerated() {
                        let x = geo.size.width * Double(i) / Double(values.count - 1)
                        let y = geo.size.height * (1 - (Double(v) - lo) / range)
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                        else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(.red, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            } else {
                Text("collecting…").font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }
}

#Preview("live") {
    let s = HealthStore()
    [62,65,70,68,72,80,95,110,90,75,72,71].forEach { s.updateHR($0) }
    return MenuContentView(store: s, onSettings: {})
}

#Preview("idle") {
    MenuContentView(store: HealthStore(), onSettings: {})
}
