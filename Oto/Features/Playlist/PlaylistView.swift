import SwiftUI

struct PlaylistView: View {
    let tracks: [Track]
    let title: String
    let listTransitionScope: String
    /// When set (e.g. 每日推荐), now playing shows this instead of “Current Queue”.
    let playbackSource: PlaybackSource?
    let discoverNavigationTransitionSource: DiscoverNavigationTransitionSource?
    /// When `true`, uses `navigationTitle` / system bar instead of `OtoDetailHeader`-style chrome.
    let usesSystemNavigationBar: Bool
    /// When `usesSystemNavigationBar` and the view is the root of a presented `NavigationStack` (e.g. from Now Playing), show a leading toolbar button — push destinations get the standard back chevron.
    let prefersToolbarDismissButton: Bool
    @Binding var showNowPlaying: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nowPlayingHeroNamespace) private var heroNamespace
    @Environment(\.setNowPlayingZoomSource) private var setNowPlayingZoomSource
    @State private var player = PlayerService.shared
    @State private var actionSheetTrack: Track? = nil
    @State private var pendingNavigation: PendingNavigation? = nil

    init(
        tracks: [Track],
        title: String = String(localized: String.LocalizationValue("discover_daily")),
        listTransitionScope: String = "playlist-inline",
        playbackSource: PlaybackSource? = nil,
        discoverNavigationTransitionSource: DiscoverNavigationTransitionSource? = nil,
        usesSystemNavigationBar: Bool = false,
        prefersToolbarDismissButton: Bool = false,
        showNowPlaying: Binding<Bool> = .constant(false)
    ) {
        self.tracks = tracks
        self.title = title
        self.listTransitionScope = listTransitionScope
        self.playbackSource = playbackSource
        self.discoverNavigationTransitionSource = discoverNavigationTransitionSource
        self.usesSystemNavigationBar = usesSystemNavigationBar
        self.prefersToolbarDismissButton = prefersToolbarDismissButton
        self._showNowPlaying = showNowPlaying
    }

    var body: some View {
        let stack = ZStack {
            BlurredBackground()

            Group {
                if usesSystemNavigationBar {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                playAllButton
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, OtoMetrics.screenPadding)
                            .padding(.top, OtoMetrics.sectionSpacing)
                            .padding(.bottom, 16)

                            LazyVStack(spacing: 12) {
                                trackRows
                            }
                            .padding(.horizontal, OtoMetrics.screenPadding)
                        }
                        .padding(.bottom, OtoMetrics.screenPadding + 120)
                    }
                } else {
                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(Color.glassPrimary)
                                    .padding(10)
                                    .background(Circle().fill(.ultraThinMaterial))
                            }

                            Spacer()

                            Text(title)
                                .font(.glassTitle)
                                .foregroundStyle(Color.glassPrimary)

                            Spacer()

                            Color.clear
                                .frame(width: 44, height: 44)
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)

                        HStack {
                            playAllButton
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal)
                        .padding(.top, 16)
                        .padding(.bottom, 16)

                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 12) {
                                trackRows
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 24)
                        }
                    }
                }
            }
        }

        Group {
            #if os(iOS)
            if let src = discoverNavigationTransitionSource, let ns = heroNamespace {
                stack.navigationTransition(.zoom(sourceID: src, in: ns))
            } else {
                stack
            }
            #else
            stack
            #endif
        }
        .sheet(item: $actionSheetTrack) { track in
            TrackActionSheetView(
                track: track,
                onDismiss: { actionSheetTrack = nil },
                onNavigate: { nav in pendingNavigation = nav }
            )
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
        .modifier(PlaylistNavigationChromeModifier(
            usesSystemNavigationBar: usesSystemNavigationBar,
            prefersToolbarDismissButton: prefersToolbarDismissButton,
            title: title
        ))
    }

    private var playAllButton: some View {
        Button {
            if let first = tracks.first {
                setNowPlayingZoomSource?(
                    .listRow(scope: listTransitionScope, trackID: first.id, rowIndex: 0)
                )
            }
            player.playQueue(tracks: tracks, startIndex: 0, source: playbackSource)
            showNowPlaying = true
        } label: {
            OtoPlayAllTracksButtonLabel(title: String(localized: String.LocalizationValue("play_all")))
        }
        .buttonStyle(.plain)
        .disabled(tracks.isEmpty)
    }

    @ViewBuilder
    private var trackRows: some View {
        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
            Button {
                setNowPlayingZoomSource?(
                    .listRow(scope: listTransitionScope, trackID: track.id, rowIndex: index)
                )
                player.playQueue(tracks: tracks, startIndex: index, source: playbackSource)
                showNowPlaying = true
            } label: {
                trackRow(track, index: index, isPlaying: player.currentTrack?.id == track.id && player.isPlaying)
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 0.5) {
                        actionSheetTrack = track
                    }
            }
            .buttonStyle(.plain)
        }
    }

    private func trackRow(_ track: Track, index: Int, isPlaying: Bool) -> some View {
        LiquidGlassCard {
            HStack(spacing: 16) {
                RemoteImageView(urlString: track.coverURL, placeholderStyle: .minimal)
                    .frame(width: 56, height: 56)
                    .nowPlayingMatchedListArtwork(
                        sourceID: .listRow(scope: listTransitionScope, trackID: track.id, rowIndex: index),
                        namespace: heroNamespace,
                        cornerRadius: 10
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.glassHeadline)
                        .foregroundStyle(Color.glassPrimary)
                    Text(track.artist)
                        .font(.glassCaption)
                        .foregroundStyle(Color.glassSecondary)
                }

                Spacer()

                if isPlaying {
                    OtoInlinePlayingIndicator(tint: .glassAccent)
                }
            }
        }
    }
}

private struct PlaylistNavigationChromeModifier: ViewModifier {
    let usesSystemNavigationBar: Bool
    let prefersToolbarDismissButton: Bool
    let title: String
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        if usesSystemNavigationBar {
            content
                .otoMusicPushedListNavigation(title: title, hidesTabBar: true)
                .toolbar {
                    if prefersToolbarDismissButton {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                        }
                    }
                }
        } else {
            content
                .otoMusicInlineNavigation(hidesTabBar: true)
        }
    }
}
