import SwiftUI

struct LibraryView: View {
    @Binding var showNowPlaying: Bool
    let onAccountAvatarTap: () -> Void
    private var session = SessionStore.shared
    @State private var showDownloads = false
    @State private var selectedPlaylist: UserPlaylistSummary?
    @State private var shelfKind: LibraryShelfKind = .createdPlaylists
    @State private var selectedAlbumRoute: LibraryAlbumRoute?

    init(
        showNowPlaying: Binding<Bool> = .constant(false),
        onAccountAvatarTap: @escaping () -> Void = {}
    ) {
        self._showNowPlaying = showNowPlaying
        self.onAccountAvatarTap = onAccountAvatarTap
    }

    var body: some View {
        ZStack {
            BlurredBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: OtoMetrics.sectionSpacing) {
                    if session.isLoggedIn {
                        loggedInShelf
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, OtoMetrics.screenPadding)
                .padding(.bottom, OtoMetrics.screenPadding + 120)
            }
        }
        .navigationTitle(String(localized: String.LocalizationValue("tab_library")))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showDownloads = true
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.otoAccent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: String.LocalizationValue("library_downloads_a11y")))

                OtoTabProfileAvatarButton(action: onAccountAvatarTap)
            }
        }
        .navigationDestination(isPresented: $showDownloads) {
            DownloadsLibraryPage(showNowPlaying: $showNowPlaying)
        }
        .navigationDestination(item: $selectedPlaylist) { playlist in
            PlaylistDetailView(playlistID: playlist.id, showNowPlaying: $showNowPlaying)
        }
        .navigationDestination(item: $selectedAlbumRoute) { route in
            AlbumDetailView(albumID: route.id, showNowPlaying: $showNowPlaying)
        }
        .task {
            guard SessionPersistence.loadCookieString() != nil else { return }
            if !session.isLoggedIn, !session.isLoadingStatus {
                await session.refresh()
            }
        }
    }

    private var loggedInShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(String(localized: String.LocalizationValue("library_picker_label")), selection: $shelfKind) {
                ForEach(LibraryShelfKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            switch shelfKind {
            case .createdPlaylists:
                createdPlaylistsShelf
            case .collectedPlaylists:
                collectedPlaylistsShelf
            case .albums:
                albumsShelf
            }
        }
    }

    private var createdPlaylistsShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(String(localized: String.LocalizationValue("library_section_created")))
            if session.playlists.isEmpty {
                LiquidGlassCard {
                    Text("library_empty_created")
                        .font(.otoCaption)
                        .foregroundStyle(Color.otoTextSecondary)
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(session.playlists) { playlist in
                        playlistRowButton(playlist)
                    }
                }
            }
        }
    }

    private var collectedPlaylistsShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(String(localized: String.LocalizationValue("library_section_collected")))
            if session.collectedPlaylists.isEmpty {
                LiquidGlassCard {
                    Text("library_empty_collected")
                        .font(.otoCaption)
                        .foregroundStyle(Color.otoTextSecondary)
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(session.collectedPlaylists) { playlist in
                        playlistRowButton(playlist)
                    }
                }
            }
        }
    }

    private func playlistSubtitle(_ playlist: UserPlaylistSummary) -> String {
        if let creator = playlist.creatorName, !creator.isEmpty {
            return String(format: String(localized: String.LocalizationValue("library_playlist_subtitle_creator")), creator, playlist.trackCount)
        }
        return String(format: String(localized: String.LocalizationValue("library_playlist_subtitle_tracks_only")), playlist.trackCount)
    }

    private func playlistRowButton(_ playlist: UserPlaylistSummary) -> some View {
        Button {
            selectedPlaylist = playlist
        } label: {
            LiquidGlassCard {
                HStack(spacing: 14) {
                    RemoteImageView(urlString: playlist.coverURL)
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(playlist.name)
                            .font(.otoHeadline)
                            .foregroundStyle(Color.otoTextPrimary)
                        Text(playlistSubtitle(playlist))
                            .font(.otoCaption)
                            .foregroundStyle(Color.otoTextSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.otoTextTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var albumsShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(String(localized: String.LocalizationValue("library_section_albums")))

            if session.collectedAlbums.isEmpty {
                LiquidGlassCard {
                    Text("library_empty_albums")
                        .font(.otoCaption)
                        .foregroundStyle(Color.otoTextSecondary)
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(session.collectedAlbums) { album in
                        Button {
                            selectedAlbumRoute = LibraryAlbumRoute(id: album.id)
                        } label: {
                            LiquidGlassCard {
                                HStack(spacing: 14) {
                                    RemoteImageView(urlString: album.coverURL)
                                        .frame(width: 58, height: 58)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(album.name)
                                            .font(.otoHeadline)
                                            .foregroundStyle(Color.otoTextPrimary)
                                        Text(String(format: String(localized: String.LocalizationValue("library_album_row_subtitle")), album.artist, album.trackCount))
                                            .font(.otoCaption)
                                            .foregroundStyle(Color.otoTextSecondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.otoTextTertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.otoSectionTitle)
            .foregroundStyle(Color.otoTextTertiary)
            .textCase(.uppercase)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 1)
    }
}

private enum LibraryShelfKind: String, CaseIterable {
    case createdPlaylists
    case collectedPlaylists
    case albums

    var title: String {
        switch self {
        case .createdPlaylists: return String(localized: String.LocalizationValue("library_shelf_created"))
        case .collectedPlaylists: return String(localized: String.LocalizationValue("library_shelf_collected"))
        case .albums: return String(localized: String.LocalizationValue("library_shelf_albums"))
        }
    }
}

private struct LibraryAlbumRoute: Identifiable, Hashable {
    let id: Int
}

private struct DownloadsLibraryPage: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var showNowPlaying: Bool
    @State private var downloadService = DownloadService.shared
    @State private var pendingNavigation: PendingNavigation? = nil

    var body: some View {
        ZStack {
            BlurredBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: OtoMetrics.sectionSpacing) {
                    OtoDetailHeader(label: String(localized: String.LocalizationValue("library_downloads_header"))) {
                        dismiss()
                    }

                    if downloadService.downloadedTracks.isEmpty {
                        LiquidGlassCard {
                            Text("library_empty_downloads")
                                .font(.otoCaption)
                                .foregroundStyle(Color.otoTextSecondary)
                        }
                    } else {
                        OtoTrackList(
                            tracks: downloadService.downloadedTracks,
                            listTransitionScope: "library-downloads",
                            onSelect: { index in
                                PlayerService.shared.playQueue(
                                    tracks: downloadService.downloadedTracks,
                                    startIndex: index
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
        .otoMusicInlineNavigation(hidesTabBar: true)
    }
}
