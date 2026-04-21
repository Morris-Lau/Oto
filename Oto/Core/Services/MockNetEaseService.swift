import Foundation

actor MockNetEaseService: NetEaseServiceProtocol {
    static let shared = MockNetEaseService()

    private let stories: [Int: MusicStory] = [
        1: MusicStory(
            id: 1,
            title: "晴天",
            body: "这首歌背后的故事，是周杰伦回忆童年时光。外婆家的旧钢琴、夏天的蝉鸣、还有那个永远回不去的午后。",
            coverImageURL: "https://p2.music.126.net/tGHU62DTszbFQ37W9qPHcg==/2002210674180204.jpg"
        ),
        2: MusicStory(
            id: 2,
            title: "七里香",
            body: "窗外的麻雀，在电线杆上多嘴。这是方文山写给初恋的诗，也是无数人青春里最美的夏天。",
            coverImageURL: "https://p2.music.126.net/tGHU62DTszbFQ37W9qPHcg==/2002210674180204.jpg"
        ),
        3: MusicStory(
            id: 3,
            title: "夜曲",
            body: "肖邦的夜曲是悲伤的，而周杰伦的夜曲是怀念。献给那些消失在黑夜里的人和事。",
            coverImageURL: "https://p2.music.126.net/tGHU62DTszbFQ37W9qPHcg==/2002210674180204.jpg"
        )
    ]

    func fetchStory(for trackId: Int) async throws -> MusicStory {
        try await Task.sleep(nanoseconds: 300_000_000)
        if let story = stories[trackId] {
            return story
        }
        return MusicStory(
            id: trackId,
            title: "未知歌曲",
            body: "暂无音乐故事。",
            coverImageURL: ""
        )
    }
}
