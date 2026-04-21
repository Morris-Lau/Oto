import Foundation

/// 按本地日历日缓存每日推荐；跨冷启动复用，隔日自动失效。
enum DailyRecommendationsStore {
    private static let storageKey = "storymusic.discover.daily-recommendations-v1"

    private struct Payload: Codable {
        let dayKey: String
        let tracks: [Track]
    }

    static func loadValidCache() -> [Track]? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return nil
        }
        guard payload.dayKey == CalendarDayKey.string(), !payload.tracks.isEmpty else { return nil }
        return payload.tracks
    }

    static func save(tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        let payload = Payload(dayKey: CalendarDayKey.string(), tracks: tracks)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
