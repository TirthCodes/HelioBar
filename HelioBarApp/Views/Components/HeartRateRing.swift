import SwiftUI
import HelioCore

/// Hero heart-rate ring: gradient progress arc with rounded caps + glow,
/// centered BPM, % of max, trend arrow, and a pulsing heart.
struct HeartRateRing: View {
    let bpm: Int?
    let fraction: Double          // 0...1, portion of max HR
    let percentMax: Int?
    let zone: HRZone?
    let trend: HealthStore.Trend?
    let status: SourceStatus

    private var clamped: Double { min(max(fraction, 0), 1) }
    private var ghost: Bool { bpm == nil }
    private var dimmed: Bool { status == .stale }

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.07), lineWidth: 14)

            Circle()
                .trim(from: 0, to: ghost ? 0 : clamped)
                .stroke(
                    AngularGradient(
                        // Full-ring ramp; arc length shows progress. The last stop
                        // returns to green so the 360°/0° seam — where the arc's
                        // rounded start-cap overhangs — is green-on-green instead of
                        // showing a red dot. Red peaks at 0.85, inside the unfilled gap.
                        gradient: Gradient(stops: [
                            .init(color: Theme.resting,  location: 0.00),
                            .init(color: Color(red: 0.62, green: 0.82, blue: 0.29), location: 0.40),
                            .init(color: Theme.elevated, location: 0.66),
                            .init(color: Theme.high,     location: 0.85),
                            .init(color: Theme.resting,  location: 1.00),
                        ]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(90))            // start from the bottom
                .shadow(color: Theme.color(for: zone).opacity(0.45), radius: 6)
                .animation(.easeInOut(duration: 0.5), value: clamped)

            VStack(spacing: Theme.sm) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(bpm.map(String.init) ?? "—").font(Theme.bpmFont(52))
                    if bpm != nil {
                        Text("bpm")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                if let percentMax {
                    HStack(spacing: 6) {
                        PulsingHeart(bpm: bpm, color: Theme.color(for: zone))
                            .font(.system(size: 13))
                        Text(centerSubtitle(percentMax))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.color(for: zone))
                    }
                }
            }
        }
        .frame(width: 176, height: 176)
        .opacity(dimmed ? 0.5 : (ghost ? 0.6 : 1))
    }

    private func centerSubtitle(_ pct: Int) -> String {
        switch trend {
        case .rising:  return "\(pct)% · ↑"
        case .falling: return "\(pct)% · ↓"
        default:       return "\(pct)%"
        }
    }
}

#if !SWIFT_PACKAGE
#Preview("live") {
    HeartRateRing(bpm: 84, fraction: 0.58, percentMax: 58,
                  zone: .elevated, trend: .rising, status: .live)
        .padding().background(.black)
}
#Preview("idle") {
    HeartRateRing(bpm: nil, fraction: 0, percentMax: nil,
                  zone: nil, trend: nil, status: .idle)
        .padding().background(.black)
}
#endif
