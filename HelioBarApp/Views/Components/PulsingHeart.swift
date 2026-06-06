import SwiftUI

/// A heart glyph that gently beats at the live BPM. Static when bpm is nil.
///
/// Driven by a `TimelineView` keyed to the beat period rather than a
/// `.repeatForever` animation: live HR updates ~1×/sec, and tearing down and
/// restarting a repeating animation on every sample makes the pulse stutter.
/// A continuous time-based scale lets the tempo change smoothly with no restart.
struct PulsingHeart: View {
    let bpm: Int?
    var color: Color = Theme.high

    /// One beat (full expand+contract cycle) duration in seconds, derived from
    /// BPM. Clamped so extreme/garbage values don't produce absurd tempos.
    private var beat: Double? {
        guard let bpm else { return nil }
        return 60.0 / Double(min(max(bpm, 40), 200))
    }

    var body: some View {
        if let beat {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = (sin(2 * .pi * t / beat) + 1) / 2   // 0…1, one cycle per beat
                Image(systemName: "heart.fill")
                    .foregroundStyle(color)
                    .scaleEffect(0.82 + 0.18 * phase)
            }
        } else {
            Image(systemName: "heart.fill")
                .foregroundStyle(color)
                .scaleEffect(0.82)
        }
    }
}

#if !SWIFT_PACKAGE
#Preview {
    HStack(spacing: 24) {
        PulsingHeart(bpm: 60, color: Theme.resting)
        PulsingHeart(bpm: 120, color: Theme.elevated)
        PulsingHeart(bpm: nil)
    }
    .font(.system(size: 30))
    .padding()
}
#endif
