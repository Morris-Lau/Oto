import SwiftUI

struct ProfileListView: View {
    let title: String
    let playlists: [UserPlaylistSummary]
    @Binding var showNowPlaying: Bool

    @State private var selectedPlaylist: UserPlaylistSummary?

    var body: some View {
        ZStack {
            BlurredBackground()

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(playlists) { playlist in
                        Button {
                            selectedPlaylist = playlist
                        } label: {
                            LiquidGlassCard {
                                HStack(spacing: 14) {
                                    RemoteImageView(urlString: playlist.coverURL)
                                        .frame(width: 58, height: 58)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(playlist.name)
                                            .font(.otoHeadline)
                                            .foregroundStyle(Color.otoTextPrimary)
                                        Text(String(format: String(localized: String.LocalizationValue("library_playlist_subtitle_tracks_only")), playlist.trackCount))
                                            .font(.otoCaption)
                                            .foregroundStyle(Color.otoTextSecondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.otoTextTertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(OtoMetrics.screenPadding)
                .padding(.bottom, 120)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        #if os(iOS)
        .toolbar(.hidden, for: .tabBar)
            .otoTrackMiniPlayerTabBarSuppression()
        #endif
        .navigationDestination(item: $selectedPlaylist) { playlist in
            PlaylistDetailView(playlistID: playlist.id, showNowPlaying: $showNowPlaying)
        }
    }
}
