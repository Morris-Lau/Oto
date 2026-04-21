import SwiftUI

struct DiscoverView: View {
    /// Set to `true` to show 私人 FM again (hero card + API fetch).
    private static let isPersonalFMEnabled = true

    @Binding var showNowPlaying: Bool
    /// Passed from `OtoTabShell` so taps work reliably (SwiftUI env through `TabView` is flaky).
    let onAccountAvatarTap: () -> Void
    @Environment(\.setNowPlayingZoomSource) private var setNowPlayingZoomSource
    @Environment(\.nowPlayingHeroNamespace) private var heroNamespace
    @State private var session = SessionStore.shared
    @State private var dailyRecommendations: [Track] = []
    @State private var recommendedPlaylists: [PlaylistSummary] = []
    @State private var dailyPlaylistRecommendations: [PlaylistSummary] = []
    @State private var likedSimilarTracks: [Track] = []
    @State private var personalFMTracks: [Track] = []
    @State private var recommendedArtists: [ArtistSummary] = []
    @State private var presentedDiscoverList: DiscoverInlineList?
    @State private var selectedPlaylistID: Int?
    @State private var selectedArtistID: Int?
    @State private var didLoadDiscoverContent = false
    @State private var player = PlayerService.shared
    @State private var connectivity = NetworkConnectivityMonitor.shared

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
                    if hasAnyHeroCard {
                        heroCardRow
                    }

                    likedSimilarShelf

                    if !recommendedArtists.isEmpty {
                        artistShelf
                    }

