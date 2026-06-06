import SwiftUI

/// Compact HR line chart with a soft gradient area fill.
struct HRSparkline: View {
    let values: [Int]
    var color: Color = Theme.elevated

    var body: some View {
        GeometryReader { geo in
            if values.count >= 2 {
                let lo = Double(values.min()!)
                let hi = Double(values.max()!)
                let range = max(hi - lo, 1)
                let pts: [CGPoint] = values.enumerated().map { i, v in
                    CGPoint(
                        x: geo.size.width * Double(i) / Double(values.count - 1),
                        y: geo.size.height * (1 - (Double(v) - lo) / range)
                    )
                }

                // Area fill
                Path { p in
                    p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                    pts.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(LinearGradient(
                    colors: [color.opacity(0.35), color.opacity(0)],
                    startPoint: .top, endPoint: .bottom))

                // Line
                Path { p in
                    p.move(to: pts[0])
                    pts.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            } else {
                Text("collecting…")
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }
}

#if !SWIFT_PACKAGE
#Preview {
    HRSparkline(values: [62,65,70,68,72,80,95,110,90,75,72,71])
        .frame(height: 46).padding().background(.black)
}
#endif
