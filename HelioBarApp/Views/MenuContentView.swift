import SwiftUI
import HelioCore

struct MenuContentView: View {
    let store: HealthStore
    var onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            hrRow
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 220)
    }

    private var hrRow: some View {
        HStack {
            Image(systemName: "heart.fill").foregroundStyle(.red)
            Text(store.liveHR.map { "\($0) bpm" } ?? "—")
                .font(.title3).bold()
                .opacity(store.hrStatus == .stale ? 0.5 : 1)
            Spacer()
            badge
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

    private var footer: some View {
        HStack {
            Button("Settings…", action: onSettings)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}

#Preview("live") {
    let s = HealthStore(); s.updateHR(72)
    return MenuContentView(store: s, onSettings: {})
}

#Preview("idle") {
    MenuContentView(store: HealthStore(), onSettings: {})
}
