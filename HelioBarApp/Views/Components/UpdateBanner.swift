import SwiftUI
import HelioCore

/// "Update available" row shown at the top of the popover.
struct UpdateBanner: View {
    let release: LatestRelease
    var onDownload: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Theme.sm) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text("HelioBar \(release.version) available")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Button("Download", action: onDownload)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(.blue.opacity(0.25))
        )
    }
}

#if !SWIFT_PACKAGE
#Preview {
    UpdateBanner(
        release: LatestRelease(tagName: "v2.1.0", htmlURL: "https://example.com"),
        onDownload: {}, onDismiss: {}
    )
    .frame(width: 300).padding().background(.black)
}
#endif
