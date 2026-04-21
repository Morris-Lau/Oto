import SwiftUI

enum HeroLayout {
    static let artworkSide: CGFloat = 280
    static let stackSpacing: CGFloat = 28
    static let bandHeight = artworkSide + stackSpacing + 104
}

struct NowPlayingHeroCover: View {
    @State private var player = PlayerService.shared
    let heroNamespace: Namespace.ID
    let layout: HeroLayout.Type
    @Binding var showLyrics: Bool
    @Binding var showTranslation: Bool
    @Binding var lyricLines: [LyricLine]
    @Binding var isLoadingLyrics: Bool
    @Binding var lyricError: String?
    @Binding var nowPlayingZoomSource: NowPlayingZoomSourceID

    var body: some View {
        ZStack {
            if let track = player.currentTrack {
                Button {
                    showLyrics = true
                } label: {
                    RemoteImageView(urlString: track.coverURL)
                        .frame(width: layout.artworkSide, height: layout.artworkSide)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 30, x: 0, y: 15)
                        .nowPlayingCoverZoomTransition(sourceID: nowPlayingZoomSource, namespace: heroNamespace)
                }
                .buttonStyle(.plain)
                .opacity(showLyrics ? 0 : 1)
                .allowsHitTesting(!showLyrics)

                if showLyrics {
                    HStack {
                        Spacer(minLength: 0)
                        NowPlayingLyricsPanel(
                            lyricLines: $lyricLines,
                            isLoadingLyrics: $isLoadingLyrics,
                            lyricError: $lyricError,
                            showTranslation: $showTranslation,
                            onClose: { showLyrics = false }
                        )
                        .frame(width: layout.artworkSide)
                        .frame(maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 30, x: 0, y: 15)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}
