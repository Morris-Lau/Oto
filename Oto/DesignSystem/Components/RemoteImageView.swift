import SwiftUI
import Nuke
import NukeUI

/// Remote images (HTTP/HTTPS) should use this view. SF Symbols and local assets are out of scope.
public struct RemoteImageView: View {
    public enum PlaceholderStyle: Sendable {
        case album
        case avatar
        case minimal
    }

    private let url: URL?
    private let placeholderStyle: PlaceholderStyle
    private let contentMode: ContentMode
    private let prefersDrawingGroup: Bool

    @State private var reloadID = UUID()

    public init(
        urlString: String,
        placeholderStyle: PlaceholderStyle = .album,
        contentMode: ContentMode = .fill,
        prefersDrawingGroup: Bool = false
    ) {
        self.url = RemoteURLNormalizer.url(from: urlString)
        self.placeholderStyle = placeholderStyle
        self.contentMode = contentMode
        self.prefersDrawingGroup = prefersDrawingGroup
    }

    public init(
        url: URL?,
        placeholderStyle: PlaceholderStyle = .album,
        contentMode: ContentMode = .fill,
        prefersDrawingGroup: Bool = false
    ) {
        self.url = url.map(RemoteURLNormalizer.canonicalURL)
        self.placeholderStyle = placeholderStyle
        self.contentMode = contentMode
        self.prefersDrawingGroup = prefersDrawingGroup
    }

    /// 使用共享 `ImagePipeline` 预取封面，URL 规则与展示时一致，便于命中同一缓存。
    public static func prefetch(urlStrings: [String]) {
        let urls = urlStrings.compactMap(RemoteURLNormalizer.url(from:))
        guard !urls.isEmpty else { return }
        ImagePrefetcher(pipeline: ImagePipeline.shared).startPrefetching(with: Array(Set(urls)))
    }

    public var body: some View {
        Group {
            if let url {
                if let cached = cachedUIImage(for: url) {
                    styledImage(Image(uiImage: cached))
                } else {
                    LazyImage(url: url) { state in
                        Group {
                            if let image = state.image {
                                styledImage(image)
                            } else if state.error != nil {
                                retryableFailure
                            } else {
                                loadingPlaceholder
                            }
                        }
                        .animation(.easeInOut(duration: 0.25), value: state.image != nil)
                        .transition(.opacity)
                    }
                    .id(reloadID)
                }
            } else {
                staticFailurePlaceholder
            }
        }
    }

    private func cachedUIImage(for url: URL) -> UIImage? {
        let request = ImageRequest(url: url)
        return ImagePipeline.shared.cache.cachedImage(for: request)?.image
    }

    @ViewBuilder
    private func styledImage(_ image: Image) -> some View {
        let base = image
            .resizable()
            .aspectRatio(contentMode: contentMode)
        if prefersDrawingGroup {
            base.drawingGroup()
        } else {
            base
        }
    }

    private var loadingPlaceholder: some View {
        PlaceholderSurface(style: placeholderStyle, showFailureGlyph: false)
    }

    private var staticFailurePlaceholder: some View {
        PlaceholderSurface(style: placeholderStyle, showFailureGlyph: true)
    }

    private var retryableFailure: some View {
        Button {
            reloadID = UUID()
        } label: {
            PlaceholderSurface(style: placeholderStyle, showFailureGlyph: true)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Placeholder

private struct PlaceholderSurface: View {
    let style: RemoteImageView.PlaceholderStyle
    var showFailureGlyph: Bool

    var body: some View {
        ZStack {
            Rectangle().fill(backgroundFill)
            if showFailureGlyph {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: iconPointSize, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                switch style {
                case .album:
                    Image(systemName: "music.note")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.gray)
                case .avatar:
                    Image(systemName: "person.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.gray)
                case .minimal:
                    EmptyView()
                }
            }
        }
    }

    private var backgroundFill: Color {
        switch style {
        case .album:
            return Color.gray.opacity(0.2)
        case .avatar:
            return Color.clear
        case .minimal:
            return Color.otoPanelStroke
        }
    }

    private var iconPointSize: CGFloat {
        switch style {
        case .album, .avatar:
            return 20
        case .minimal:
            return 14
        }
    }
}
