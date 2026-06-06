import SwiftUI

/// One min/avg/max stat in a rounded card.
struct StatCard: View {
    let label: String
    let value: Int?
    var tint: Color = .primary

    var body: some View {
        VStack(spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
            Text(value.map(String.init) ?? "—")
                .font(Theme.statValueFont)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .cardSurface()
    }
}

#if !SWIFT_PACKAGE
#Preview {
    HStack(spacing: 8) {
        StatCard(label: "min", value: 61, tint: Theme.resting)
        StatCard(label: "avg", value: 73)
        StatCard(label: "max", value: 98, tint: Theme.high)
    }
    .padding().background(.black)
}
#endif
