import SwiftUI

// MARK: - Shared list / cover bar heights (audio meters + synthetic motion)

enum OtoPlayingBarAnimation {
    static func barHeight(
        t: TimeInterval,
        index: Int,
        maxH: CGFloat,
        useMeters: Bool,
        levels: [Float]
    ) -> CGFloat {
        let minH = maxH * 0.18
        let maxR = maxH
        let i = min(index, 3)
        let meter = useMeters ? CGFloat(i < levels.count ? levels[i] : 0) : 0
        let synthetic = syntheticLevel01(t: t, index: index)
        let threshold: CGFloat = 0.035
        let level: CGFloat = {
            if meter > threshold {
                return min(1, meter * 0.88 + synthetic * 0.12)
            }
            return synthetic
        }()
        return minH + level * (maxR - minH)
    }

    /// Decorative 0...1 motion when audio meters are quiet or unavailable.
    private static func syntheticLevel01(t: TimeInterval, index: Int) -> CGFloat {
        let i = Double(index)
        let a = sin(t * (5.6 + i * 1.35) + i * 2.05)
        let b = sin(t * (9.2 + i * 0.9) + i * 1.2)
        let blend = (a * 0.62 + b * 0.38 + 1) * 0.5
        return CGFloat(min(1, max(0, blend)))
    }
}

/// Compact equalizer bars for list rows and queue; matches cover badge motion.
struct OtoInlinePlayingIndicator: View {
    @State private var player = PlayerService.shared
    var tint: Color = .otoAccent

    private let barCount = 4
    private let maxBarHeight: CGFloat = 14
    private let barWidth: CGFloat = 2.2
    private let barSpacing: CGFloat = 2

    var body: some View {
        let _ = player.playbackVisualizerLevels
        let _ = player.isPlaying
        TimelineView(.animation(minimumInterval: 1.0 / 75.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: barWidth * 0.45, style: .continuous)
                        .fill(tint)
                        .frame(
                            width: barWidth,
                            height: OtoPlayingBarAnimation.barHeight(
                                t: t,
                                index: i,
                                maxH: maxBarHeight,
                                useMeters: player.isPlaying,
                                levels: player.playbackVisualizerLevels
                            )
                        )
                }
            }
            .frame(height: maxBarHeight, alignment: .bottom)
            .accessibilityHidden(true)
        }
    }
}

/// Bottom-trailing badge: uneven equalizer-style bars for “now playing” on artwork.
struct CoverPlayingNotesOverlay: View {
    @State private var player = PlayerService.shared
    let isActive: Bool
    /// Artwork edge length in points; drives bar size and insets (ignored when `usesHeroPlayButtonAnchor`).
    let coverSide: CGFloat
    /// Extra bottom inset when another control (e.g. play button) shares the trailing corner.
    var bottomChromeInset: CGFloat = 0
    /// Capsule behind bars (Discover covers use `false` so bars sit directly on artwork).
    var showsBackground: Bool = false
    /// Bottom-trailing layout matching discover hero play control: 34×34 content, 14pt padding from edges.
    var usesHeroPlayButtonAnchor: Bool = false

    private let barCount = 4

    /// Matches `DiscoverView` hero play `Button` label size.
    private var heroControlSide: CGFloat { 34 }
    private var heroControlPadding: CGFloat { 14 }

    var body: some View {
        if isActive {
            let _ = player.playbackVisualizerLevels
            let _ = player.isPlaying
            if usesHeroPlayButtonAnchor {
                heroAnchoredBars
            } else {
                standardBars
            }
        }
    }

    private var heroAnchoredBars: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 75.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: heroBarSpacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: heroBarCornerRadius, style: .continuous)
                        .fill(.white)
                        .shadow(color: .black.opacity(0.35), radius: 1.2, x: 0, y: 0.5)
                        .frame(width: heroBarWidth, height: barHeight(t: t, index: i, maxH: heroMaxBarHeight))
                }
            }
            .frame(width: heroControlSide, height: heroControlSide, alignment: .bottom)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(heroControlPadding)
    }

    private var standardBars: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 75.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous)
                        .fill(.white)
                        .shadow(
                            color: showsBackground ? .clear : Color.black.opacity(0.35),
                            radius: showsBackground ? 0 : 1.2,
                            x: 0,
                            y: showsBackground ? 0 : 0.5
                        )
                        .frame(width: barWidth, height: barHeight(t: t, index: i, maxH: maxBarHeight))
                }
            }
            .frame(height: maxBarHeight, alignment: .bottom)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background {
                if showsBackground {
                    Capsule()
                        .fill(.black.opacity(0.48))
                }
            }
            .accessibilityHidden(true)
        }
        .padding(edgeInset)
        .padding(.bottom, bottomChromeInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private var heroMaxBarHeight: CGFloat { 14 }

    private var heroBarWidth: CGFloat { 2.35 }

    private var heroBarSpacing: CGFloat { 2.0 }

    private var heroBarCornerRadius: CGFloat { heroBarWidth * 0.45 }

    private var maxBarHeight: CGFloat {
        min(17, max(8, coverSide * 0.12))
    }

    private var barWidth: CGFloat {
        max(2.2, coverSide * 0.026)
    }

    private var barCornerRadius: CGFloat {
        barWidth * 0.45
    }

    private var barSpacing: CGFloat {
        max(1.5, coverSide * 0.016)
    }

    private var horizontalPadding: CGFloat {
        max(4, coverSide * 0.055)
    }

    private var verticalPadding: CGFloat {
        max(3, coverSide * 0.038)
    }

    private var edgeInset: CGFloat {
        max(2, coverSide * 0.035)
    }

    private func barHeight(t: TimeInterval, index: Int, maxH: CGFloat) -> CGFloat {
        OtoPlayingBarAnimation.barHeight(
            t: t,
            index: index,
            maxH: maxH,
            useMeters: isActive && player.isPlaying,
            levels: player.playbackVisualizerLevels
        )
    }
}
