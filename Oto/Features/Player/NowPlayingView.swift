import SwiftUI

struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    private let heroNamespace: Namespace.ID
    @Binding private var nowPlayingZoomSource: NowPlayingZoomSourceID
    private let onNavigateFromSource: ((PendingNavigation) -> Void)?
    @State private var player = PlayerService.shared
    @State private var showQueue = false
    @State private var resolvedTrack: Track?
    @State private var lyricLines: [LyricLine] = []
    @State private var isLoadingURL = true
    @State private var isLoadingLyrics = true
    @State private var loadError: String?
    @State private var lyricError: String?
    @State private var loadTask: Task<Void, Never>?
    @State private var isTogglingLike = false
    @State private var lyricsLoadGeneration: UInt64 = 0
    @State private var showLyrics = false
    @State private var showTranslation = true

    init(namespace: Namespace.ID, nowPlayingZoomSource: Binding<NowPlayingZoomSourceID>, onNavigateFromSource: ((PendingNavigation) -> Void)? = nil) {
        heroNamespace = namespace
        _nowPlayingZoomSource = nowPlayingZoomSource
        self.onNavigateFromSource = onNavigateFromSource
    }

    var body: some View {
        ZStack {
            PlayerBackgroundView(coverURL: player.currentTrack?.coverURL)
            VStack(spacing: 0) {
                VStack(spacing: 28) {
                    NowPlayingTopBar(
                        track: player.currentTrack,
                        isTogglingLike: isTogglingLike,
                        onToggleLike: {
                            guard let track = player.currentTrack else { return }
                            Task { await toggleLike(for: track) }
                        },
                        onDismiss: {
                            if let id = player.currentTrack?.id { nowPlayingZoomSource = .miniBarTrack(id) }
                            dismiss()
                        },
                        onNavigateFromSource: { nav in
                            if let onNavigateFromSource { onNavigateFromSource(nav) } else { dismiss() }
                        }
                    )
                    if let track = player.currentTrack {
                        VStack(spacing: HeroLayout.stackSpacing) {
                            Spacer(minLength: 0)
                            VStack(spacing: HeroLayout.stackSpacing) {
                                NowPlayingHeroCover(
                                    heroNamespace: heroNamespace,
                                    layout: HeroLayout.self,
                                    showLyrics: $showLyrics,
                                    showTranslation: $showTranslation,
                                    lyricLines: $lyricLines,
                                    isLoadingLyrics: $isLoadingLyrics,
                                    lyricError: $lyricError,
                                    nowPlayingZoomSource: $nowPlayingZoomSource
                                )
                                if !showLyrics { trackTitleSubtitle(track) }
                            }
                            .frame(height: HeroLayout.bandHeight)
                            .frame(maxWidth: .infinity)
                            .overlay(alignment: .bottom) {
                                Group {
                                    if let error = loadError ?? player.playbackError {
                                        VStack(spacing: 8) {
                                            Text(error)
                                                .font(.glassCaption)
                                                .foregroundStyle(Color.red.opacity(0.8))
                                                .multilineTextAlignment(.center)
                                            Button {
                                                guard let currentTrack = player.currentTrack else { return }
                                                loadError = nil
                                                Task {
                                                    await loadAudioURL(for: currentTrack)
                                                    guard !Task.isCancelled else { return }
                                                    player.playCurrentTrackFromQueue()
                                                }
                                            } label: {
                                                Text("now_playing_retry")
                                                    .font(.glassHeadline)
                                                    .foregroundStyle(Color.glassPrimary)
                                                    .padding(.horizontal, 24)
                                                    .padding(.vertical, 10)
                                                    .background(
                                                        Capsule()
                                                            .fill(.ultraThinMaterial)
                                                            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                                                    )
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.top, 12)
                                    }
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        PlayerControlsView(track: track, width: 320, isLoading: isLoadingURL, onShowQueue: { showQueue = true })
                            .offset(y: -20)
                    } else {
                        Text("now_playing_empty").font(.glassBody).foregroundStyle(Color.glassSecondary)
                    }
                }
                .frame(maxWidth: 360, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { scheduleTrackMetadataLoad() }
        .onDisappear {
            loadTask?.cancel()
            showQueue = false
        }
        .onChange(of: player.currentTrack) { _, newTrack in
            loadTask?.cancel()
            if newTrack == nil {
                resolvedTrack = nil
                lyricLines = []
                isLoadingURL = false
                isLoadingLyrics = false
                showLyrics = false
                return
            }
            scheduleTrackMetadataLoad()
        }
        .sheet(isPresented: $showQueue) { QueueSheetView() }
    }

    @ViewBuilder
    private func trackTitleSubtitle(_ track: Track) -> some View {
        VStack(spacing: 8) {
            Text(track.title)
                .font(.glassTitle)
                .foregroundStyle(Color.glassPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(track.artist)
                .font(.glassHeadline)
                .foregroundStyle(Color.glassSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity)
    }

    private func scheduleTrackMetadataLoad() {
        loadTask?.cancel()
        guard let track = player.currentTrack else {
            resolvedTrack = nil
            lyricLines = []
            isLoadingURL = false
            isLoadingLyrics = false
            loadTask = nil
            return
        }
        if resolvedTrack?.id == track.id && !lyricLines.isEmpty {
            isLoadingURL = false
            isLoadingLyrics = false
            return
        }
        lyricsLoadGeneration &+= 1
        let lyricsGeneration = lyricsLoadGeneration
        loadTask = Task { @MainActor in await loadTrackMetadata(for: track, lyricsGeneration: lyricsGeneration) }
    }

    private func loadTrackMetadata(for track: Track, lyricsGeneration: UInt64) async {
        async let audioTask: Void = loadAudioURL(for: track)
        async let lyricTask: Void = loadLyrics(for: track, generation: lyricsGeneration)
        _ = await (audioTask, lyricTask)
    }

    private func loadAudioURL(for track: Track) async {
        isLoadingURL = true
        loadError = nil
        defer { if !Task.isCancelled, player.currentTrack?.id == track.id { isLoadingURL = false } }
        guard !Task.isCancelled, player.currentTrack?.id == track.id else { return }
        if await DownloadService.shared.localFileURL(for: track.id) != nil {
            guard !Task.isCancelled, player.currentTrack?.id == track.id else { return }
            resolvedTrack = track
            return
        }
        do {
            let info = try await NetEaseService.shared.fetchAudioInfo(for: track.id)
            guard !Task.isCancelled, player.currentTrack?.id == track.id else { return }
            let updatedTrack = Track(
                id: track.id,
                title: track.title,
                artist: track.artist,
                album: track.album,
                albumID: track.albumID,
                artistID: track.artistID,
                coverURL: track.coverURL,
                audioURL: info.url,
                audioType: info.type ?? track.audioType
            )
            player.replaceTrackMetadata(updatedTrack)
            resolvedTrack = updatedTrack
        } catch {
            guard !Task.isCancelled, player.currentTrack?.id == track.id else { return }
            loadError = String(localized: String.LocalizationValue("error_fetch_playback_url"))
        }
    }

    private func toggleLike(for track: Track) async {
        isTogglingLike = true
        defer { isTogglingLike = false }
        await SessionStore.shared.toggleLikedState(for: track)
    }

    private func loadLyrics(for track: Track, generation: UInt64) async {
        isLoadingLyrics = true
        lyricError = nil
        defer { if !Task.isCancelled, lyricsLoadGeneration == generation { isLoadingLyrics = false } }
        guard !Task.isCancelled, player.currentTrack?.id == track.id else { return }
        do {
            let lines = try await NetEaseService.shared.fetchLyrics(for: track.id)
            guard !Task.isCancelled, player.currentTrack?.id == track.id else { return }
            lyricLines = lines
        } catch {
            guard !Task.isCancelled, player.currentTrack?.id == track.id else { return }
            lyricLines = []
            lyricError = String(localized: String.LocalizationValue("error_load_lyrics"))
        }
    }
}
