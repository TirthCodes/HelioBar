import SwiftUI
import HelioCore

/// HR timeline with colored segments per app.
struct TimelineChart: View {
    let segments: [TimelineSegment]
    let samples: [ActivitySample]

    var body: some View {
        GeometryReader { geo in
            if samples.count >= 2 {
                ZStack(alignment: .bottom) {
                    // App segment backgrounds
                    segmentBackgrounds(in: geo)

                    // HR line
                    hrLine(in: geo)
                }
            } else {
                Text("Collecting data...")
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func segmentBackgrounds(in geo: GeometryProxy) -> some View {
        let range = timeRange
        if range.duration > 0 {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                let startX = xPosition(for: segment.start, in: geo, range: range)
                let endX = xPosition(for: segment.end, in: geo, range: range)

                Rectangle()
                    .fill(Theme.color(for: segment.zone).opacity(0.15))
                    .frame(width: max(endX - startX, 2))
                    .position(x: startX + (endX - startX) / 2, y: geo.size.height / 2)
            }
        }
    }

    @ViewBuilder
    private func hrLine(in geo: GeometryProxy) -> some View {
        let range = timeRange
        let hrRange = hrRange

        Path { path in
            var first = true
            for sample in samples.sorted(by: { $0.timestamp < $1.timestamp }) {
                let x = xPosition(for: sample.timestamp, in: geo, range: range)
                let y = yPosition(for: sample.hr, in: geo, range: hrRange)

                if first {
                    path.move(to: CGPoint(x: x, y: y))
                    first = false
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .stroke(Theme.elevated, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    private var timeRange: (start: Date, end: Date, duration: TimeInterval) {
        guard let first = samples.min(by: { $0.timestamp < $1.timestamp }),
              let last = samples.max(by: { $0.timestamp < $1.timestamp }) else {
            return (Date(), Date(), 0)
        }
        return (first.timestamp, last.timestamp, last.timestamp.timeIntervalSince(first.timestamp))
    }

    private var hrRange: (min: Int, max: Int) {
        let hrs = samples.map(\.hr)
        return (hrs.min() ?? 60, hrs.max() ?? 100)
    }

    private func xPosition(
        for date: Date,
        in geo: GeometryProxy,
        range: (start: Date, end: Date, duration: TimeInterval)
    ) -> CGFloat {
        guard range.duration > 0 else { return 0 }
        let offset = date.timeIntervalSince(range.start)
        return geo.size.width * (offset / range.duration)
    }

    private func yPosition(
        for hr: Int,
        in geo: GeometryProxy,
        range: (min: Int, max: Int)
    ) -> CGFloat {
        let span = max(range.max - range.min, 1)
        let normalized = Double(hr - range.min) / Double(span)
        return geo.size.height * (1 - normalized)
    }
}
