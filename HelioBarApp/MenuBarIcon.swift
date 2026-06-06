import AppKit
import HelioCore

/// Renders the menu-bar item as a fixed-width dark pill with a zone-colored
/// heart + BPM. Drawn as a non-template NSImage so the color is preserved.
enum MenuBarIcon {
    private static let size = NSSize(width: 66, height: 22)

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

            // Heart glyph — tinted via a colored symbol configuration. A template
            // image drawn with draw(in:) ignores the set fill color and renders
            // black, so we bake the zone color into the symbol instead.
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(hierarchicalColor: contentColor))
            if let heart = NSImage(systemSymbolName: "heart.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(symbolConfig) {
                heart.isTemplate = false
                let hRect = NSRect(x: 8, y: (rect.height - 13) / 2, width: 14, height: 13)
                heart.draw(in: hRect)
            }

            // Number (centered in a fixed slot for up to 3 digits)
            let text = bpm.map(String.init) ?? "–"
            let para = NSMutableParagraphStyle(); para.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: contentColor,
                .paragraphStyle: para,
            ]
            let numberSlot = NSRect(x: 24, y: (rect.height - 17) / 2 - 1, width: 36, height: 18)
            (text as NSString).draw(in: numberSlot, withAttributes: attrs)
            return true
        }
        image.isTemplate = false
        return image
    }
}
