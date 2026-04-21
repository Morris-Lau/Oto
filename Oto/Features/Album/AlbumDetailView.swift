import SwiftUI

struct AlbumDetailView: View {
    let albumID: Int
    @Binding var showNowPlaying: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.setNowPlayingZoomSource) private var setNowPlayingZoomSource
    @State private var detail: AlbumDetailModel?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var pendingNavigation: PendingNavigation? = nil

    var body: some View {
        ZStack {
            BlurredBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: OtoMetrics.sectionSpacing) {
                    OtoDetailHeader(label: String(localized: String.LocalizationValue("header_album"))) {
                        dismiss()
                    }

                    if isLoading {
                        OtoDetailLoadingCard()
                    } else if let errorMessage {
                        OtoDetailErrorCard(title: String(localized: String.LocalizationValue("error_album_load")), message: errorMessage)
                    } else if let detail {
                        hero(detail)
                        albumPlayBar(detail)
                        OtoTrackList(
                            tracks: detail.tracks,
                            listTransitionScope: "album-\(albumID)",
                            showsTrackArtwork: false,
                            onSelect: { index in
                                PlayerService.shared.playQueue(tracks: detail.tracks, startIndex: index, source: PlaybackSource(kind: .album, label: String(localized: String.LocalizationValue("playing_from_album")), title: detail.name, id: albumID))
                                showNowPlaying = true
                            },
                            onNavigate: { nav in pendingNavigation = nav }
                        )
                    }
                }
                .padding(OtoMetrics.screenPadding)
                .padding(.bottom, 120)
            }
        }
        .navigationDestination(item: $pendingNavigation) { nav in
            switch nav {
            case .artist(let id):
                ArtistDetailView(artistID: id, showNowPlaying: $showNowPlaying)
            case .album(let id):
                AlbumDetailView(albumID: id, showNowPlaying: $showNowPlaying)
            default:
                EmptyView()
            }
        }
        .task(id: albumID) {
            await load()
        }
        .otoMusicInlineNavigation(hidesTabBar: true)
    }

    private func hero(_ detail: AlbumDetailModel) -> some View {
        LiquidGlassCard {
            HStack(spacing: 16) {
                RemoteImageView(urlString: detail.coverURL)
                    .frame(width: 104, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text(detail.name)
                        .font(.otoScreenTitle)
                        .foregroundStyle(Color.otoTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail.artist)
                        .font(.otoHeadline)
                        .foregroundStyle(Color.otoTextSecondary)
                    Text(detail.publishInfo)
                        .font(.otoCaption)
                        .foregroundStyle(Color.otoTextTertiary)
                }
            }
        }
    }

    private func albumPlayBar(_ detail: AlbumDetailModel) -> some View {
        HStack(spacing: 10) {
            Button {
                let scope = "album-\(albumID)"
                if let first = detail.tracks.first {
                    setNowPlayingZoomSource?(.listRow(scope: scope, trackID: first.id, rowIndex: 0))
                }
                PlayerService.shared.playQueue(tracks: detail.tracks, startIndex: 0, source: PlaybackSource(kind: .album, label: String(localized: String.LocalizationValue("playing_from_album")), title: detail.name, id: albumID))
                showNowPlaying = true
            } label: {
                OtoPlayAllTracksButtonLabel(title: String(localized: String.LocalizationValue("play_album")))
            }
            .buttonStyle(.plain)
            .disabled(detail.tracks.isEmpty)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() async {
        await MainActor.run {
            errorMessage = nil
            if let cached = MusicDetailCacheStore.loadAlbum(id: albumID) {
                detail = cached
                isLoading = false
            } else {
                isLoading = true
            }
        }
        do {
            let fresh = try await NetEaseService.shared.fetchAlbumDetail(id: albumID)
            await MainActor.run {
                detail = fresh
                isLoading = false
                errorMessage = nil
            }
            MusicDetailCacheStore.saveAlbum(fresh)
        } catch {
            await MainActor.run {
                if detail == nil {
                    errorMessage = error.localizedDescription
                }
                isLoading = false
            }
        }
    }
}
