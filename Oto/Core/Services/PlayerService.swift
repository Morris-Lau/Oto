import Foundation
import AVFoundation

@MainActor
@Observable
final class PlayerService {
    static let shared = PlayerService()

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var currentItemObserver: NSObjectProtocol?
    private var failedItemObserver: NSObjectProtocol?
    private var bufferedObserver: NSKeyValueObservation?

    /// Bumps on every `playCurrentTrack` start so stale async work cannot replace the active `AVPlayer`.
    private var playbackGeneration: UInt64 = 0

    private let persistence = PlaybackContextStore.shared
    private let persistThrottleSeconds = 2.0
    private var lastPersistedTime = 0.0
    #if os(iOS)
    private var lastNowPlayingWholeSecondSynced = Int.min
    #endif

    var isPlaying = false
    var currentTime: Double = 0
    var duration: Double = 0
    var bufferedTime: Double = 0
    var isSeeking = false
    var currentTrack: Track?
    var queue: [Track] = []
    var currentIndex: Int = 0
    var playbackMode: PlaybackMode = .listLoop
    var playbackSource: PlaybackSource?
    /// Set when URL resolution or `AVPlayerItem` fails; cleared when a new track load succeeds.
    var playbackError: String?
    /// Four band envelopes 0...1 from `MTAudioProcessingTap` RMS (Discover equalizer, etc.).
    var playbackVisualizerLevels: [Float] = [0, 0, 0, 0]

    /// Prevents concurrent FM replenishment requests.
    private var isReplenishingPersonalFM = false

    private init() {
        #if os(iOS)
        activatePlaybackAudioSession()
        #endif
    }

    func restoreLastSession() async {
        guard currentTrack == nil else { return }

        guard let context = persistence.loadContext() else {
            return
        }

        guard !context.queue.isEmpty,
              context.currentIndex >= 0,
              context.currentIndex < context.queue.count else {
            persistence.clear()
            return
        }

        queue = context.queue
        currentIndex = context.currentIndex
        currentTime = context.currentTime
        duration = context.duration
        playbackMode = context.playbackMode
        playbackSource = context.playbackSource
        currentTrack = queue[currentIndex]
        isPlaying = false
        playbackError = nil
        playbackVisualizerLevels = [0, 0, 0, 0]
        lastPersistedTime = context.currentTime
        persistIfNeeded(force: true)
        syncSystemPlaybackState(periodicTimeTick: false)
    }

    func play(track: Track) {
        queue = [track]
        currentIndex = 0
        currentTime = 0
        lastPersistedTime = 0
        playbackSource = nil
        Task {
            await playCurrentTrack(track)
        }
    }

    func playQueue(tracks: [Track], startIndex: Int = 0, source: PlaybackSource? = nil) {
        guard !tracks.isEmpty, startIndex >= 0, startIndex < tracks.count else { return }
        queue = tracks
        currentIndex = startIndex
        currentTime = 0
        lastPersistedTime = 0
        playbackSource = source
        Task {
            await playCurrentTrack(tracks[startIndex])
        }
    }

    func updateCurrentTrack(_ track: Track) {
        if let index = queue.firstIndex(where: { $0.id == track.id }) {
            queue[index] = track
            currentIndex = index
        } else {
            queue = [track]
            currentIndex = 0
        }
        Task {
            await playCurrentTrack(track)
        }
    }

    func playCurrentTrackFromQueue() {
        guard currentIndex >= 0, currentIndex < queue.count else { return }
        Task {
            await playCurrentTrack(queue[currentIndex])
        }
    }

    func replaceTrackMetadata(_ track: Track) {
        if let index = queue.firstIndex(where: { $0.id == track.id }) {
            queue[index] = track
            currentIndex = index
        } else {
            queue = [track]
            currentIndex = 0
        }
        playbackError = nil
        currentTrack = track
        persistIfNeeded(force: true)
        syncSystemPlaybackState(periodicTimeTick: false)
    }

