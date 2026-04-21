import SwiftUI
import UIKit

/// UIKit-backed dynamic colors for light/dark mode. SwiftUI ``Color`` tokens wrap these for a single source of truth.
enum OtoDynamicUIColor {
    static let canvasTop = UIColor { tc in
        switch tc.userInterfaceStyle {
        case .dark:
            return UIColor(red: 0.14, green: 0.12, blue: 0.11, alpha: 1)
        default:
            return UIColor(red: 0.98, green: 0.96, blue: 0.92, alpha: 1)
        }
    }

    static let canvasBottom = UIColor { tc in
        switch tc.userInterfaceStyle {
        case .dark:
            return UIColor(red: 0.10, green: 0.09, blue: 0.085, alpha: 1)
        default:
            return UIColor(red: 0.93, green: 0.90, blue: 0.85, alpha: 1)
        }
    }

    static let heroGlow = UIColor { tc in
        switch tc.userInterfaceStyle {
        case .dark:
            return UIColor(red: 0.90, green: 0.42, blue: 0.30, alpha: 1)
        default:
            return UIColor(red: 0.84, green: 0.37, blue: 0.24, alpha: 1)
        }
    }

    static let secondaryGlow = UIColor { tc in
        switch tc.userInterfaceStyle {
        case .dark:
            return UIColor(red: 0.55, green: 0.56, blue: 0.88, alpha: 1)
        default:
            return UIColor(red: 0.41, green: 0.42, blue: 0.78, alpha: 1)
        }
    }

    static let textPrimary = UIColor { tc in
        switch tc.userInterfaceStyle {
        case .dark:
            return UIColor(red: 0.96, green: 0.94, blue: 0.91, alpha: 1)
        default:
            return UIColor(red: 0.10, green: 0.09, blue: 0.08, alpha: 1)
        }
    }

    static let textSecondary = UIColor { tc in
        switch tc.userInterfaceStyle {
        case .dark:
            return UIColor(red: 0.72, green: 0.70, blue: 0.66, alpha: 1)
        default:
            return UIColor(red: 0.42, green: 0.40, blue: 0.37, alpha: 1)
        }
    }

    static let textTertiary = UIColor { tc in
        switch tc.userInterfaceStyle {
        case .dark:
            return UIColor(red: 0.55, green: 0.52, blue: 0.48, alpha: 1)
        default:
            return UIColor(red: 0.58, green: 0.55, blue: 0.51, alpha: 1)
        }
    }

    static let panelFill = UIColor { tc in
        switch tc.userInterfaceStyle {
        case .dark:
            return UIColor.white.withAlphaComponent(0.12)
        default:
            return UIColor.white.withAlphaComponent(0.72)
        }
    }

    static let panelStroke = UIColor { tc in
        switch tc.userInterfaceStyle {
        case .dark:
            return UIColor.white.withAlphaComponent(0.14)
        default:
            return UIColor.black.withAlphaComponent(0.08)
        }
    }

    static let glassFill = UIColor { tc in
        switch tc.userInterfaceStyle {
        case .dark:
            return UIColor.white.withAlphaComponent(0.08)
        default:
            return UIColor.white.withAlphaComponent(0.16)
        }
    }

    static let glassStroke = UIColor { tc in
        switch tc.userInterfaceStyle {
        case .dark:
            return UIColor.white.withAlphaComponent(0.22)
        default:
            return UIColor.white.withAlphaComponent(0.18)
        }
    }

    static let accent = UIColor { tc in
        switch tc.userInterfaceStyle {
        case .dark:
            return UIColor(red: 0.92, green: 0.44, blue: 0.32, alpha: 1)
        default:
            return UIColor(red: 0.84, green: 0.37, blue: 0.24, alpha: 1)
        }
    }

    static let accentSoft = UIColor { tc in
        switch tc.userInterfaceStyle {
        case .dark:
            return UIColor(red: 0.92, green: 0.44, blue: 0.32, alpha: 0.22)
        default:
            return UIColor(red: 0.84, green: 0.37, blue: 0.24, alpha: 0.14)
        }
    }

    static let playbackBackground = UIColor { tc in
        switch tc.userInterfaceStyle {
        case .dark:
            return UIColor(red: 0.22, green: 0.06, blue: 0.03, alpha: 1)
        default:
            return UIColor(red: 0.47, green: 0.10, blue: 0.04, alpha: 1)
        }
    }

