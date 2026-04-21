import SwiftUI
import UIKit
import Nuke

/// Reports the measured height of the pinned tab header so `ScrollView` content can `padding(.top,)` and scroll underneath.
enum TabPinnedHeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

extension View {
    func tabPinnedHeaderMeasureHeight() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: TabPinnedHeaderHeightKey.self, value: proxy.size.height)
            }
        }
    }
}

extension View {
    /// Gradient behind the status bar and pinned tab title row; extends under the status bar so list content can scroll beneath.
    func otoTabTopBarFadingBackground() -> some View {
        background(alignment: .top) {
            OtoLyricsPageVerticalFade.tabPinnedHeaderFading
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .top)
        }
    }
}

/// Profile shortcut shown in the top trailing corner of primary tab screens.
struct OtoTabProfileAvatarButton: View {
    @State private var session = SessionStore.shared
    let action: () -> Void

    var body: some View {
        OtoTabProfileAvatarToolbarControl(
            action: action,
            avatarURL: session.profile?.avatarURL,
            hasProfile: session.profile != nil
        )
        .frame(width: OtoTabAvatarToolbarMetrics.hitSide, height: OtoTabAvatarToolbarMetrics.hitSide)
        .fixedSize()
    }
}

// MARK: - UIKit toolbar avatar

/// SwiftUI `Toolbar` aggressively clips bar-button content; a fixed-size `UIButton` avoids cropped circles.
private enum OtoTabAvatarToolbarMetrics {
    static let hitSide: CGFloat = 44
    static let imageSide: CGFloat = 36
}

private struct OtoTabProfileAvatarToolbarControl: UIViewRepresentable {
    let action: () -> Void
    var avatarURL: String?
    var hasProfile: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        container.isUserInteractionEnabled = true
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.imageView?.contentMode = .scaleAspectFill
        button.adjustsImageWhenHighlighted = false
        button.showsMenuAsPrimaryAction = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .vertical)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        button.accessibilityLabel = String(localized: String.LocalizationValue("detail_account_a11y"))

        container.addSubview(button)
        let side = OtoTabAvatarToolbarMetrics.hitSide
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: side),
            container.heightAnchor.constraint(equalToConstant: side),
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: side),
            button.heightAnchor.constraint(equalToConstant: side),
        ])

        context.coordinator.button = button
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let button = context.coordinator.button else { return }
        context.coordinator.sync(button: button, avatarURL: avatarURL, hasProfile: hasProfile)
    }

    @MainActor
    final class Coordinator: NSObject {
        let action: () -> Void
        weak var button: UIButton?
        private var imageTask: ImageTask?
        private var lastKey: String = ""

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func tapped() {
            action()
        }

        func sync(button: UIButton, avatarURL: String?, hasProfile: Bool) {
            self.button = button
            let key: String
            if let url = avatarURL, !url.isEmpty {
                key = "u:\(url)"
            } else {
                key = hasProfile ? "p:empty" : "guest"
            }
            if key == lastKey, button.image(for: .normal) != nil {
                return
            }
            lastKey = key
            imageTask?.cancel()

            let side = OtoTabAvatarToolbarMetrics.imageSide
            let capturedHasProfile = hasProfile

            if let urlString = avatarURL, !urlString.isEmpty, let url = RemoteURLNormalizer.url(from: urlString) {
                imageTask = ImagePipeline.shared.loadImage(with: url, completion: { [weak self, weak button] result in
                    Task { @MainActor in
                        guard let self, let button else { return }
                        switch result {
                        case .success(let response):
                            let img = Self.renderDiskAvatar(source: response.image, side: side)
                            button.setImage(img, for: .normal)
                        case .failure:
                            let fallback = Self.placeholderDiskImage(hasProfile: capturedHasProfile, side: side)
                            button.setImage(fallback, for: .normal)
                        }
                    }
                })
            } else {
                button.setImage(Self.placeholderDiskImage(hasProfile: hasProfile, side: side), for: .normal)
            }
        }

        private static func renderDiskAvatar(source: UIImage, side: CGFloat) -> UIImage {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
            return renderer.image { ctx in
                let rect = CGRect(origin: .zero, size: CGSize(width: side, height: side))
                ctx.cgContext.addEllipse(in: rect)
                ctx.cgContext.clip()
                let iw = source.size.width
                let ih = source.size.height
                guard iw > 0, ih > 0 else { return }
                let scale = max(side / iw, side / ih)
                let w = iw * scale
                let h = ih * scale
                let x = (side - w) / 2
                let y = (side - h) / 2
                source.draw(in: CGRect(x: x, y: y, width: w, height: h))
                ctx.cgContext.resetClip()
                strokeDiskOutline(in: ctx.cgContext, rect: rect)
            }
        }

        private static func placeholderDiskImage(hasProfile: Bool, side: CGFloat) -> UIImage {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
            return renderer.image { ctx in
                let rect = CGRect(origin: .zero, size: CGSize(width: side, height: side))

                let pointSize = side * (hasProfile ? 0.38 : 0.42)
                let weight: UIImage.SymbolWeight = hasProfile ? .medium : .semibold
                let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
                if let sym = UIImage(systemName: "person.fill", withConfiguration: config) {
                    let tint = hasProfile ? OtoDynamicUIColor.accent : OtoDynamicUIColor.textSecondary
                    let tinted = sym.withTintColor(tint, renderingMode: .alwaysOriginal)
                    let sz = tinted.size
                    let origin = CGPoint(x: (side - sz.width) / 2, y: (side - sz.height) / 2)
                    tinted.draw(at: origin)
                }
                strokeDiskOutline(in: ctx.cgContext, rect: rect)
            }
        }

        private static func strokeDiskOutline(in cg: CGContext, rect: CGRect) {
            let inset = max(0.25, OtoMetrics.hairlineWidth / 2)
            let strokeRect = rect.insetBy(dx: inset, dy: inset)
            cg.setStrokeColor(OtoDynamicUIColor.subtleHairlineOnImage.cgColor)
            cg.setLineWidth(OtoMetrics.hairlineWidth)
            cg.strokeEllipse(in: strokeRect)
        }
    }
}

