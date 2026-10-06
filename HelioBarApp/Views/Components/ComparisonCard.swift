import SwiftUI
import HelioCore

/// Week-over-week comparison card.
struct ComparisonCard: View {
    let comparisons: [AppStressComparison]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("THIS WEEK VS LAST")
                .font(Theme.cardTitleFont)
                .foregroundStyle(.secondary)

            if comparisons.isEmpty {
                Text("Not enough data for comparison")
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(comparisons.prefix(5), id: \.bundleID) { comparison in
                    ComparisonRow(comparison: comparison)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardSurface()
    }
}

struct ComparisonRow: View {
    let comparison: AppStressComparison

    var body: some View {
        HStack {
            Text(comparison.appName)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: arrowIcon)
                    .foregroundStyle(changeColor)

                Text(changeText)
                    .font(Theme.captionFont.monospacedDigit())
                    .foregroundStyle(changeColor)
            }
        }
    }

    private var arrowIcon: String {
        if comparison.changePercent > 5 {
            return "arrow.up"
        } else if comparison.changePercent < -5 {
            return "arrow.down"
        } else {
            return "minus"
        }
    }

    private var changeColor: Color {
        if comparison.changePercent > 5 {
            return Theme.high
        } else if comparison.changePercent < -5 {
            return Theme.resting
        } else {
            return .secondary
        }
    }

    private var changeText: String {
        let pct = Int(abs(comparison.changePercent).rounded())
        return "\(pct)%"
    }
}

#if !SWIFT_PACKAGE
#Preview {
    ComparisonCard(comparisons: [
        AppStressComparison(bundleID: "com.slack", appName: "Slack", currentElevatedRatio: 0.5, previousElevatedRatio: 0.4, changePercent: 25),
        AppStressComparison(bundleID: "com.zoom", appName: "Zoom", currentElevatedRatio: 0.3, previousElevatedRatio: 0.35, changePercent: -14),
        AppStressComparison(bundleID: "com.vscode", appName: "VS Code", currentElevatedRatio: 0.1, previousElevatedRatio: 0.1, changePercent: 0),
    ])
    .padding()
    .background(.black)
}
#endif