    static let playbackBackgroundBottom = UIColor { tc in
        switch tc.userInterfaceStyle {
        case .dark:
            return UIColor(red: 0.30, green: 0.10, blue: 0.05, alpha: 1)
        default:
            return UIColor(red: 0.56, green: 0.16, blue: 0.08, alpha: 1)
        }
    }

    static let playbackForeground = UIColor { tc in
        switch tc.userInterfaceStyle {
        case .dark:
            return UIColor(red: 0.99, green: 0.97, blue: 0.95, alpha: 1)
        default:
            return UIColor(red: 0.99, green: 0.97, blue: 0.95, alpha: 1)
        }
    }

    static let playbackMuted = UIColor { tc in
        switch tc.userInterfaceStyle {
        case .dark:
            return UIColor(red: 0.95, green: 0.88, blue: 0.84, alpha: 0.52)
        default:
            return UIColor(red: 0.97, green: 0.92, blue: 0.89, alpha: 0.72)
        }
    }

    static let chipInactiveFill = UIColor { tc in
        switch tc.userInterfaceStyle {
        case .dark:
            return UIColor.white.withAlphaComponent(0.14)
        default:
            return UIColor.white.withAlphaComponent(0.68)
        }
    }

    static let glassSpecularTop = UIColor { tc in
        switch tc.userInterfaceStyle {
        case .dark:
            return UIColor.white.withAlphaComponent(0.22)
        default:
            return UIColor.white.withAlphaComponent(0.52)
        }
    }

    static let glassSpecularMid = UIColor { tc in
        switch tc.userInterfaceStyle {
        case .dark:
            return UIColor.white.withAlphaComponent(0.06)
        default:
            return UIColor.white.withAlphaComponent(0.12)
        }
    }

    static let glassBorderHighlight = UIColor { tc in
        switch tc.userInterfaceStyle {
        case .dark:
            return UIColor.white.withAlphaComponent(0.38)
        default:
            return UIColor.white.withAlphaComponent(0.82)
        }
    }

    static let glassBorderLow = UIColor { tc in
        switch tc.userInterfaceStyle {
        case .dark:
            return UIColor.white.withAlphaComponent(0.14)
        default:
            return UIColor.white.withAlphaComponent(0.28)
        }
    }

    static let cardShadow = UIColor { tc in
        switch tc.userInterfaceStyle {
        case .dark:
            return UIColor.black.withAlphaComponent(0.45)
        default:
            return UIColor.black.withAlphaComponent(0.08)
        }
    }

    static let subtleHairlineOnImage = UIColor { tc in
        switch tc.userInterfaceStyle {
        case .dark:
            return UIColor.white.withAlphaComponent(0.12)
        default:
            return UIColor.black.withAlphaComponent(0.08)
        }
    }
}

enum OtoMetrics {
    static let screenPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 18
    static let cardCornerRadius: CGFloat = 24
    static let chipCornerRadius: CGFloat = 16
    static let miniPlayerCornerRadius: CGFloat = 18
    static let hairlineWidth: CGFloat = 1
}

enum OtoLyricsPageVerticalFade {
    private static let lyricsFade0: CGFloat = 0
    private static let lyricsFade1: CGFloat = 0.5
    private static let lyricsFade2: CGFloat = 0.75
    private static let lyricsFade3: CGFloat = 1

    static var lyricsScrollEdgeMask: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .clear, location: lyricsFade0),
                .init(color: Color.otoCanvasTop, location: lyricsFade1),
                .init(color: Color.otoCanvasTop, location: lyricsFade2),
                .init(color: .clear, location: lyricsFade3)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private static let tabFade0: CGFloat = 0
    private static let tabFade1: CGFloat = 0.5
    private static let tabFade2: CGFloat = 1

    /// Canvas tint from the top of the screen (including status bar) through the pinned tab header.
    /// The upper edge is fully opaque; 0…0.8 stays nearly solid before the fade to the list.
    static var tabPinnedHeaderFading: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.otoCanvasTop, location: tabFade0),
                .init(color: Color.otoCanvasTop.opacity(0.5), location: tabFade1),
                .init(color:Color.clear, location: tabFade2)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