struct OtoDetailHeader: View {
    let label: String
    let dismiss: () -> Void

    var body: some View {
        HStack {
            Button(action: dismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.otoTextPrimary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.otoPanelFill))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(label)
                .font(.otoSectionTitle)
                .foregroundStyle(Color.otoTextTertiary)
                .textCase(.uppercase)

            Spacer()

            Color.clear.frame(width: 34, height: 34)
        }
    }
}

struct OtoDetailLoadingCard: View {
    var body: some View {
        LiquidGlassCard {
            HStack {
                Spacer()
                ProgressView()
                    .tint(.otoAccent)
                Spacer()
            }
            .padding(.vertical, 40)
        }
    }
}

struct OtoDetailErrorCard: View {
    let title: String
    let message: String

    var body: some View {
        LiquidGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.otoHeadline)
                    .foregroundStyle(Color.otoTextPrimary)
                Text(message)
                    .font(.otoCaption)
                    .foregroundStyle(Color.otoTextSecondary)
            }
        }
    }
}

struct OtoTrackList: View {
    let tracks: [Track]
    let listTransitionScope: String
    var showsTrackArtwork: Bool
    let onSelect: (Int) -> Void
    let onDownload: ((Track) -> Void)?
    let onNavigate: ((PendingNavigation) -> Void)?
    @Environment(\.nowPlayingHeroNamespace) private var heroNamespace
    @Environment(\.setNowPlayingZoomSource) private var setNowPlayingZoomSource
    @State private var player = PlayerService.shared
    @State private var actionSheetTrack: Track? = nil

    init(
        tracks: [Track],
        listTransitionScope: String,
        showsTrackArtwork: Bool = true,
        onSelect: @escaping (Int) -> Void,
        onDownload: ((Track) -> Void)? = nil,
        onNavigate: ((PendingNavigation) -> Void)? = nil
    ) {
        self.tracks = tracks
        self.listTransitionScope = listTransitionScope
        self.showsTrackArtwork = showsTrackArtwork
        self.onSelect = onSelect
        self.onDownload = onDownload
        self.onNavigate = onNavigate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("detail_tracks")
                .font(.otoSectionTitle)
                .foregroundStyle(Color.otoTextTertiary)
                .textCase(.uppercase)

            LazyVStack(spacing: 12) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    Button {
                        setNowPlayingZoomSource?(
                            .listRow(scope: listTransitionScope, trackID: track.id, rowIndex: index)
                        )
                        onSelect(index)
                    } label: {
                        Group {
                            if showsTrackArtwork {
                                LiquidGlassCard {
                                    trackRowHStack(index: index, track: track)
                                }
                            } else {
                                LiquidGlassCard {
                                    trackRowHStack(index: index, track: track)
                                }
                                .nowPlayingMatchedListArtwork(
                                    sourceID: .listRow(
                                        scope: listTransitionScope,
                                        trackID: track.id,
                                        rowIndex: index
                                    ),
                                    namespace: heroNamespace,
                                    cornerRadius: OtoMetrics.cardCornerRadius
                                )
                            }
                        }
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.5) {
                            actionSheetTrack = track
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(item: $actionSheetTrack) { track in
            TrackActionSheetView(
                track: track,
                onDismiss: { actionSheetTrack = nil },
                onNavigate: onNavigate
            )
        }
    }

    @ViewBuilder
    private func trackRowHStack(index: Int, track: Track) -> some View {
        let isPlayingRow = player.currentTrack?.id == track.id && player.isPlaying
        HStack(spacing: 14) {
            if showsTrackArtwork {
                RemoteImageView(urlString: track.coverURL, placeholderStyle: .minimal)
                    .frame(width: 48, height: 48)
                    .nowPlayingMatchedListArtwork(
                        sourceID: .listRow(
                            scope: listTransitionScope,
                            trackID: track.id,
                            rowIndex: index
                        ),
                        namespace: heroNamespace,
                        cornerRadius: 10
                    )
            }

            Text("\(index + 1)")
                .font(.otoCaption)
                .foregroundStyle(Color.otoTextTertiary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.otoHeadline)
                    .foregroundStyle(Color.otoTextPrimary)
                Text(track.artist)
                    .font(.otoCaption)
                    .foregroundStyle(Color.otoTextSecondary)
            }

            Spacer()

            if isPlayingRow {
                OtoInlinePlayingIndicator()
            }
        }
    }
}

