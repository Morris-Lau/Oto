import Foundation

protocol NetEaseServiceProtocol: Sendable {
    func fetchStory(for trackId: Int) async throws -> MusicStory
}
