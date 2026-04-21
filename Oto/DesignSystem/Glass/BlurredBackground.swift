import SwiftUI

struct BlurredBackground: View {
    var body: some View {
        ZStack {
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    .init(x: 0, y: 0), .init(x: 0.5, y: 0), .init(x: 1, y: 0),
                    .init(x: 0, y: 0.5), .init(x: 0.5, y: 0.5), .init(x: 1, y: 0.5),
                    .init(x: 0, y: 1), .init(x: 0.5, y: 1), .init(x: 1, y: 1)
                ],
                colors: [
                    .otoHeroGlow.opacity(0.18), .otoCanvasTop.opacity(0.72), .otoSecondaryGlow.opacity(0.12),
                    .otoCanvasTop.opacity(0.64), .otoCanvasBottom.opacity(0.92), .otoCanvasTop.opacity(0.58),
                    .otoCanvasBottom.opacity(0.86), .otoCanvasTop.opacity(0.64), .otoSecondaryGlow.opacity(0.08)
                ]
            )
            .ignoresSafeArea()

            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        }
    }
}
