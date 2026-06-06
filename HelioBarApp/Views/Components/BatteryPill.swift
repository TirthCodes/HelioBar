import SwiftUI
import HelioCore

/// Strap battery readout: drawn glyph (fill scales with %), percent, time-left.
struct BatteryPill: View {
    let percent: Int?
    let estimate: BatteryEstimate

    var body: some View {
        HStack(spacing: 9) {
            BatteryGlyph(percent: percent, color: color)
            Text(label).font(.system(size: 13, design: .rounded)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let right = timeLeft {
                Text(right).font(.system(size: 12, design: .rounded)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .cardSurface()
    }

    private var color: Color {
        guard let percent else { return .secondary }
        return percent < 20 ? Theme.elevated : Theme.resting
    }

    private var label: String {
        guard let percent else { return "Strap —" }
        return "Strap \(percent)%"
    }

    private var timeLeft: String? {
        guard percent != nil else { return nil }
        switch estimate {
        case .calibrating:          return "calibrating"
        case .ready(let remaining): return "~\(Self.formatRemaining(remaining)) left"
        }
    }

    static func formatRemaining(_ remaining: TimeInterval) -> String {
        let hours = Swift.max(0, Int(floor(remaining / 3600)))
        if hours >= 48 { return "\(Int((Double(hours) / 24).rounded()))d" }
        if hours >= 1  { return "\(hours)h" }
        return "<1h"
    }
}

/// Simple battery icon whose inner fill scales with the percentage.
private struct BatteryGlyph: View {
    let percent: Int?
    let color: Color

    var body: some View {
        let frac = CGFloat(min(max(percent ?? 0, 0), 100)) / 100
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(color, lineWidth: 1.4)
                    .frame(width: 22, height: 13)
                RoundedRectangle(cornerRadius: 1.6)
                    .fill(color)
                    .frame(width: max(0, (22 - 4) * frac), height: 9)
                    .padding(.leading, 2)
            }
            Capsule().fill(color).frame(width: 2, height: 5)
        }
    }
}

#if !SWIFT_PACKAGE
#Preview {
    VStack(spacing: 8) {
        BatteryPill(percent: 72, estimate: .ready(8 * 3600))
        BatteryPill(percent: 15, estimate: .calibrating)
        BatteryPill(percent: nil, estimate: .calibrating)
    }
    .frame(width: 264).padding().background(.black)
}
#endif