    private func playCurrentTrack(_ track: Track, shouldAutoPlay: Bool = true, startTime: Double = 0) async {
        playbackGeneration &+= 1
        let generation = playbackGeneration

        resetPlayer()
        playbackError = nil

        // 先同步当前曲目，避免在解析直链期间 UI / 锁屏仍显示上一首封面与标题。
        let playbackTrack = queue.first(where: { $0.id == track.id }) ?? track
        currentTrack = playbackTrack
        if let queueIndex = queue.firstIndex(where: { $0.id == track.id }) {
            currentIndex = queueIndex
        }
        persistIfNeeded(force: true)
        syncSystemPlaybackState(periodicTimeTick: false)

        let playbackURL = await resolvePlaybackURL(for: playbackTrack)
        guard generation == playbackGeneration else { return }

        guard let playbackURL else {
            handlePlaybackLoadFailure(track: playbackTrack, generation: generation)
            return
        }

        #if os(iOS)
        activatePlaybackAudioSession()
        #endif

        guard generation == playbackGeneration else { return }

        currentTrack = queue.first(where: { $0.id == track.id }) ?? playbackTrack

        let item = AVPlayerItem(url: playbackURL)
        await PlaybackAudioTapInstaller.install(on: item, generation: generation)
        guard generation == playbackGeneration else { return }

        player = AVPlayer(playerItem: item)

        let safeStartTime = max(0, startTime)
        if safeStartTime > 0 {
            player?.seek(to: CMTime(seconds: safeStartTime, preferredTimescale: 600), completionHandler: { _ in })
        } else {
            currentTime = 0
        }
        currentTime = safeStartTime

        if shouldAutoPlay {
            player?.play()
            isPlaying = true
        } else {
            player?.pause()
            isPlaying = false
        }

        if let assetDuration = try? await item.asset.load(.duration),
           assetDuration.isNumeric {
            guard generation == playbackGeneration else { return }
            duration = CMTimeGetSeconds(assetDuration)
        } else {
            guard generation == playbackGeneration else { return }
            duration = 0
        }

        guard generation == playbackGeneration else { return }

        addTimeObserver()

        bufferedObserver = item.observe(\.loadedTimeRanges, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self = self else { return }
                guard generation == self.playbackGeneration else { return }
                guard self.player?.currentItem === item else { return }
                let ranges = item.loadedTimeRanges
                guard let first = ranges.first?.timeRangeValue else { return }
                let end = CMTimeGetSeconds(CMTimeRangeGetEnd(first))
                self.bufferedTime = end
            }
        }

        currentItemObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                guard generation == self.playbackGeneration else { return }
                guard self.player?.currentItem === item else { return }
                self.playNext()
            }
        }

        if playbackSource?.systemRecommendationKind == .personalFM {
            Task {
                await replenishPersonalFMIfNeeded()
            }
        }

        failedItemObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let errorDetail = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                .localizedDescription
            Task { @MainActor in
                guard let self = self else { return }
                guard generation == self.playbackGeneration else { return }
                guard self.player?.currentItem === item else { return }
                self.handleAVPlaybackFailure(errorDetail: errorDetail, generation: generation)
            }
        }

        persistIfNeeded(force: true)
        syncSystemPlaybackState(periodicTimeTick: false)
    }

    func applyVisualizerLevels(_ levels: [Float], generation: UInt64) {
        guard generation == playbackGeneration else { return }
        let capped = (0..<4).map { i in
            let v = i < levels.count ? levels[i] : 0
            return min(1, max(0, v))
        }
        playbackVisualizerLevels = capped
    }

    func playNext() {
        guard !queue.isEmpty else {
            isPlaying = false
            currentTime = 0
            persistIfNeeded(force: true)
            syncSystemPlaybackState(periodicTimeTick: false)
            return
        }

        switch playbackMode {
        case .singleLoop:
            restartCurrentTrackFromBeginning()
            return
        case .shuffle:
            if queue.count <= 1 {
                restartCurrentTrackFromBeginning()
                return
            }
            var nextIndex = currentIndex
            while nextIndex == currentIndex {
                nextIndex = Int.random(in: 0..<queue.count)
            }
            currentIndex = nextIndex
        case .listLoop:
            let nextIndex = currentIndex + 1
            currentIndex = nextIndex >= queue.count ? 0 : nextIndex
        }

        Task {
            await playCurrentTrack(queue[currentIndex])
        }
    }

    func playPrevious() {
        guard !queue.isEmpty else { return }

        if playbackMode == .shuffle && queue.count > 1 {
            var prevIndex = currentIndex
            while prevIndex == currentIndex {
                prevIndex = Int.random(in: 0..<queue.count)
            }
            currentIndex = prevIndex
        } else {
            guard currentIndex > 0 else { return }
            currentIndex -= 1
        }

        Task {
            await playCurrentTrack(queue[currentIndex])
        }
    }

    func jumpTo(index: Int) {
        guard index >= 0, index < queue.count else { return }
        currentIndex = index
        Task {
            await playCurrentTrack(queue[index])
        }
    }

    func clearQueue() {
        resetPlayer()
        currentTrack = nil
        queue = []
        currentIndex = 0
        currentTime = 0
        duration = 0
        playbackSource = nil
        playbackError = nil
        clearContext()
        syncSystemPlaybackState(periodicTimeTick: false)
    }

    func cyclePlaybackMode() {
        switch playbackMode {
        case .listLoop: playbackMode = .singleLoop
        case .singleLoop: playbackMode = .shuffle
        case .shuffle: playbackMode = .listLoop
        }
        persistIfNeeded(force: true)
    }

    // MARK: - Personal FM

    /// 当私人 FM 队列剩余歌曲不多时，自动拉取新歌曲追加到队列。
    private func replenishPersonalFMIfNeeded() async {
        guard playbackSource?.systemRecommendationKind == .personalFM else { return }
        guard !isReplenishingPersonalFM else { return }
        guard currentIndex >= queue.count - 2 else { return }

        isReplenishingPersonalFM = true
        defer { isReplenishingPersonalFM = false }

        do {
            let newTracks = try await NetEaseService.shared.fetchPersonalFM(limit: 3)
            guard !newTracks.isEmpty else { return }
            guard playbackSource?.systemRecommendationKind == .personalFM else { return }

            let existingIDs = Set(queue.map(\.id))
            let uniqueNewTracks = newTracks.filter { !existingIDs.contains($0.id) }
            guard !uniqueNewTracks.isEmpty else { return }

            queue.append(contentsOf: uniqueNewTracks)
            persistIfNeeded(force: true)
        } catch {
            // 静默失败，下次播放时自动重试
        }
    }

    /// 将当前 FM 歌曲移入垃圾桶并切换到下一首。
    func fmTrashCurrentTrack() {
        guard playbackSource?.systemRecommendationKind == .personalFM else { return }
        guard let track = currentTrack else { return }

        // 从队列中移除当前歌曲
        if currentIndex < queue.count, queue[currentIndex].id == track.id {
            queue.remove(at: currentIndex)
            if currentIndex >= queue.count {
                currentIndex = max(0, queue.count - 1)
            }
        }

        // 切到下一首；如果队列空了先补歌
        if !queue.isEmpty, currentIndex < queue.count {
            Task {
                guard self.playbackSource?.systemRecommendationKind == .personalFM else { return }
                await playCurrentTrack(queue[currentIndex])
            }
        } else {
            Task {
                await replenishPersonalFMIfNeeded()
                guard self.playbackSource?.systemRecommendationKind == .personalFM else { return }
                if currentIndex < queue.count {
                    await playCurrentTrack(queue[currentIndex])
                } else {
                    isPlaying = false
                    currentTrack = nil
                    playbackError = nil
                }
            }
        }

        // 后台调用垃圾桶 API
        Task {
            try? await NetEaseService.shared.fmTrash(trackID: track.id)
        }
    }

    func play() {
        #if os(iOS)
        activatePlaybackAudioSession()
        #endif
        if player == nil,
           let track = currentTrack,
           !queue.isEmpty,
           currentIndex >= 0,
           currentIndex < queue.count {
            let resumeTime = currentTime
            Task {
                await playCurrentTrack(track, shouldAutoPlay: true, startTime: resumeTime)
            }
            return
        }
        player?.play()
        isPlaying = true
        playbackError = nil
        persistIfNeeded(force: true)
        syncSystemPlaybackState(periodicTimeTick: false)
    }

    func pause() {
        player?.pause()
        isPlaying = false
        playbackVisualizerLevels = [0, 0, 0, 0]
        persistIfNeeded(force: true)
        syncSystemPlaybackState(periodicTimeTick: false)
    }

    func toggle() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to time: Double) {
        let safeTime = max(0, time)
        let targetTime = CMTime(seconds: safeTime, preferredTimescale: 600)
        isSeeking = true
        player?.seek(to: targetTime) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.currentTime = safeTime
                self.isSeeking = false
            }
        }
        persistIfNeeded(force: true)
        syncSystemPlaybackState(periodicTimeTick: false)
    }

    func clearContext() {
        persistence.clear()
    }

    private func resetPlayer() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        if let itemObserver = currentItemObserver {
            NotificationCenter.default.removeObserver(itemObserver)
            currentItemObserver = nil
        }
        if let failedObserver = failedItemObserver {
            NotificationCenter.default.removeObserver(failedObserver)
            failedItemObserver = nil
        }
        bufferedObserver?.invalidate()
        bufferedObserver = nil
        player?.pause()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        bufferedTime = 0
        playbackVisualizerLevels = [0, 0, 0, 0]
    }

    /// Seek to the start of the current item, then play once the seek completes.
    private func restartCurrentTrackFromBeginning() {
        guard let player, player.currentItem != nil else {
            Task {
                guard currentIndex >= 0, currentIndex < queue.count else { return }
                await playCurrentTrack(queue[currentIndex])
            }
            return
        }
        let target = CMTime(seconds: 0, preferredTimescale: 600)
        player.seek(to: target) { [weak self] finished in
            Task { @MainActor in
                guard let self, finished else { return }
                #if os(iOS)
                self.activatePlaybackAudioSession()
                #endif
                self.player?.play()
                self.isPlaying = true
                self.currentTime = 0
                self.persistIfNeeded(force: true)
                self.syncSystemPlaybackState(periodicTimeTick: false)
            }
        }
    }

    private func handlePlaybackLoadFailure(track: Track, generation: UInt64) {
        guard generation == playbackGeneration else { return }
        if let queueIndex = queue.firstIndex(where: { $0.id == track.id }) {
            currentIndex = queueIndex
        }
        currentTrack = queue.first(where: { $0.id == track.id }) ?? track
        playbackError = String(localized: String.LocalizationValue("error_fetch_playback_url"))
        currentTime = 0
        duration = 0
        isPlaying = false
        persistIfNeeded(force: true)
        syncSystemPlaybackState(periodicTimeTick: false)
    }

    private func handleAVPlaybackFailure(errorDetail: String?, generation: UInt64) {
        guard generation == playbackGeneration else { return }
        playbackError = errorDetail.map { "\(String(localized: String.LocalizationValue("error_playback_failed"))): \($0)" }
            ?? String(localized: String.LocalizationValue("error_playback_failed"))
        resetPlayer()
        isPlaying = false
        currentTime = 0
        duration = 0
        persistIfNeeded(force: true)
        syncSystemPlaybackState(periodicTimeTick: false)
    }

    private func addTimeObserver() {
        guard let player = player else { return }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if !self.isSeeking {
                    self.currentTime = CMTimeGetSeconds(time)
                }
                if let item = player.currentItem, item.duration.isNumeric {
                    self.duration = CMTimeGetSeconds(item.duration)
                }
                if abs(self.currentTime - self.lastPersistedTime) >= self.persistThrottleSeconds {
                    self.persistIfNeeded(force: false)
                    self.lastPersistedTime = self.currentTime
                }
                self.syncSystemPlaybackState(periodicTimeTick: true)
            }
        }
    }

    private func persistIfNeeded(force: Bool) {
        guard !queue.isEmpty,
              currentIndex >= 0,
              currentIndex < queue.count else {
            return
        }

        if !force && abs(currentTime - lastPersistedTime) < persistThrottleSeconds {
            return
        }

        persistence.persist(
            queue: queue,
            currentIndex: currentIndex,
            currentTime: currentTime,
            duration: duration,
            isPlaying: isPlaying,
            playbackMode: playbackMode,
            playbackSource: playbackSource
        )
        lastPersistedTime = currentTime
    }

    private func resolvePlaybackURL(for track: Track) async -> URL? {
        if let downloadedURL = await DownloadService.shared.localFileURL(for: track.id),
           FileManager.default.fileExists(atPath: downloadedURL.path) {
            return downloadedURL
        }

        // 队列/持久化里的 `track.audioURL` 可能早已超过 CDN 签名有效期，不能短路跳过 `song/url`。
        guard let info = try? await NetEaseService.shared.fetchAudioInfo(for: track.id) else {
            return nil
        }
        let remoteRaw = info.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remoteRaw.isEmpty else { return nil }
        let secureRemote = remoteRaw.replacingOccurrences(of: "http://", with: "https://")
        guard let url = URL(string: secureRemote) else { return nil }

        if let index = queue.firstIndex(where: { $0.id == track.id }) {
            queue[index] = Track(
                id: track.id,
                title: track.title,
                artist: track.artist,
                album: track.album,
                albumID: track.albumID,
                artistID: track.artistID,
                coverURL: track.coverURL,
                audioURL: remoteRaw,
                audioType: info.type ?? track.audioType
            )
        }

        return url
    }

    private func syncSystemPlaybackState(periodicTimeTick: Bool) {
        #if os(iOS)
        if periodicTimeTick {
            let whole = Int(floor(currentTime))
            if whole != lastNowPlayingWholeSecondSynced {
                lastNowPlayingWholeSecondSynced = whole
                NowPlayingInfoService.shared.updateNowPlayingInfo()
            }
        } else {
            lastNowPlayingWholeSecondSynced = Int(floor(currentTime))
            NowPlayingInfoService.shared.updateNowPlayingInfo()
        }
        #endif
    }

    #if os(iOS)
    private func activatePlaybackAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay])
            try session.setActive(true, options: [])
        } catch {
            // Best-effort; the session may already be active.
        }
    }
    #endif
}
