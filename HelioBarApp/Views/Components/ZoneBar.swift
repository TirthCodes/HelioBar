import SwiftUI
import HelioCore

/// Segmented time-in-zone bar with a legend.
struct ZoneBar: View {
    /// Fractions (0...1) per zone, in display order.
    let fractions: [(zone: HRZone, fraction: Double)]
    let isEmpty: Bool

    private let order: [HRZone] = [.resting, .elevated, .high]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(order, id: \.self) { z in
                        Capsule()
                            .fill(Theme.color(for: z))
                            .frame(width: max(0, geo.size.width * fraction(for: z)))
                    }
                }
            }
            .frame(height: 8)
            .opacity(isEmpty ? 0.15 : 1)

            HStack(spacing: 12) {
                legend("Resting", Theme.resting)
                legend("Elevated", Theme.elevated)
                legend("High", Theme.high)
            }
        }
    }

    private func fraction(for zone: HRZone) -> Double {
        fractions.first { $0.zone == zone }?.fraction ?? 0
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 10, design: .rounded)).foregroundStyle(.tertiary)
        }
    }
}

#if !SWIFT_PACKAGE
#Preview {
    ZoneBar(fractions: [(.resting, 0.6), (.elevated, 0.3), (.high, 0.1)], isEmpty: false)
        .padding().background(.black)
}
#endif
