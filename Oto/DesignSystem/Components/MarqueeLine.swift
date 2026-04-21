import SwiftUI
import UIKit

/// Single-line label that scrolls horizontally (one direction, seamless loop) when wider than the clip width.
struct MarqueeLine: View {
    let text: String
    var font: Font = .body
    var foregroundStyle: Color = .primary
    /// Total width including ``horizontalInset`` on both sides.
    let maxWidth: CGFloat
    /// Inset between the clip edge and the surrounding layout (e.g. adjacent toolbar buttons).
    var horizontalInset: CGFloat = 8
    /// Gap between repeated copies of the label (for seamless wrap).
    var labelGap: CGFloat = 24
    /// Scroll speed in points per second.
    var scrollSpeed: CGFloat = 22
    /// Single-line width for overflow checks; should match ``font`` (default matches ``.glassCaption`` / caption 13 medium).
    var uiMeasurementFont: UIFont = UIFont.systemFont(ofSize: 13, weight: .medium)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clipWidth: CGFloat {
        max(0, maxWidth - 2 * horizontalInset)
    }

    /// Measured without SwiftUI layout so it is not clamped by ``clipWidth`` (overlay/background measurement was wrong).
    private var contentWidth: CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: uiMeasurementFont]).width)
    }

    private var needsMarquee: Bool {
        !reduceMotion && clipWidth > 1 && contentWidth > clipWidth + 0.5
    }

    private var cycleWidth: CGFloat {
        contentWidth + labelGap
    }

    var body: some View {
        ZStack {
            if needsMarquee {
                TimelineView(
                    .animation(
                        minimumInterval: 1.0 / 60.0,
                        paused: false
                    )
                ) { context in
                    let cycle = Double(cycleWidth)
                    let t = context.date.timeIntervalSinceReferenceDate * Double(scrollSpeed)
                    let phase = cycle > 0 ? t.truncatingRemainder(dividingBy: cycle) : 0
                    HStack(spacing: labelGap) {
                        marqueeTextSegment
                        marqueeTextSegment
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: -CGFloat(phase))
                }
            } else {
                Text(text)
                    .font(font)
                    .foregroundStyle(foregroundStyle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: clipWidth, alignment: .center)
            }
        }
        .frame(width: clipWidth, alignment: needsMarquee ? .leading : .center)
        .clipped()
        .padding(.horizontal, horizontalInset)
    }

    private var marqueeTextSegment: some View {
        Text(text)
            .font(font)
            .foregroundStyle(foregroundStyle)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}
