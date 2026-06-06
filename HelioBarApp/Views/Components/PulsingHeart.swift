import SwiftUI

/// A heart glyph that gently beats at the live BPM. Static when bpm is nil.
struct PulsingHeart: View {
    let bpm: Int?
    var color: Color = Theme.high

    @State private var expanded = false

    /// Half-cycle (beat) duration in seconds, derived from BPM. Clamped so
    /// extreme/garbage values don't produce absurd animation speeds.
    private var beat: Double {
        guard let bpm else { return 0 }
        return 60.0 / Double(min(max(bpm, 40), 200))
    }

    var body: some View {
        Image(systemName: "heart.fill")
            .foregroundStyle(color)
            .scaleEffect(expanded ? 1.0 : 0.82)
            .animation(
                bpm == nil ? nil
                : .easeInOut(duration: beat).repeatForever(autoreverses: true),
                value: expanded
            )
            .onAppear { expanded = bpm != nil }
            .onChange(of: bpm) { _, newValue in
                // Restart the loop so the new BPM's tempo takes effect.
                expanded = false
                if newValue != nil {
                    DispatchQueue.main.async { expanded = true }
                }
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
