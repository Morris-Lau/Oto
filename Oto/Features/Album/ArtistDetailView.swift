import SwiftUI

struct ArtistDetailView: View {
    let artistID: Int
    @Binding var showNowPlaying: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.setNowPlayingZoomSource) private var setNowPlayingZoomSource
    @State private var detail: ArtistDetailModel?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedAlbumID: Int?
    @State private var pendingNavigation: PendingNavigation? = nil

    var body: some View {
        ZStack {
            BlurredBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: OtoMetrics.sectionSpacing) {
                    OtoDetailHeader(label: String(localized: String.LocalizationValue("header_artist"))) {
                        dismiss()
                    }

                    if isLoading {
                        OtoDetailLoadingCard()
                    } else if let errorMessage {
                        OtoDetailErrorCard(title: String(localized: String.LocalizationValue("error_artist_load")), message: errorMessage)
                    } else if let detail {
                        hero(detail)
                        albumShelf(detail.featuredAlbums)
                        artistTopTracksPlayBar(detail)
                        OtoTrackList(
                            tracks: detail.topTracks,
                            listTransitionScope: "artist-\(artistID)",
                            onSelect: { index in
                                PlayerService.shared.playQueue(
                                    tracks: detail.topTracks,
                                    startIndex: index,
                                    source: PlaybackSource(kind: .artist, label: String(localized: String.LocalizationValue("playing_from_artist")), title: detail.name, id: artistID)
                                )
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
        .navigationDestination(item: Binding(
            get: { selectedAlbumID.map(AlbumRoute.init(id:)) },
            set: { selectedAlbumID = $0?.id }
        )) { route in
            AlbumDetailView(albumID: route.id, showNowPlaying: $showNowPlaying)
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
        .task(id: artistID) {
            await load()
        }
        .otoMusicInlineNavigation(hidesTabBar: true)
    }

    private func hero(_ detail: ArtistDetailModel) -> some View {
        LiquidGlassCard {
            HStack(spacing: 16) {
                RemoteImageView(urlString: detail.avatarURL, placeholderStyle: .avatar)
                    .frame(width: 104, height: 104)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 8) {
                    Text(detail.name)
                        .font(.otoScreenTitle)
                        .foregroundStyle(Color.otoTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !detail.alias.isEmpty {
                        Text(detail.alias)
                            .font(.otoHeadline)
                            .foregroundStyle(Color.otoTextSecondary)
                    }

                    Text(
                        detail.fansCount > 0
                            ? String(format: String(localized: String.LocalizationValue("artist_fans_count")), detail.fansCount)
                            : String(localized: String.LocalizationValue("artist_top_songs_hint"))
                    )
                        .font(.otoCaption)
                        .foregroundStyle(Color.otoTextTertiary)
                }
            }
        }
    }

    private func artistTopTracksPlayBar(_ detail: ArtistDetailModel) -> some View {
        HStack(spacing: 10) {
            Button {
                guard !detail.topTracks.isEmpty else { return }
                let scope = "artist-\(artistID)"
                if let first = detail.topTracks.first {
                    setNowPlayingZoomSource?(.listRow(scope: scope, trackID: first.id, rowIndex: 0))
                }
                PlayerService.shared.playQueue(
                    tracks: detail.topTracks,
                    startIndex: 0,
                    source: PlaybackSource(kind: .artist, label: String(localized: String.LocalizationValue("playing_from_artist")), title: detail.name, id: artistID)
                )
                showNowPlaying = true
            } label: {
                OtoPlayAllTracksButtonLabel(title: String(localized: String.LocalizationValue("play_top_tracks")))
            }
            .buttonStyle(.plain)
            .disabled(detail.topTracks.isEmpty)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func albumShelf(_ albums: [AlbumSummary]) -> some View {
        if !albums.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Albums")
                    .font(.otoSectionTitle)
                    .foregroundStyle(Color.otoTextTertiary)
                    .textCase(.uppercase)

                albumTwoRowScroll(albums)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func albumTwoRowScroll(_ albums: [AlbumSummary]) -> some View {
        let mid = (albums.count + 1) / 2
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(0..<mid, id: \.self) { index in
                            albumCard(albums[index])
                        }
                    }
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(mid..<albums.count, id: \.self) { index in
                            albumCard(albums[index])
                        }
                    }
                }
            }
            .padding(.horizontal, OtoMetrics.screenPadding)
        }
        .padding(.horizontal, -OtoMetrics.screenPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func albumCard(_ album: AlbumSummary) -> some View {
        Button {
            selectedAlbumID = album.id
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RemoteImageView(urlString: album.coverURL)
                    LinearGradient(
                        colors: [Color.black.opacity(0.06), Color.black.opacity(0.2)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .frame(width: 162, height: 162)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                Text(album.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.otoTextPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 162, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        await MainActor.run {
            errorMessage = nil
            if let cached = MusicDetailCacheStore.loadArtist(id: artistID) {
                detail = cached
                isLoading = false
            } else {
                isLoading = true
            }
        }
        do {
            let fresh = try await NetEaseService.shared.fetchArtistDetail(id: artistID)
            await MainActor.run {
                detail = fresh
                isLoading = false
                errorMessage = nil
            }
            MusicDetailCacheStore.saveArtist(fresh)
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

private struct AlbumRoute: Identifiable, Hashable {
    let id: Int
}
