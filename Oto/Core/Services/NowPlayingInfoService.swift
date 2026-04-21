import Foundation
#if os(iOS)
import MediaPlayer
import Nuke
import UIKit

/// `MPMediaItemArtwork` invokes its image handler on MediaPlayer queues (e.g. `accessQueue`), not the main actor.
/// Building the artwork inside `@MainActor` code makes that closure MainActor-isolated and trips `dispatch_assert_queue` / executor checks when the system calls it.
private enum NowPlayingArtworkFactory {
    nonisolated static func artwork(from image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
#endif

@MainActor
public final class NowPlayingInfoService {
    public static let shared = NowPlayingInfoService()

    private var player: PlayerService { PlayerService.shared }

    /// Last posted dictionary (includes artwork) for the current track; used to update elapsed time without re-fetching art or double-writing metadata (avoids Dynamic Island / lock screen cover flicker).
    private var frozenNowPlayingInfo: [String: Any]?
    private var frozenTrackFingerprint: String?

    private init() {}

    private static func trackFingerprint(_ track: Track) -> String {
        "\(track.id)|\(track.title)|\(track.artist)|\(track.coverURL)|\(track.album)"
    }

    public func configureRemoteCommands() {
        #if os(iOS)
        let commandCenter = MPRemoteCommandCenter.shared()

        // Handlers run on MediaPlayer queues (e.g. `MPNowPlayingInfoCenter/accessQueue`). Use the main queue + MainActor so AVPlayer / @Observable state never runs on those queues.
        commandCenter.playCommand.addTarget { _ in
            DispatchQueue.main.async {
                Task { @MainActor in
                    PlayerService.shared.play()
                }
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { _ in
            DispatchQueue.main.async {
                Task { @MainActor in
                    PlayerService.shared.pause()
                }
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { _ in
            DispatchQueue.main.async {
                Task { @MainActor in
                    PlayerService.shared.toggle()
                }
            }
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { _ in
            DispatchQueue.main.async {
                Task { @MainActor in
                    PlayerService.shared.playNext()
                }
            }
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { _ in
            DispatchQueue.main.async {
                Task { @MainActor in
                    PlayerService.shared.playPrevious()
                }
            }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let position = event.positionTime
            DispatchQueue.main.async {
                Task { @MainActor in
                    PlayerService.shared.seek(to: position)
                }
            }
            return .success
        }
        #endif
    }

    func updateNowPlayingInfo() {
        #if os(iOS)
        let track = player.currentTrack
        let duration = player.duration
        let currentTime = player.currentTime
        let isPlaying = player.isPlaying

        // Always defer: avoids re-entrant `MPNowPlayingInfoCenter` <-> `accessQueue` deadlocks when updates are triggered from MediaPlayer internals.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.applyNowPlayingInfo(
                    track: track,
                    duration: duration,
                    currentTime: currentTime,
                    isPlaying: isPlaying
                )
            }
        }
        #endif
    }

    func clearNowPlayingInfo() {
        #if os(iOS)
        frozenNowPlayingInfo = nil
        frozenTrackFingerprint = nil
        DispatchQueue.main.async {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
        #endif
    }

    #if os(iOS)
    private func applyNowPlayingInfo(
        track: Track?,
        duration: Double,
        currentTime: Double,
        isPlaying: Bool
    ) async {
        guard let track else {
            frozenNowPlayingInfo = nil
            frozenTrackFingerprint = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        let fingerprint = Self.trackFingerprint(track)
        if frozenTrackFingerprint == fingerprint, var info = frozenNowPlayingInfo {
            info[MPMediaItemPropertyPlaybackDuration] = duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
            info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
            info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            frozenNowPlayingInfo = info
            return
        }

        // Full refresh: load artwork first, then a single `nowPlayingInfo` write (avoids a frame without art).
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        if let image = await loadArtwork(for: track.coverURL) {
            info[MPMediaItemPropertyArtwork] = NowPlayingArtworkFactory.artwork(from: image)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        frozenNowPlayingInfo = info
        frozenTrackFingerprint = fingerprint
    }

    private func loadArtwork(for urlString: String) async -> UIImage? {
        guard let url = RemoteURLNormalizer.url(from: urlString) else { return nil }
        return try? await ImagePipeline.shared.image(for: url)
    }
    #endif
}
