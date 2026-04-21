import SwiftUI

struct StoryView: View {
    let trackId: Int
    @Environment(\.dismiss) private var dismiss
    @State private var story: MusicStory?
    @State private var isLoading = true
    @State private var showMockFallback = false

    var body: some View {
        ZStack {
            BlurredBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color.glassPrimary)
                                .padding(12)
                                .background(Circle().fill(.ultraThinMaterial))
                        }
                    }
                    .padding(.horizontal)

                    if let story = story {
                        RemoteImageView(urlString: story.coverImageURL)
                        .frame(width: 200, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)

                        Text(story.title)
                            .font(.glassTitle)
                            .foregroundStyle(Color.glassPrimary)
                            .multilineTextAlignment(.center)

                        Text(story.body)
                            .font(.glassBody)
                            .foregroundStyle(Color.glassSecondary)
                            .lineSpacing(6)
                            .padding(.horizontal)
                    } else if showMockFallback {
                        VStack(spacing: 16) {
                            Text("story_empty")
                                .font(.glassHeadline)
                                .foregroundStyle(Color.glassSecondary)

                            Button {
                                loadMockStory()
                            } label: {
                                Text("story_load_sample")
                                    .font(.glassHeadline)
                                    .foregroundStyle(Color.glassPrimary)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(
                                        Capsule()
                                            .fill(.ultraThinMaterial)
                                            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                                    )
                            }
                        }
                    } else if isLoading {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(Color.glassPrimary)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.vertical)
            }
        }
        .task {
            await loadStory()
        }
    }

    private func loadStory() async {
        isLoading = true
        showMockFallback = false
        do {
            let result = try await NetEaseService.shared.fetchStory(for: trackId)
            story = result
        } catch {
            showMockFallback = true
        }
        isLoading = false
    }

    private func loadMockStory() {
        Task {
            do {
                let result = try await MockNetEaseService.shared.fetchStory(for: trackId)
                story = result
                showMockFallback = false
            } catch {
                showMockFallback = true
            }
        }
    }
}
