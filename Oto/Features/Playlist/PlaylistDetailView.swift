import SwiftUI

struct PlaylistDetailView: View {
    let playlistID: Int
    let discoverNavigationTransitionSource: DiscoverNavigationTransitionSource?
    @Binding var showNowPlaying: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.nowPlayingHeroNamespace) private var heroNamespace
    @Environment(\.setNowPlayingZoomSource) private var setNowPlayingZoomSource

    init(
        playlistID: Int,
        discoverNavigationTransitionSource: DiscoverNavigationTransitionSource? = nil,
        showNowPlaying: Binding<Bool>
    ) {
        self.playlistID = playlistID
        self.discoverNavigationTransitionSource = discoverNavigationTransitionSource
        self._showNowPlaying = showNowPlaying
    }
    @State private var detail: PlaylistDetailModel?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isDownloadingAll = false
    @State private var downloadAllTask: Task<Void, Never>?
    @State private var pendingNavigation: PendingNavigation? = nil

    private var downloadService: DownloadService { DownloadService.shared }

    var body: some View {
        let stack = ZStack {
            BlurredBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: OtoMetrics.sectionSpacing) {
                    OtoDetailHeader(label: String(localized: String.LocalizationValue("header_playlist"))) {
                        dismiss()
                    }

                    if isLoading {
                        OtoDetailLoadingCard()
                    } else if let errorMessage {
                        OtoDetailErrorCard(title: String(localized: String.LocalizationValue("error_playlist_load")), message: errorMessage)
                    } else if let detail {
                        hero(detail)
                        playlistActionBar(detail)
                        OtoTrackList(
                            tracks: detail.tracks,
                            listTransitionScope: "playlist-\(playlistID)",
                            onSelect: { index in
                                PlayerService.shared.playQueue(
                                    tracks: detail.tracks,
                                    startIndex: index,
                                    source: PlaybackSource(kind: .playlist, label: String(localized: String.LocalizationValue("playing_from_playlist")), title: detail.name, id: playlistID)
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
        .task(id: playlistID) {
            await load()
        }
        .otoMusicInlineNavigation(hidesTabBar: true)
    }

    private func hero(_ detail: PlaylistDetailModel) -> some View {
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

                    if !detail.description.isEmpty {
                        Text(detail.description)
                            .font(.otoCaption)
                            .foregroundStyle(Color.otoTextSecondary)
                            .lineLimit(3)
                    }

                    Text(String(format: String(localized: String.LocalizationValue("playlist_stats_line")), detail.trackCount, detail.playCount))
                        .font(.otoCaption)
                        .foregroundStyle(Color.otoTextTertiary)
                }
            }
        }
    }

    private func playlistActionBar(_ detail: PlaylistDetailModel) -> some View {
        HStack(spacing: 10) {
            Button {
                let scope = "playlist-\(playlistID)"
                if let first = detail.tracks.first {
                    setNowPlayingZoomSource?(.listRow(scope: scope, trackID: first.id, rowIndex: 0))
                }
                PlayerService.shared.playQueue(
                    tracks: detail.tracks,
                    startIndex: 0,
                    source: PlaybackSource(kind: .playlist, label: String(localized: String.LocalizationValue("playing_from_playlist")), title: detail.name, id: playlistID)
                )
                showNowPlaying = true
            } label: {
                OtoPlayAllTracksButtonLabel(title: String(localized: String.LocalizationValue("play_all")))
            }
            .buttonStyle(.plain)
            .disabled(detail.tracks.isEmpty)

            Spacer(minLength: 0)

            playlistDownloadAllButton(tracks: detail.tracks)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func playlistDownloadAllButton(tracks: [Track]) -> some View {
        let allDone = allTracksDownloaded(tracks)
        let busy = isDownloadingAll || tracks.contains { downloadService.isDownloading(trackID: $0.id) }
        let aggregate = playlistAggregateDownloadProgress(tracks: tracks)
        let pct = Int((aggregate * 100).rounded(.down))

        return Button {
            startDownloadAll(tracks: tracks)
        } label: {
            ZStack {
                Circle()
                    .fill(Color.otoPanelFill)
                    .overlay(
                        Circle()
                            .stroke(Color.otoPanelStroke, lineWidth: OtoMetrics.hairlineWidth)
                    )

                if busy, !allDone {
                    if aggregate > 0.004 {
                        Circle()
                            .trim(from: 0, to: aggregate)
                            .stroke(Color.otoAccent, style: StrokeStyle(lineWidth: 2.75, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .padding(3)
                    } else {
                        ProgressView()
                            .scaleEffect(0.58)
                            .tint(Color.otoAccent)
                    }
                }

                Image(systemName: allDone ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(allDone ? Color.otoAccent : Color.otoTextPrimary)
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(allDone || busy)
        .accessibilityLabel(playlistDownloadAccessibilityLabel(allDone: allDone, busy: busy, percent: pct))
    }

    /// Combined 0...1: finished tracks count as 1; in-flight tracks use byte fraction from `DownloadService`.
    private func playlistAggregateDownloadProgress(tracks: [Track]) -> Double {
        guard !tracks.isEmpty else { return 0 }
        var sum = 0.0
        for track in tracks {
            if downloadService.isDownloaded(trackID: track.id) {
                sum += 1
            } else if let f = downloadService.downloadFraction(for: track.id) {
                sum += f
            }
        }
        return min(1, sum / Double(tracks.count))
    }

    private func playlistDownloadAccessibilityLabel(allDone: Bool, busy: Bool, percent: Int) -> String {
        if allDone { return String(localized: String.LocalizationValue("playlist_download_a11y_done")) }
        if busy { return String(format: String(localized: String.LocalizationValue("playlist_download_a11y_busy")), percent) }
        return String(localized: String.LocalizationValue("playlist_download_a11y_start"))
    }

    private func allTracksDownloaded(_ tracks: [Track]) -> Bool {
        guard !tracks.isEmpty else { return false }
        return tracks.allSatisfy { downloadService.isDownloaded(trackID: $0.id) }
    }

    private func startDownloadAll(tracks: [Track]) {
        guard !isDownloadingAll else { return }
        let pending = tracks.filter { !downloadService.isDownloaded(trackID: $0.id) }
        guard !pending.isEmpty else { return }

        isDownloadingAll = true

        downloadAllTask = Task { @MainActor in
            let maxConcurrent = 3
            var index = 0
            while index < pending.count {
                let end = min(index + maxConcurrent, pending.count)
                await downloadBatch(Array(pending[index..<end]))
                index = end
            }
            isDownloadingAll = false
        }
    }

    @MainActor
    private func downloadBatch(_ batch: [Track]) async {
        switch batch.count {
        case 1:
            _ = await DownloadService.shared.downloadIfNeeded(batch[0])
        case 2:
            async let a: Result<Void, Error> = DownloadService.shared.downloadIfNeeded(batch[0])
            async let b: Result<Void, Error> = DownloadService.shared.downloadIfNeeded(batch[1])
            _ = await (a, b)
        default:
            async let a: Result<Void, Error> = DownloadService.shared.downloadIfNeeded(batch[0])
            async let b: Result<Void, Error> = DownloadService.shared.downloadIfNeeded(batch[1])
            async let c: Result<Void, Error> = DownloadService.shared.downloadIfNeeded(batch[2])
            _ = await (a, b, c)
        }
    }

    private func load() async {
        await MainActor.run {
            errorMessage = nil
            if let cached = MusicDetailCacheStore.loadPlaylist(id: playlistID) {
                detail = cached
                isLoading = false
            } else {
                isLoading = true
            }
        }
        do {
            let fresh = try await NetEaseService.shared.fetchPlaylistDetail(id: playlistID)
            await MainActor.run {
                detail = fresh
                isLoading = false
                errorMessage = nil
            }
            MusicDetailCacheStore.savePlaylist(fresh)
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