extension View {
    @ViewBuilder
    func otoMusicInlineNavigation(hidesTabBar: Bool = false) -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(hidesTabBar ? .hidden : .automatic, for: .tabBar)
            .modifier(OtoMiniPlayerTabBarSuppressionModifier(active: hidesTabBar))
        #else
        self
        #endif
    }

    /// System navigation title (inline) plus tab-bar suppression for pushed list screens (e.g. 每日推荐).
    @ViewBuilder
    func otoMusicPushedListNavigation(title: String, hidesTabBar: Bool = false) -> some View {
        #if os(iOS)
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(hidesTabBar ? .hidden : .automatic, for: .tabBar)
            .modifier(OtoMiniPlayerTabBarSuppressionModifier(active: hidesTabBar))
        #else
        navigationTitle(title)
        #endif
    }

    /// Call when hiding the tab bar without `otoMusicInlineNavigation(hidesTabBar:)` (e.g. extra toolbars on a pushed screen).
    @ViewBuilder
    func otoTrackMiniPlayerTabBarSuppression(_ active: Bool = true) -> some View {
        #if os(iOS)
        modifier(OtoMiniPlayerTabBarSuppressionModifier(active: active))
        #else
        self
        #endif
    }
}

#if os(iOS)
private struct OtoMiniPlayerTabBarSuppressionModifier: ViewModifier {
    let active: Bool
    @Environment(\.otoTabShellChrome) private var shellChrome
    @Environment(\.otoHostTab) private var hostTab

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard active, let shellChrome, let hostTab else { return }
                shellChrome.beginTabBarSuppression(for: hostTab)
            }
            .onDisappear {
                guard active, let shellChrome, let hostTab else { return }
                shellChrome.endTabBarSuppression(for: hostTab)
            }
    }
}
#endif
import SwiftUI

struct TrackActionSheetView: View {
    let track: Track
    let onDismiss: () -> Void
    let onNavigate: ((PendingNavigation) -> Void)?

    @State private var session = SessionStore.shared
    @State private var downloadService = DownloadService.shared
    @State private var isTogglingLike = false
    @State private var isDownloading = false
    @State private var showAddToPlaylist = false

    private var isLiked: Bool {
        session.isTrackLiked(track.id)
    }

