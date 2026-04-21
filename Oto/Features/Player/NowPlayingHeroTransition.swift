import SwiftUI

/// Stable identity for iOS zoom transitions between list rows / mini bar and the full-screen player cover.
public enum NowPlayingZoomSourceID: Hashable, Sendable {
    /// Global mini player artwork for `trackID` (must match `PlayerService.currentTrack` when dismissing).
    case miniBarTrack(Int)
    /// A row in a list; `scope` must be unique per on-screen list (e.g. `"album-123"`).
    case listRow(scope: String, trackID: Int, rowIndex: Int)
}

// MARK: - Environment

private enum NowPlayingHeroNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

private enum SetNowPlayingZoomSourceKey: EnvironmentKey {
    static let defaultValue: (@MainActor (NowPlayingZoomSourceID) -> Void)? = nil
}

extension EnvironmentValues {
    var nowPlayingHeroNamespace: Namespace.ID? {
        get { self[NowPlayingHeroNamespaceKey.self] }
        set { self[NowPlayingHeroNamespaceKey.self] = newValue }
    }

    /// When non-nil, call before setting `showNowPlaying` so the zoom transition matches the tapped source.
    var setNowPlayingZoomSource: (@MainActor (NowPlayingZoomSourceID) -> Void)? {
        get { self[SetNowPlayingZoomSourceKey.self] }
        set { self[SetNowPlayingZoomSourceKey.self] = newValue }
    }
}

extension View {
    /// Zoom transition is iOS-only; macOS uses the default sheet animation.
    @ViewBuilder
    func nowPlayingCoverZoomTransition(sourceID: NowPlayingZoomSourceID, namespace: Namespace.ID) -> some View {
        #if os(iOS)
        self.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        #else
        self
        #endif
    }

    /// `matchedTransitionSource` only supports `RoundedRectangle` clip shapes; use a large corner radius (e.g. half the view side) to mimic a circle.
    @ViewBuilder
    func nowPlayingMatchedListArtwork(
        sourceID: NowPlayingZoomSourceID,
        namespace: Namespace.ID?,
        cornerRadius: CGFloat
    ) -> some View {
        #if os(iOS)
        if let namespace {
            self.matchedTransitionSource(id: sourceID, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            self
        }
        #else
        self
        #endif
    }
}
