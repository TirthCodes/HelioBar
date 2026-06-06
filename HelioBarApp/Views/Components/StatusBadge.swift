import SwiftUI
import HelioCore

/// The live/reconnecting/idle/error indicator under the ring.
struct StatusBadge: View {
    let status: SourceStatus

    var body: some View {
        switch status {
        case .live:
            label("live", Theme.resting, dot: true)
        case .stale:
            label("reconnecting", .secondary, dot: true)
        case .idle:
            Text("Enable Heart Rate Push in Zepp")
                .font(Theme.captionFont).foregroundStyle(.secondary)
        case .error(let message):
            Text(message)
                .font(Theme.captionFont).foregroundStyle(Theme.elevated)
                .multilineTextAlignment(.center)
        }
    }

    private func label(_ text: String, _ color: Color, dot: Bool) -> some View {
        HStack(spacing: 6) {
            if dot {
                Circle().fill(color).frame(width: 7, height: 7)
                    .shadow(color: color, radius: 3)
            }
            Text(text).font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
    }
}

#if !SWIFT_PACKAGE
#Preview {
    VStack(spacing: 12) {
        StatusBadge(status: .live)
        StatusBadge(status: .stale)
        StatusBadge(status: .idle)
        StatusBadge(status: .error("Bluetooth off"))
    }
    .padding().background(.black)
}
#endif
