import SwiftUI

struct NowPlayingLyricsPanel: View {
    @State private var player = PlayerService.shared
    @Binding var lyricLines: [LyricLine]
    @Binding var isLoadingLyrics: Bool
    @Binding var lyricError: String?
    @Binding var showTranslation: Bool
    let onClose: () -> Void

    private var hasTranslations: Bool {
        lyricLines.contains { $0.translation?.isEmpty == false }
    }

    private var currentLyricIndex: Int {
        lyricLines.focusedLyricIndex(at: player.currentTime)
    }

    private func scrollLyricsToCurrentLine(proxy: ScrollViewProxy, animated: Bool) {
        guard !lyricLines.isEmpty else { return }
        let idx = min(max(currentLyricIndex, 0), lyricLines.count - 1)
        if animated {
            withAnimation(.easeInOut(duration: 0.22)) {
                proxy.scrollTo(idx, anchor: .center)
            }
        } else {
            proxy.scrollTo(idx, anchor: .center)
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            lyricContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)


        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var lyricContent: some View {
        if isLoadingLyrics {
            ProgressView("lyrics_loading")
                .tint(Color.glassPrimary)
                .foregroundStyle(Color.glassSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let lyricError {
            Text(lyricError)
                .font(.glassCaption)
                .foregroundStyle(Color.glassSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
        } else if lyricLines.isEmpty {
            Text("now_playing_no_lyrics")
                .font(.glassCaption)
                .foregroundStyle(Color.glassSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        ForEach(Array(lyricLines.enumerated()), id: \.offset) { index, line in
                            let isCurrent = index == currentLyricIndex
                            VStack(spacing: 4) {
                                Text(line.text)
                                    .font(isCurrent ? .glassHeadline : .glassBody)
                                    .fontWeight(isCurrent ? .semibold : .regular)
                                    .foregroundStyle(isCurrent ? Color.glassPrimary : Color.glassSecondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .center)

                                if let translation = line.translation,
                                   !translation.isEmpty {
                                    Text(translation)
                                        .font(.glassCaption)
                                        .foregroundStyle(
                                            (isCurrent ? Color.glassPrimary : Color.glassSecondary)
                                                .opacity(0.75)
                                        )
                                        .multilineTextAlignment(.center)
                                        .lineLimit(nil)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }
                            }
                            .id(index)
                            .onTapGesture { onClose() }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 56)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .mask(OtoLyricsPageVerticalFade.lyricsScrollEdgeMask)
                .onAppear {
                    scrollLyricsToCurrentLine(proxy: proxy, animated: false)
                }
                .onChange(of: lyricLines.count) { _, _ in
                    scrollLyricsToCurrentLine(proxy: proxy, animated: false)
                }
                .onChange(of: isLoadingLyrics) { _, loading in
                    if !loading {
                        scrollLyricsToCurrentLine(proxy: proxy, animated: false)
                    }
                }
                .onChange(of: currentLyricIndex) { _, _ in
                    scrollLyricsToCurrentLine(proxy: proxy, animated: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
