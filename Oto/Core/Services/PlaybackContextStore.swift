import Foundation
import Observation

@MainActor
@Observable
final class PlaybackContextStore {
    static let shared = PlaybackContextStore()

    private enum StorageKeys {
        static let playbackContext = "storymusic.session.playback-context"
    }

    private init() {}

    func loadContext() -> PlaybackContext? {
        guard let data = UserDefaults.standard.data(forKey: StorageKeys.playbackContext) else {
            return nil
        }

        let decoder = JSONDecoder()
        return try? decoder.decode(PlaybackContext.self, from: data)
    }

    func persist(
        queue: [Track],
        currentIndex: Int,
        currentTime: Double,
        duration: Double = 0,
        isPlaying: Bool,
        playbackMode: PlaybackMode = .listLoop,
        playbackSource: PlaybackSource? = nil
    ) {
        let context = PlaybackContext(
            queue: queue,
            currentIndex: currentIndex,
            currentTime: max(0, currentTime),
            duration: duration,
            isPlaying: isPlaying,
            timestamp: Date(),
            playbackMode: playbackMode,
            playbackSource: playbackSource
        )

        let encoder = JSONEncoder()
        if let data = try? encoder.encode(context) {
            UserDefaults.standard.set(data, forKey: StorageKeys.playbackContext)
        }
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: StorageKeys.playbackContext)
    }
}

