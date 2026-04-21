import SwiftUI

struct LiquidGlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: OtoMetrics.cardCornerRadius, style: .continuous)
                    .fill(Color.otoPanelFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: OtoMetrics.cardCornerRadius, style: .continuous)
                            .stroke(Color.otoPanelStroke, lineWidth: OtoMetrics.hairlineWidth)
                    )
            )
            .shadow(color: Color.otoCardShadow, radius: 20, x: 0, y: 12)
    }
}
