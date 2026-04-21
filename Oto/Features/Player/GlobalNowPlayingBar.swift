import SwiftUI

public struct GlobalNowPlayingBar: View {
    @State private var player = PlayerService.shared
    @Environment(\.nowPlayingHeroNamespace) private var heroNamespace
    @Environment(\.colorScheme) private var colorScheme
    let onExpand: () -> Void

    public init(onExpand: @escaping () -> Void) {
        self.onExpand = onExpand
    }

    public var body: some View {
        miniPlayerPaddedContent
            .background {
                RoundedRectangle(cornerRadius: OtoMetrics.miniPlayerCornerRadius, style: .continuous)
                    .fill(.bar)
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.38 : 0.14),
                radius: colorScheme == .dark ? 22 : 18,
                x: 0,
                y: colorScheme == .dark ? 14 : 10
            )
            .contentShape(Rectangle())
        .onTapGesture {
            onExpand()
        }
    }

    @ViewBuilder
    private var miniPlayerPaddedContent: some View {
        HStack(spacing: 10) {
            if let track = player.currentTrack {
                RemoteImageView(urlString: track.coverURL, placeholderStyle: .minimal)
                    .frame(width: 36, height: 36)
                    .modifier(MiniBarCoverTransitionModifier(trackID: track.id, namespace: heroNamespace))

                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.glassHeadline)
                        .foregroundStyle(Color.glassPrimary)
                        .lineLimit(1)
                    if let err = player.playbackError {
                        Text(err)
                            .font(.glassCaption)
                            .foregroundStyle(Color.red.opacity(0.85))
                            .lineLimit(1)
                    } else {
                        Text(track.artist)
                            .font(.glassCaption)
                            .foregroundStyle(Color.glassSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button {
                    player.toggle()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.otoAccent)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.otoAccentSoft))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct MiniBarCoverTransitionModifier: ViewModifier {
    let trackID: Int
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        #if os(iOS)
        if let namespace {
            content
                .matchedTransitionSource(id: NowPlayingZoomSourceID.miniBarTrack(trackID), in: namespace) { source in
                    source.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
        } else {
            content
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        #else
        content
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        #endif
    }
}
