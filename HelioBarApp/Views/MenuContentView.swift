import SwiftUI
import HelioCore

struct MenuContentView: View {
    let store: HealthStore
    var onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            hrRow
            Divider()
            cloudRows
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
            Spacer()
            hrStatusBadge
        }
    }

    @ViewBuilder private var hrStatusBadge: some View {
        switch store.hrStatus {
        case .live:  Label("live", systemImage: "circle.fill")
                        .foregroundStyle(.green).labelStyle(.titleAndIcon).font(.caption)
        case .stale: Label("reconnecting", systemImage: "circle.fill")
                        .foregroundStyle(.secondary).font(.caption)
        case .idle:  Text("enable Heart Rate Push").font(.caption).foregroundStyle(.secondary)
        case .error(let m): Text(m).font(.caption).foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var cloudRows: some View {
        if case .error(let m) = store.cloudStatus {
            Button(action: onSettings) {
                Label("⚠ Re-connect Zepp (\(m))", systemImage: "exclamationmark.triangle")
                    .font(.caption)
            }.buttonStyle(.plain)
        } else {
            metricRow("Energy", store.energy.map { "\($0)%" })
            metricRow("Stress", store.stress.map { "\($0.value)  (\($0.label))" })
            metricRow("Readiness", store.readiness.map { "\($0.value)" })
        }
    }

    private func metricRow(_ name: String, _ value: String?) -> some View {
        HStack {
            Text(name).foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "—")
        }.font(.callout)
    }

    private var footer: some View {
        HStack {
            Text(syncText).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Settings…", action: onSettings)
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }

    private var syncText: String {
        guard let last = store.lastSync else { return "not synced" }
        let mins = Int(Date().timeIntervalSince(last) / 60)
        return mins <= 0 ? "synced just now" : "synced \(mins)m ago"
    }
}

#Preview("live") {
    let s = HealthStore()
    s.updateHR(72)
    s.updateCloud(stress: .init(value: 34, label: "Relaxed"),
                  readiness: .init(value: 81),
                  energy: 72,
                  at: Date())
    return MenuContentView(store: s, onSettings: {})
}

#Preview("no token / dropped") {
    let s = HealthStore()
    s.hrDisconnected()
    s.cloudFailed("401")
    return MenuContentView(store: s, onSettings: {})
}
