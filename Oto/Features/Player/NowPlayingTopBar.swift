import SwiftUI

struct NowPlayingTopBar: View {
    @State private var player = PlayerService.shared
    @State private var session = SessionStore.shared
    @State private var downloadService = DownloadService.shared
    let track: Track?
    let isTogglingLike: Bool
    let onToggleLike: () -> Void
    let onDismiss: () -> Void
    let onNavigateFromSource: (PendingNavigation) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let leadingMargin: CGFloat = 46
            let trailingOccupied: CGFloat = track != nil ? 86 : 38
            let maxChipWidth = max(
                0,
                min(w - 2 * leadingMargin, w - 2 * trailingOccupied)
            )

            ZStack {
                // Source chip first (underneath) so trailing toolbar buttons stay on top for hit testing.
                Button {
                    handleSourceChipTap()
                } label: {
                    MarqueeLine(
                        text: queueSourceTitle,
                        font: .glassCaption,
                        foregroundStyle: Color.glassSecondary,
                        maxWidth: maxChipWidth
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isSourceChipTappable)

                HStack(spacing: 8) {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.glassPrimary)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                        .allowsHitTesting(false)

                    if let track {
                        HStack(spacing: 10) {
                            let liked = session.isTrackLiked(track.id)
                            Button {
                                onToggleLike()
                            } label: {
                                Image(systemName: liked ? "heart.fill" : "heart")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(liked ? Color.red : Color.glassPrimary)
                                    .frame(width: 38, height: 38)
                                    .background(Circle().fill(.ultraThinMaterial))
                            }
                            .buttonStyle(.plain)
                            .disabled(isTogglingLike)

                            Button {
                                Task { _ = await downloadService.downloadIfNeeded(track) }
                            } label: {
                                nowPlayingDownloadButtonLabel(trackID: track.id)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Color.clear
                            .frame(width: 38)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(height: 38)
    }

    @ViewBuilder
    private func nowPlayingDownloadButtonLabel(trackID: Int) -> some View {
        let downloaded = downloadService.isDownloaded(trackID: trackID)
        let loading = downloadService.isDownloading(trackID: trackID)
        let fraction = downloadService.downloadFraction(for: trackID)

        ZStack {
            Circle()
                .fill(.ultraThinMaterial)

            if loading, !downloaded {
                if let fraction {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(Color.glassPrimary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(2)
                } else {
                    ProgressView()
                        .scaleEffect(0.55)
                        .tint(Color.glassPrimary)
                }
            }

            Image(
                systemName: downloaded
                    ? "arrow.down.circle.fill"
                    : "arrow.down.circle"
            )
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Color.glassPrimary)
        }
        .frame(width: 38, height: 38)
    }

    private var queueSourceTitle: String {
        if let source = player.playbackSource, !source.title.isEmpty {
            return source.title
        }
        return player.queue.count > 1
            ? String(localized: String.LocalizationValue("queue_source_current"))
            : String(localized: String.LocalizationValue("queue_source_single"))
    }

    private var isSourceChipTappable: Bool {
        sourceNavigation != nil
    }

    private var sourceNavigation: PendingNavigation? {
        guard let source = player.playbackSource else { return nil }
        switch source.kind {
        case .playlist:
            guard let id = source.id else { return nil }
            return .playlist(id: id)
        case .album:
            guard let id = source.id else { return nil }
            return .album(id: id)
        case .artist:
            guard let id = source.id else { return nil }
            return .artist(id: id)
        case .recommendation:
            return source.pendingNavigationForRecommendationSource()
        default:
            return nil
        }
    }

    private func handleSourceChipTap() {
        guard let nav = sourceNavigation else { return }
        onNavigateFromSource(nav)
        _ = nav
    }
}