extension Color {
    static let otoCanvasTop = Color(uiColor: OtoDynamicUIColor.canvasTop)
    static let otoCanvasBottom = Color(uiColor: OtoDynamicUIColor.canvasBottom)
    static let otoHeroGlow = Color(uiColor: OtoDynamicUIColor.heroGlow)
    static let otoSecondaryGlow = Color(uiColor: OtoDynamicUIColor.secondaryGlow)

    static let otoTextPrimary = Color(uiColor: OtoDynamicUIColor.textPrimary)
    static let otoTextSecondary = Color(uiColor: OtoDynamicUIColor.textSecondary)
    static let otoTextTertiary = Color(uiColor: OtoDynamicUIColor.textTertiary)

    static let otoPanelFill = Color(uiColor: OtoDynamicUIColor.panelFill)
    static let otoPanelStroke = Color(uiColor: OtoDynamicUIColor.panelStroke)
    static let otoGlassFill = Color(uiColor: OtoDynamicUIColor.glassFill)
    static let otoGlassStroke = Color(uiColor: OtoDynamicUIColor.glassStroke)

    static let otoAccent = Color(uiColor: OtoDynamicUIColor.accent)
    static let otoAccentSoft = Color(uiColor: OtoDynamicUIColor.accentSoft)
    static let otoPlaybackBackground = Color(uiColor: OtoDynamicUIColor.playbackBackground)
    static let otoPlaybackBackgroundBottom = Color(uiColor: OtoDynamicUIColor.playbackBackgroundBottom)
    static let otoPlaybackForeground = Color(uiColor: OtoDynamicUIColor.playbackForeground)
    static let otoPlaybackMuted = Color(uiColor: OtoDynamicUIColor.playbackMuted)

    static let otoChipInactiveFill = Color(uiColor: OtoDynamicUIColor.chipInactiveFill)
    static let otoGlassSpecularTop = Color(uiColor: OtoDynamicUIColor.glassSpecularTop)
    static let otoGlassSpecularMid = Color(uiColor: OtoDynamicUIColor.glassSpecularMid)
    static let otoGlassBorderHighlight = Color(uiColor: OtoDynamicUIColor.glassBorderHighlight)
    static let otoGlassBorderLow = Color(uiColor: OtoDynamicUIColor.glassBorderLow)
    static let otoCardShadow = Color(uiColor: OtoDynamicUIColor.cardShadow)

    public static var glassBackground: Color { otoPanelFill }
    static var glassPrimary: Color { otoTextPrimary }
    static var glassSecondary: Color { otoTextSecondary }
    static var glassAccent: Color { otoAccent }
    static var glassOverlay: Color { otoGlassStroke }
}

extension Font {
    static let otoHero = Font.system(size: 34, weight: .bold, design: .serif)
    static let otoScreenTitle = Font.system(size: 28, weight: .semibold, design: .serif)
    static let otoSectionTitle = Font.system(size: 12, weight: .semibold, design: .default)
    static let otoHeadline = Font.system(size: 17, weight: .semibold, design: .default)
    static let otoBody = Font.system(size: 16, weight: .regular, design: .default)
    static let otoCaption = Font.system(size: 13, weight: .medium, design: .default)

    static let glassLargeTitle = otoHero
    static let glassTitle = otoScreenTitle
    static let glassHeadline = otoHeadline
    static let glassBody = otoBody
    static let glassCaption = otoCaption
}

struct OtoChip<Label: View>: View {
    private let isActive: Bool
    private let label: Label

    init(isActive: Bool = false, @ViewBuilder label: () -> Label) {
        self.isActive = isActive
        self.label = label()
    }

    var body: some View {
        label
            .font(.otoCaption)
            .foregroundStyle(isActive ? Color.otoAccent : Color.otoTextSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? Color.otoAccentSoft : Color.otoChipInactiveFill)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(isActive ? Color.otoAccent.opacity(0.22) : Color.otoPanelStroke, lineWidth: OtoMetrics.hairlineWidth)
                    )
            )
    }
}

/// Label for the primary “play all / play collection” action on track-list screens.
struct OtoPlayAllTracksButtonLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "play.fill")
            Text(title)
                .font(.glassHeadline)
        }
        .foregroundStyle(Color.glassPrimary)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .glassEffect(.regular.interactive())
    }
}
