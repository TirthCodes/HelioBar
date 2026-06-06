import SwiftUI

/// Square card button holding a single SF Symbol — used in the popover toolbar.
struct IconButton: View {
    let systemName: String
    let help: String
    var tint: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .cardSurface()
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

#if !SWIFT_PACKAGE
#Preview {
    HStack(spacing: 8) {
        IconButton(systemName: "wind", help: "Breathe", tint: .blue) {}
        IconButton(systemName: "arrow.counterclockwise", help: "Reset") {}
        IconButton(systemName: "gearshape", help: "Settings") {}
        IconButton(systemName: "power", help: "Quit") {}
    }
    .frame(width: 264).padding().background(.black)
}
#endif
