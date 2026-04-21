import SwiftUI

public struct AppRootView: View {
    @Namespace private var nowPlayingHero
    @Environment(\.scenePhase) private var scenePhase
    @State private var showNowPlaying = false
    @State private var nowPlayingZoomSource = NowPlayingZoomSourceID.miniBarTrack(0)
    @State private var session = SessionStore.shared
    @State private var player = PlayerService.shared
    @State private var presentedNavigation: PendingNavigation?

    public init() {}

    public var body: some View {
        OtoTabShell(showNowPlaying: $showNowPlaying)
            .environment(\.nowPlayingHeroNamespace, nowPlayingHero)
            .environment(\.setNowPlayingZoomSource) { id in
                nowPlayingZoomSource = id
            }
            .ignoresSafeArea(.keyboard)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    DiscoverDailyRefreshCoordinator.handleSceneBecameActive()
                    Task {
                        await session.reapplyPersistedNetEaseCookies()
                    }
                }
            }
            .task {
                await player.restoreLastSession()
                await session.applyLibraryCacheIfAvailable()
                // 仅当用户曾登录并持久化了 cookie 时才在冷启动拉取账号；无 cookie 的访客由发现页负责首屏内容，
                // 避免首启与发现页请求叠加以减少「一打开就多次联网」与失败态污染登录流程。
                if SessionPersistence.loadCookieString() != nil {
                    await session.refresh()
                }
            }
        #if os(iOS)
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingView(
                namespace: nowPlayingHero,
                nowPlayingZoomSource: $nowPlayingZoomSource,
                onNavigateFromSource: { nav in
                    presentedNavigation = nav
                }
            )
            .fullScreenCover(item: $presentedNavigation) { nav in
                NavigationStack {
                    pendingNavigationDestination(nav)
                }
            }
        }
        #else
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView(
                namespace: nowPlayingHero,
                nowPlayingZoomSource: $nowPlayingZoomSource,
                onNavigateFromSource: { nav in
                    presentedNavigation = nav
                }
            )
            .sheet(item: $presentedNavigation) { nav in
                NavigationStack {
                    pendingNavigationDestination(nav)
                }
            }
        }
        #endif
    }

    @ViewBuilder
    private func pendingNavigationDestination(_ nav: PendingNavigation) -> some View {
        switch nav {
        case .playlist(let id):
            PlaylistDetailView(playlistID: id, showNowPlaying: $showNowPlaying)
        case .album(let id):
            AlbumDetailView(albumID: id, showNowPlaying: $showNowPlaying)
        case .artist(let id):
            ArtistDetailView(artistID: id, showNowPlaying: $showNowPlaying)
        case .dailyRecommendations:
            PlaylistView(
                tracks: player.queue,
                title: PlaybackSource.discoverDailyRecommendations.title,
                listTransitionScope: "now-playing-source-daily",
                playbackSource: .discoverDailyRecommendations,
                usesSystemNavigationBar: true,
                prefersToolbarDismissButton: true,
                showNowPlaying: $showNowPlaying
            )
        case .personalFM:
            PlaylistView(
                tracks: player.queue,
                title: PlaybackSource.discoverPersonalFM.title,
                listTransitionScope: "now-playing-source-personal-fm",
                playbackSource: .discoverPersonalFM,
                showNowPlaying: $showNowPlaying
            )
        case .likedSimilar:
            PlaylistView(
                tracks: player.queue,
                title: PlaybackSource.discoverLikedSimilar.title,
                listTransitionScope: "now-playing-source-liked-similar",
                playbackSource: .discoverLikedSimilar,
                showNowPlaying: $showNowPlaying
            )
        }
    }
}

extension PendingNavigation: Identifiable {
    var id: String {
        switch self {
        case .playlist(let i): return "playlist-\(i)"
        case .album(let i): return "album-\(i)"
        case .artist(let i): return "artist-\(i)"
        case .dailyRecommendations: return "daily-recommendations"
        case .personalFM: return "personal-fm"
        case .likedSimilar: return "liked-similar"
        }
    }
}
