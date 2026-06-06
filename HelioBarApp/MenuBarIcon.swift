import AppKit
import HelioCore

/// Renders the menu-bar item as a fixed-width dark pill with a zone-colored
/// heart + BPM. Drawn as a non-template NSImage so the color is preserved.
enum MenuBarIcon {
    private static let size = NSSize(width: 58, height: 20)

    static func image(bpm: Int?, zone: HRZone?, status: SourceStatus) -> NSImage {
        let contentColor: NSColor
        switch status {
        case .stale:                 contentColor = .secondaryLabelColor
        case .idle, .error:          contentColor = .tertiaryLabelColor
        case .live:
            switch zone {
            case .elevated: contentColor = .systemOrange
            case .high:     contentColor = .systemRed
            default:        contentColor = .systemGreen
            }
        }

        let image = NSImage(size: size, flipped: false) { rect in
            // Dark pill
            let pill = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                    xRadius: 6, yRadius: 6)
            NSColor.black.withAlphaComponent(0.55).setFill()
            pill.fill()
            NSColor.white.withAlphaComponent(0.08).setStroke()
            pill.lineWidth = 1
            pill.stroke()

            // Heart glyph
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            if let heart = NSImage(systemSymbolName: "heart.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(symbolConfig) {
                let tinted = heart
                tinted.isTemplate = true
                let hRect = NSRect(x: 7, y: (rect.height - 11) / 2, width: 12, height: 11)
                contentColor.set()
                tinted.draw(in: hRect)
            }

            // Number (centered in a fixed slot for up to 3 digits)
            let text = bpm.map(String.init) ?? "–"
            let para = NSMutableParagraphStyle(); para.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: contentColor,
                .paragraphStyle: para,
            ]
            let numberSlot = NSRect(x: 22, y: (rect.height - 14) / 2 - 1, width: 30, height: 16)
            (text as NSString).draw(in: numberSlot, withAttributes: attrs)
            return true
        }
        image.isTemplate = false
        return image
    }
}
