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
