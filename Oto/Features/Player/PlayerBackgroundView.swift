import SwiftUI
import Nuke

struct PlayerBackgroundView: View {
    let coverURL: String?

    @State private var dominantColor: Color?
    @State private var coverImage: UIImage?

    private var fallbackGradient: some View {
        LinearGradient(
            colors: [.otoPlaybackBackground, .otoPlaybackBackgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var dynamicGradient: some View {
        Group {
            if let dominantColor {
                LinearGradient(
                    colors: [
                        dominantColor.opacity(0.50),
                        dominantColor.opacity(0.15)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                fallbackGradient
            }
        }
    }

    var body: some View {
        ZStack {
            dynamicGradient
                .ignoresSafeArea()

            if let coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .drawingGroup()
                    .scaleEffect(1.5)
                    .blur(radius: 40)
                    .opacity(0.72)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.5), value: coverURL)
        .task(id: coverURL) { await load(for: coverURL) }
    }

    private func load(for urlString: String?) async {
        guard let urlString, let url = RemoteURLNormalizer.url(from: urlString) else {
            await MainActor.run {
                dominantColor = nil
                coverImage = nil
            }
            return
        }

        let request = ImageRequest(url: url)
        let image: UIImage
        if let cached = ImagePipeline.shared.cache.cachedImage(for: request) {
            image = cached.image
        } else {
            do {
                image = try await ImagePipeline.shared.image(for: request)
            } catch {
                return
            }
        }

        await MainActor.run {
            if let uiColor = image.averageColor {
                dominantColor = Color(uiColor: uiColor.backgroundTint)
            }
            coverImage = image
        }
    }
}
