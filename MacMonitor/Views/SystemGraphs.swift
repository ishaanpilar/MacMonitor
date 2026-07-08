import SwiftUI

// MARK: - Usage bar indicator

/// A compact labelled progress bar (0...1) used for CPU and Memory readouts.
struct UsageBar: View {
    let label: String
    let fraction: Double          // 0...1
    let valueText: String
    let color: Color
    var badge: (text: String, color: Color)?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(label)
                    .fontWeight(.semibold)
                if let badge {
                    Text(badge.text)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(badge.color.opacity(0.2), in: Capsule())
                        .foregroundStyle(badge.color)
                }
                Spacer()
                Text(valueText)
                    .foregroundStyle(color)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .font(.subheadline)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.secondary.opacity(0.2))
                    Capsule()
                        .fill(color)
                        .frame(width: max(0, min(1, fraction)) * geo.size.width)
                }
            }
            .frame(height: 5)
        }
    }
}

// MARK: - Metric line graph

/// A single-series line graph (values normalised to 0...1) over the shared history window,
/// with a gradient fill and, optionally, a colored pressure band behind it.
struct MetricLineGraph: View {
    private static let maxPoints = 300

    let history: [HistoryEntry]
    let value: (HistoryEntry) -> Double?     // returns 0...1
    let lineColor: Color
    var band: ((HistoryEntry) -> Color?)?    // optional background segment color
    var topLabel: String = "100%"
    var bottomLabel: String = "0%"

    private var downsampled: [HistoryEntry] {
        guard history.count > Self.maxPoints else { return history }
        let step = Double(history.count) / Double(Self.maxPoints)
        var result: [HistoryEntry] = []
        result.reserveCapacity(Self.maxPoints)
        for i in 0..<Self.maxPoints {
            let index = min(Int(Double(i) * step), history.count - 1)
            result.append(history[index])
        }
        if let last = history.last, result.last?.timestamp != last.timestamp {
            result[result.count - 1] = last
        }
        return result
    }

    private func y(_ normalized: Double, height: CGFloat) -> CGFloat {
        let padding: CGFloat = 4
        return padding + (1.0 - CGFloat(min(1, max(0, normalized)))) * (height - padding * 2)
    }

    var body: some View {
        Canvas { context, size in
            let sampled = downsampled
            guard sampled.count >= 2, let first = sampled.first else { return }
            let startTime = first.timestamp
            let totalDuration = Date().timeIntervalSince(startTime)
            guard totalDuration > 0 else { return }

            func x(_ entry: HistoryEntry) -> CGFloat {
                CGFloat(entry.timestamp.timeIntervalSince(startTime) / totalDuration) * size.width
            }

            // Optional colored background bands (merged by color)
            if let band {
                var currentColor = band(sampled[0])
                var segmentStart: CGFloat = 0
                for entry in sampled {
                    let color = band(entry)
                    if color?.description != currentColor?.description {
                        if let c = currentColor {
                            let rect = CGRect(x: segmentStart, y: 0, width: x(entry) - segmentStart, height: size.height)
                            context.fill(Path(rect), with: .color(c.opacity(0.18)))
                        }
                        currentColor = color
                        segmentStart = x(entry)
                    }
                }
                if let c = currentColor {
                    let rect = CGRect(x: segmentStart, y: 0, width: size.width - segmentStart, height: size.height)
                    context.fill(Path(rect), with: .color(c.opacity(0.18)))
                }
            }

            // Build the line
            var line = Path()
            var firstPoint = true
            var lastPoint = CGPoint.zero
            for entry in sampled {
                guard let v = value(entry) else { continue }
                let point = CGPoint(x: x(entry), y: y(v, height: size.height))
                if firstPoint {
                    line.move(to: point)
                    firstPoint = false
                } else {
                    line.addLine(to: point)
                }
                lastPoint = point
            }
            if let last = sampled.last, let v = value(last) {
                lastPoint = CGPoint(x: size.width, y: y(v, height: size.height))
                line.addLine(to: lastPoint)
            }

            // Gradient fill under the line
            var fill = line
            fill.addLine(to: CGPoint(x: lastPoint.x, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            context.fill(
                fill,
                with: .linearGradient(
                    Gradient(colors: [lineColor.opacity(0.35), lineColor.opacity(0.02)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            context.stroke(line, with: .color(lineColor), lineWidth: 1.5)

            // Current point
            if !firstPoint {
                let circle = Path(ellipseIn: CGRect(x: lastPoint.x - 3, y: lastPoint.y - 3, width: 6, height: 6))
                context.fill(circle, with: .color(lineColor))
            }

            // Axis labels
            let labelStyle = Font.system(size: 8)
            let labelColor = Color.secondary.opacity(0.8)
            context.draw(Text(topLabel).font(labelStyle).foregroundColor(labelColor),
                         at: CGPoint(x: 4, y: 4), anchor: .topLeading)
            context.draw(Text(bottomLabel).font(labelStyle).foregroundColor(labelColor),
                         at: CGPoint(x: 4, y: size.height - 4), anchor: .bottomLeading)
        }
        .frame(height: 54)
        .drawingGroup()
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.3), lineWidth: 1))
    }
}
