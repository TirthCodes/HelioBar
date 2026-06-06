import SwiftUI
import HelioCore

/// Design tokens for the HelioBar UI. Single source of truth for color,
/// spacing, radii, and typography across every surface.
enum Theme {
    // Zone color ramp
    static let resting  = Color(red: 0.20, green: 0.78, blue: 0.35) // #34C759
    static let elevated = Color(red: 1.00, green: 0.62, blue: 0.04) // #FF9F0A
    static let high     = Color(red: 1.00, green: 0.27, blue: 0.23) // #FF453A

    static func color(for zone: HRZone?) -> Color {
        switch zone {
        case .resting:  return resting
        case .elevated: return elevated
        case .high:     return high
        case nil:       return .secondary
        }
    }

    /// Gradient sweep used by the HR ring (green → yellow-green → orange → red).
    static let ringGradient: [Color] = [
        resting,
        Color(red: 0.62, green: 0.82, blue: 0.29),
        elevated,
        high,
    ]

    // Spacing
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20

    // Radii
    static let cardRadius: CGFloat = 13
    static let popoverRadius: CGFloat = 22
    static let pillRadius: CGFloat = 8

    // Typography
    static func bpmFont(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded).monospacedDigit()
    }
    static let statValueFont = Font.system(size: 20, weight: .bold, design: .rounded).monospacedDigit()
    static let cardTitleFont = Font.system(size: 11, weight: .semibold, design: .rounded)
    static let captionFont   = Font.system(size: 11, weight: .regular, design: .rounded)
}

extension View {
    /// Standard translucent card surface with a hairline stroke.
    func cardSurface(cornerRadius: CGFloat = Theme.cardRadius) -> some View {
        self
            .background(.white.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.09))
            )
    }
}
