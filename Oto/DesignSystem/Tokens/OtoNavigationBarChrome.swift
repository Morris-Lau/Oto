#if canImport(UIKit) && os(iOS)
import UIKit

extension UIFont {
    /// Matches `Font.otoScreenTitle` (28pt semibold serif).
    static var otoNavigationLargeTitle: UIFont {
        otoSerifSystemFont(size: 28, weight: .semibold)
    }

    /// Collapsed bar title; serif semibold to match the large title family.
    static var otoNavigationInlineTitle: UIFont {
        otoSerifSystemFont(size: 17, weight: .semibold)
    }

    private static func otoSerifSystemFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: size)
    }
}

extension UIColor {
    static var otoNavigationTitle: UIColor { OtoDynamicUIColor.textPrimary }
}

enum OtoNavigationBarChrome {
    /// Aligns navigation bar title typography with `Font.otoScreenTitle` / `Color.otoTextPrimary`.
    /// Avoid negative `baselineOffset` on the large title: it pulls glyphs up and clips descenders (e.g. “y” in “Library”).
    @MainActor
    static func applyAppearance() {
        let large = UIFont.otoNavigationLargeTitle
        let inline = UIFont.otoNavigationInlineTitle
        let color = UIColor.otoNavigationTitle
        let largeAttrs: [NSAttributedString.Key: Any] = [.font: large, .foregroundColor: color]
        let inlineAttrs: [NSAttributedString.Key: Any] = [.font: inline, .foregroundColor: color]

        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithDefaultBackground()
        scrolled.titleTextAttributes = inlineAttrs
        scrolled.largeTitleTextAttributes = largeAttrs

        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithTransparentBackground()
        scrollEdge.titleTextAttributes = inlineAttrs
        scrollEdge.largeTitleTextAttributes = largeAttrs

        let nav = UINavigationBar.appearance()
        nav.standardAppearance = scrolled
        nav.compactAppearance = scrolled
        nav.scrollEdgeAppearance = scrollEdge
        nav.compactScrollEdgeAppearance = scrollEdge
    }
}
#endif