    private var isDownloaded: Bool {
        downloadService.isDownloaded(trackID: track.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            handle
            trackInfo
            Divider()
                .background(Color.otoPanelStroke)
                .padding(.horizontal, 20)
            actionList
            Spacer(minLength: 0)
        }
        .background(BlurredBackground())
        .presentationDetents([.fraction(session.isLoggedIn ? 0.55 : 0.42)])
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheetView(
                track: track,
                onDismiss: { showAddToPlaylist = false },
                onAdded: {
                    showAddToPlaylist = false
                    onDismiss()
                }
            )
            .presentationDetents([.medium])
        }
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color.otoTextTertiary.opacity(0.4))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 12)
    }

    private var trackInfo: some View {
        HStack(spacing: 14) {
            RemoteImageView(urlString: track.coverURL, placeholderStyle: .minimal)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.otoHeadline)
                    .foregroundStyle(Color.otoTextPrimary)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.otoCaption)
                    .foregroundStyle(Color.otoTextSecondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var actionList: some View {
        VStack(spacing: 0) {
            if session.isLoggedIn {
                actionRow(
                    icon: isLiked ? "heart.fill" : "heart",
                    text: isLiked
                        ? String(localized: String.LocalizationValue("action_unlike"))
                        : String(localized: String.LocalizationValue("action_like")),
                    tint: isLiked ? Color.otoAccent : nil
                ) {
                    Task { await toggleLike() }
                }
            }

            actionRow(
                icon: isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle",
                text: isDownloaded
                    ? String(localized: String.LocalizationValue("action_downloaded"))
                    : String(localized: String.LocalizationValue("action_download")),
                tint: isDownloaded ? Color.otoAccent : nil
            ) {
                Task { await downloadTrack() }
            }

            if let artistID = track.artistID {
                actionRow(
                    icon: "person",
                    text: String(format: String(localized: String.LocalizationValue("action_view_artist")), track.artist)
                ) {
                    onNavigate?(.artist(id: artistID))
                    onDismiss()
                }
            }

            if let albumID = track.albumID {
                actionRow(
                    icon: "record.circle",
                    text: String(format: String(localized: String.LocalizationValue("action_view_album")), track.album)
                ) {
                    onNavigate?(.album(id: albumID))
                    onDismiss()
                }
            }

            if session.isLoggedIn {
                actionRow(
                    icon: "text.badge.plus",
                    text: String(localized: String.LocalizationValue("action_add_to_playlist"))
                ) {
                    showAddToPlaylist = true
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func actionRow(icon: String, text: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(tint ?? Color.otoTextPrimary)
                    .frame(width: 28)

                Text(text)
                    .font(.otoHeadline)
                    .foregroundStyle(tint ?? Color.otoTextPrimary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleLike() async {
        guard !isTogglingLike else { return }
        isTogglingLike = true
        defer { isTogglingLike = false }
        await session.toggleLikedState(for: track)
    }

    private func downloadTrack() async {
        guard !isDownloaded, !isDownloading else { return }
        isDownloading = true
        defer { isDownloading = false }
        _ = await downloadService.downloadIfNeeded(track)
    }
}

// MARK: - Add to Playlist Sheet

struct AddToPlaylistSheetView: View {
    let track: Track
    let onDismiss: () -> Void
    let onAdded: () -> Void

    private var session = SessionStore.shared
    @State private var isAdding = false
    @State private var errorMessage: String?

    init(track: Track, onDismiss: @escaping () -> Void, onAdded: @escaping () -> Void) {
        self.track = track
        self.onDismiss = onDismiss
        self.onAdded = onAdded
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BlurredBackground()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.otoCaption)
                                .foregroundStyle(Color.red.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, OtoMetrics.screenPadding)
                                .padding(.top, 12)
                                .padding(.bottom, 8)
                        }

                        if session.playlists.isEmpty {
                            Text(String(localized: String.LocalizationValue("add_to_playlist_empty")))
                                .font(.otoCaption)
                                .foregroundStyle(Color.otoTextSecondary)
                                .padding(.top, 40)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(session.playlists) { playlist in
                                    playlistRow(playlist)
                                }
                            }
                            .padding(.horizontal, OtoMetrics.screenPadding)
                            .padding(.top, OtoMetrics.sectionSpacing)
                        }
                    }
                    .padding(.bottom, 120)
                }
            }
            .navigationTitle(String(localized: String.LocalizationValue("add_to_playlist_title")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.otoTextPrimary)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func playlistRow(_ playlist: UserPlaylistSummary) -> some View {
        Button {
            Task { await addToPlaylist(playlist) }
        } label: {
            LiquidGlassCard {
                HStack(spacing: 14) {
                    RemoteImageView(urlString: playlist.coverURL)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(playlist.name)
                            .font(.otoHeadline)
                            .foregroundStyle(Color.otoTextPrimary)
                            .lineLimit(1)
                        Text(String(format: String(localized: String.LocalizationValue("library_playlist_subtitle_tracks_only")), playlist.trackCount))
                            .font(.otoCaption)
                            .foregroundStyle(Color.otoTextSecondary)
                    }

                    Spacer()

                    if isAdding {
                        ProgressView()
                            .tint(Color.otoAccent)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isAdding)
    }

    private func addToPlaylist(_ playlist: UserPlaylistSummary) async {
        guard !isAdding else { return }
        isAdding = true
        defer { isAdding = false }
        await MainActor.run { errorMessage = nil }
        do {
            try await NetEaseService.shared.addTrackToPlaylist(trackID: track.id, playlistID: playlist.id)
            await MainActor.run {
                if let index = session.playlists.firstIndex(where: { $0.id == playlist.id }) {
                    let updated = UserPlaylistSummary(
                        id: playlist.id,
                        name: playlist.name,
                        trackCount: playlist.trackCount + 1,
                        playCount: playlist.playCount,
                        coverURL: playlist.coverURL,
                        creatorName: playlist.creatorName
                    )
                    session.playlists[index] = updated
                }
                onAdded()
            }
        } catch {
            await MainActor.run {
                let msg = error.localizedDescription
                errorMessage = msg.isEmpty
                    ? String(localized: String.LocalizationValue("err_add_to_playlist"))
                    : msg
            }
        }
    }
}
