import SwiftUI
import HelioCore

/// Guided breathing with live HR biofeedback — shown inline in the dropdown.
struct BreathingView: View {
    let store: HealthStore
    var onClose: () -> Void

    @State private var inhaling = false
    @State private var startHR: Int?
    @State private var lowHR: Int?
    private let timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: Theme.md) {
            HStack {
                Text("Breathe").font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                Button("Done", action: onClose).controlSize(.small)
            }

            Text(inhaling ? "Inhale…" : "Exhale…")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Theme.resting.opacity(0.35), Color.blue.opacity(0.12)],
                        center: .center, startRadius: 4, endRadius: 90))
                Circle().strokeBorder(Theme.resting.opacity(0.7), lineWidth: 2)
            }
            .frame(width: inhaling ? 150 : 80, height: inhaling ? 150 : 80)
            .shadow(color: Theme.resting.opacity(0.4), radius: 12)
            .animation(.easeInOut(duration: 4), value: inhaling)
            .frame(height: 160)   // reserve space so the popover doesn't jump

            VStack(spacing: 2) {
                Text(store.liveHR.map { "\($0) bpm" } ?? "—")
                    .font(Theme.bpmFont(26))
                if let s = startHR, let l = lowHR {
                    Text("start \(s) · low \(l) · ↓\(Swift.max(0, s - l))")
                        .font(Theme.captionFont).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { startHR = store.liveHR; lowHR = store.liveHR; inhaling = true }
        .onReceive(timer) { _ in inhaling.toggle() }
        .onChange(of: store.liveHR) { _, hr in
            guard let hr else { return }
            if startHR == nil { startHR = hr }
            lowHR = Swift.min(lowHR ?? hr, hr)
        }
    }
}

#if !SWIFT_PACKAGE
#Preview {
    let s = HealthStore(); s.updateHR(72)
    return BreathingView(store: s) {}.frame(width: 300).padding().background(.black)
}
#endif