                    if !combinedPlaylists.isEmpty {
                        playlistShelf
                    }
                }
                .padding(.bottom, OtoMetrics.screenPadding + 120)
            }
            .refreshable {
                await loadDiscoverContent()
            }
            .onAppear {
                if !didLoadDiscoverContent {
                    restoreDiscoverHomeFromCache()
                }
            }
            .onChange(of: session.profile?.id) { _, newID in
                Task {
                    if newID == nil {
                        await MainActor.run {
                            likedSimilarTracks = []
                        }
                    } else {
                        await loadLikedSimilarTracks()
                        await MainActor.run {
                            DiscoverHomeCacheStore.save(
                                dailyRecommendations: dailyRecommendations,
                                recommendedPlaylists: recommendedPlaylists,
                                dailyPlaylistRecommendations: dailyPlaylistRecommendations,
                                personalFMTracks: personalFMTracks,
                                likedSimilarTracks: likedSimilarTracks,
                                recommendedArtists: recommendedArtists
                            )
                        }
                    }
                }
            }
            .onChange(of: connectivity.isOnline) { _, online in
                if online {
                    Task { await loadDiscoverContent() }
                }
            }
        }
        .navigationTitle(String(localized: String.LocalizationValue("tab_discover")))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                OtoTabProfileAvatarButton(action: onAccountAvatarTap)
            }
        }
        .navigationDestination(item: $presentedDiscoverList) { source in
            switch source {
            case .dailyRecommendations:
                PlaylistView(
                    tracks: dailyRecommendations,
                    title: String(localized: String.LocalizationValue("discover_daily")),
                    listTransitionScope: "discover-daily-mix",
                    playbackSource: .discoverDailyRecommendations,
                    discoverNavigationTransitionSource: .dailyRecommendations,
                    usesSystemNavigationBar: true,
                    showNowPlaying: $showNowPlaying
                )
            case .personalFM:
                PlaylistView(
                    tracks: personalFMTracks,
                    title: String(localized: String.LocalizationValue("discover_personal_fm")),
                    listTransitionScope: "discover-personal-fm",
                    playbackSource: .discoverPersonalFM,
                    discoverNavigationTransitionSource: .personalFM,
                    showNowPlaying: $showNowPlaying
                )
            case .likedSimilar:
                PlaylistView(
                    tracks: likedSimilarTracks,
                    title: PlaybackSource.discoverLikedSimilar.title,
                    listTransitionScope: "discover-liked-similar",
                    playbackSource: .discoverLikedSimilar,
                    discoverNavigationTransitionSource: .likedSimilar,
                    showNowPlaying: $showNowPlaying
                )
            }
        }
        .navigationDestination(item: Binding(
            get: { selectedPlaylistID.map(PlaylistRoute.init(id:)) },
            set: { selectedPlaylistID = $0?.id }
        )) { route in
            PlaylistDetailView(
                playlistID: route.id,
                discoverNavigationTransitionSource: .recommendedPlaylist(id: route.id),
                showNowPlaying: $showNowPlaying
            )
        }
        .navigationDestination(item: Binding(
            get: { selectedArtistID.map(ArtistRoute.init(id:)) },
            set: { selectedArtistID = $0?.id }
        )) { route in
            ArtistDetailView(artistID: route.id, showNowPlaying: $showNowPlaying)
        }
        .task {
            guard !didLoadDiscoverContent else { return }
            didLoadDiscoverContent = true
            await Task.yield()
            await loadDiscoverContent()
        }
        .onReceive(NotificationCenter.default.publisher(for: .otoDiscoverHomeCacheDidUpdate)) { _ in
            restoreDiscoverHomeFromCache()
        }
    }

    private func discoverPlaybackActive(for source: PlaybackSource?) -> Bool {
        guard let source, player.isPlaying else { return false }
        return player.playbackSource == source
    }

    private var hasAnyHeroCard: Bool {
        if !dailyRecommendations.isEmpty { return true }
        if Self.isPersonalFMEnabled, !personalFMTracks.isEmpty { return true }
        return false
    }

    private var heroCardRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                if !dailyRecommendations.isEmpty {
                    discoverHeroStripCard(
                        tracks: dailyRecommendations,
                        title: String(localized: String.LocalizationValue("discover_daily")),
                        onOpenList: { presentedDiscoverList = .dailyRecommendations },
                        playAccessibilityLabel: String(localized: String.LocalizationValue("discover_play_all_daily_a11y")),
                        playbackSource: .discoverDailyRecommendations,
                        navigationTransitionSource: .dailyRecommendations,
                        prepareZoomForPlay: {
                            if let id = dailyRecommendations.first?.id {
                                setNowPlayingZoomSource?(.miniBarTrack(id))
                            }
                        }
                    )
                }
                if Self.isPersonalFMEnabled, !personalFMTracks.isEmpty {
                    discoverHeroStripCard(
                        tracks: personalFMTracks,
                        title: String(localized: String.LocalizationValue("discover_personal_fm")),
                        onOpenList: { presentedDiscoverList = .personalFM },
                        playAccessibilityLabel: String(localized: String.LocalizationValue("discover_play_personal_fm_a11y")),
                        playbackSource: .discoverPersonalFM,
                        navigationTransitionSource: .personalFM,
                        prepareZoomForPlay: {
                            if let id = personalFMTracks.first?.id {
                                setNowPlayingZoomSource?(.miniBarTrack(id))
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, OtoMetrics.screenPadding)
        }
    }

    private func discoverHeroStripCard(
        tracks: [Track],
        title: String,
        onOpenList: @escaping () -> Void,
        playAccessibilityLabel: String,
        playbackSource: PlaybackSource?,
        navigationTransitionSource: DiscoverNavigationTransitionSource?,
        prepareZoomForPlay: @escaping () -> Void
    ) -> some View {
        let sourcePlaying = discoverPlaybackActive(for: playbackSource)
        return ZStack {
            ZStack {
                DailyHeroCoverRotator(tracks: tracks)

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !tracks.isEmpty else { return }
                        onOpenList()
                    }
            }

            VStack {
                Spacer(minLength: 0)
                LinearGradient(
                    colors: [
                        Color.black.opacity(0),
                        Color.black.opacity(0.52)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 118)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 1)
                    .lineLimit(2)
                    .minimumScaleFactor(0.88)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)

            if !sourcePlaying {
                Button {
                    guard !tracks.isEmpty else { return }
                    prepareZoomForPlay()
                    PlayerService.shared.playQueue(tracks: tracks, startIndex: 0, source: playbackSource)
                    showNowPlaying = true
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 34, height: 34)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.25), lineWidth: OtoMetrics.hairlineWidth)
                                )
                        }
                }
                .buttonStyle(.plain)
                .disabled(tracks.isEmpty)
                .accessibilityLabel(playAccessibilityLabel)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(14)
            }

            CoverPlayingNotesOverlay(
                isActive: sourcePlaying,
                coverSide: 108,
                bottomChromeInset: 0,
                usesHeroPlayButtonAnchor: true
            )
        }
        .frame(height: 240)
        .frame(width: 340)
        .otoDiscoverHeroCardClip(
            transitionSourceID: navigationTransitionSource,
            namespace: heroNamespace,
            cornerRadius: OtoMetrics.cardCornerRadius
        )
    }

    /// 与 `NetEaseService.tracksTrimmedToEvenCount` 一致：两排卡片时总数为偶数；仅 1 首时保留。
    private func evenedLikedSimilarTracksForDisplay(_ tracks: [Track]) -> [Track] {
        guard tracks.count > 1, !tracks.count.isMultiple(of: 2) else { return tracks }
        return Array(tracks.dropLast())
    }

    private func likedSimilarTwoRowScroll() -> some View {
        let tracks = likedSimilarTracks
        let mid = (tracks.count + 1) / 2
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(0..<mid, id: \.self) { index in
                            likedSimilarTrackCard(track: tracks[index], globalIndex: index)
                        }
                    }
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(mid..<tracks.count, id: \.self) { index in
                            likedSimilarTrackCard(track: tracks[index], globalIndex: index)
                        }
                    }
                }
            }
            .padding(.horizontal, OtoMetrics.screenPadding)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func likedSimilarTrackCard(track: Track, globalIndex: Int) -> some View {
        Button {
            setNowPlayingZoomSource?(.miniBarTrack(track.id))
            PlayerService.shared.playQueue(
                tracks: likedSimilarTracks,
                startIndex: globalIndex,
                source: .discoverLikedSimilar
            )
            showNowPlaying = true
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                ZStack {
                    RemoteImageView(urlString: track.coverURL)
                    LinearGradient(
                        colors: [Color.black.opacity(0.06), Color.black.opacity(0.18)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    CoverPlayingNotesOverlay(
                        isActive: player.isPlaying
                            && player.currentTrack?.id == track.id
                            && player.playbackSource == .discoverLikedSimilar,
                        coverSide: 132
                    )
                }
                .frame(width: 132, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.otoTextPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)

                    Text(track.artist)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.otoTextSecondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 132, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var likedSimilarShelf: some View {
        if session.isLoggedIn, !likedSimilarTracks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("discover_for_you")
                        .font(.otoSectionTitle)
                        .foregroundStyle(Color.otoTextTertiary)
                    Spacer(minLength: 0)
                    Button("discover_button_all") {
                        presentedDiscoverList = .likedSimilar
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.otoTextSecondary)
                }
                .padding(.horizontal, OtoMetrics.screenPadding)

                likedSimilarTwoRowScroll()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var artistShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("discover_recommended_artists")
                    .font(.otoSectionTitle)
                    .foregroundStyle(Color.otoTextTertiary)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, OtoMetrics.screenPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(recommendedArtists) { artist in
                        Button {
                            selectedArtistID = artist.id
                        } label: {
                            VStack(alignment: .center, spacing: 10) {
                                ZStack {
                                    RemoteImageView(urlString: artist.avatarURL)
                                    LinearGradient(
                                        colors: [Color.black.opacity(0.06), Color.black.opacity(0.2)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                }
                                .frame(width: 132, height: 132)
                                .clipShape(Circle())

                                Text(artist.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.otoTextPrimary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 132)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, OtoMetrics.screenPadding)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var playlistShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("discover_recommended_playlists")
                    .font(.otoSectionTitle)
                    .foregroundStyle(Color.otoTextTertiary)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, OtoMetrics.screenPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(combinedPlaylists) { playlist in
                        Button {
                            selectedPlaylistID = playlist.id
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                playlistCoverTile(for: playlist)

                                Text(playlist.name)
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
                }
                .padding(.horizontal, OtoMetrics.screenPadding)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var combinedPlaylists: [PlaylistSummary] {
        var seen = Set<Int>()
        return (recommendedPlaylists + dailyPlaylistRecommendations).filter { playlist in
            seen.insert(playlist.id).inserted
        }
    }

    @ViewBuilder
    private func playlistCoverTile(for playlist: PlaylistSummary) -> some View {
        ZStack {
            RemoteImageView(urlString: playlist.coverURL)
            LinearGradient(
                colors: [Color.black.opacity(0.06), Color.black.opacity(0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
            CoverPlayingNotesOverlay(
                isActive: player.isPlaying
                    && player.playbackSource?.kind == .playlist
                    && player.playbackSource?.id == playlist.id,
                coverSide: 162
            )
        }
        .frame(width: 162, height: 162)
        .otoDiscoverHeroCardClip(
            transitionSourceID: .recommendedPlaylist(id: playlist.id),
            namespace: heroNamespace,
            cornerRadius: 22
        )
    }

    private func restoreDiscoverHomeFromCache() {
        guard let snapshot = DiscoverHomeCacheStore.load() else { return }
        if let daily = DailyRecommendationsStore.loadValidCache() {
            dailyRecommendations = daily
        } else {
            dailyRecommendations = snapshot.dailyRecommendations
        }
        recommendedPlaylists = snapshot.recommendedPlaylists
        dailyPlaylistRecommendations = snapshot.dailyPlaylistRecommendations
        likedSimilarTracks = evenedLikedSimilarTracksForDisplay(snapshot.likedSimilarTracks)
        personalFMTracks = snapshot.personalFMTracks
        recommendedArtists = snapshot.recommendedArtists

        var urls: [String] = []
        urls.append(contentsOf: dailyRecommendations.map(\.coverURL))
        urls.append(contentsOf: snapshot.personalFMTracks.map(\.coverURL))
        urls.append(contentsOf: snapshot.recommendedPlaylists.map(\.coverURL))
        urls.append(contentsOf: snapshot.dailyPlaylistRecommendations.map(\.coverURL))
        urls.append(contentsOf: likedSimilarTracks.map(\.coverURL))
        urls.append(contentsOf: recommendedArtists.map(\.avatarURL))
        RemoteImageView.prefetch(urlStrings: urls)
    }

    private func loadDiscoverContent() async {
        await DiscoverHomeRefreshService.shared.refreshDiscoverHome()
        await MainActor.run {
            restoreDiscoverHomeFromCache()
        }
    }

    private func loadLikedSimilarTracks() async {
        let userID = await MainActor.run { session.profile?.id }
        guard let userID else {
            await MainActor.run {
                likedSimilarTracks = []
            }
            return
        }

        do {
            let tracks = try await NetEaseService.shared.fetchDiscoverLikedSimilarTracks(userID: userID, limit: 24)
            await MainActor.run {
                likedSimilarTracks = evenedLikedSimilarTracksForDisplay(tracks)
                RemoteImageView.prefetch(urlStrings: likedSimilarTracks.map(\.coverURL))
            }
        } catch {
            await MainActor.run {
                if likedSimilarTracks.isEmpty {
                    likedSimilarTracks = []
                }
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func otoDiscoverHeroCardClip(
        transitionSourceID: DiscoverNavigationTransitionSource?,
        namespace: Namespace.ID?,
        cornerRadius: CGFloat
    ) -> some View {
        #if os(iOS)
        if let transitionSourceID, let namespace {
            self.matchedTransitionSource(id: transitionSourceID, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            self.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        #else
        self.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        #endif
    }
}

// MARK: - Daily hero cover carousel

private struct DailyHeroCoverRotator: View {
    let tracks: [Track]

    private static let slideInterval: TimeInterval = 4
    private static let crossfadeDuration: TimeInterval = 1

    ///列表顺序、去重，仅保留有封面 URL 的曲目（与列表一致的可轮播封面）。
    private var covers: [Track] {
        var seen = Set<Int>()
        return tracks.filter { track in
            !track.coverURL.isEmpty && seen.insert(track.id).inserted
        }
    }

    @State private var frontIndex = 0
    @State private var backIndex = 1
    @State private var showFront = true

    var body: some View {
        ZStack {
            if covers.isEmpty {
                LinearGradient(
                    colors: [Color.otoHeroGlow.opacity(0.24), Color.otoSecondaryGlow.opacity(0.16)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else if covers.count == 1, let only = covers.first {
                coverFill(only)
            } else {
                ZStack {
                    coverFill(covers[backIndex])
                        .opacity(showFront ? 0 : 1)
                        .zIndex(showFront ? 0 : 1)
                    coverFill(covers[frontIndex])
                        .opacity(showFront ? 1 : 0)
                        .zIndex(showFront ? 1 : 0)
                }
                .compositingGroup()
                .onChange(of: tracks.map(\.id)) { _, _ in
                    resetIndices()
                }
                .onAppear {
                    resetIndices()
                }
                .onReceive(Timer.publish(every: Self.slideInterval, on: .main, in: .common).autoconnect()) { _ in
                    guard covers.count > 1 else { return }
                    // 先无动画换掉「背面」图层 URL，再只做 opacity 渐变，避免索引与布局动画和淡入淡出打架导致抖动。
                    var txn = Transaction()
                    txn.disablesAnimations = true
                    withTransaction(txn) {
                        if showFront {
                            backIndex = (frontIndex + 1) % covers.count
                        } else {
                            frontIndex = (backIndex + 1) % covers.count
                        }
                    }
                    withAnimation(.easeInOut(duration: Self.crossfadeDuration)) {
                        showFront.toggle()
                    }
                }
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(0.12),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resetIndices() {
        guard covers.count > 1 else {
            frontIndex = 0
            backIndex = 0
            showFront = true
            return
        }
        frontIndex = 0
        backIndex = 1
        showFront = true
    }

    @ViewBuilder
    private func coverFill(_ track: Track) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                RemoteImageView(urlString: track.coverURL)
                    .aspectRatio(contentMode: .fill)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            }
            .clipped()
    }
}

private struct PlaylistRoute: Identifiable, Hashable {
    let id: Int
}

private struct ArtistRoute: Identifiable, Hashable {
    let id: Int
}
