import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Tracks per-tab navigation screens that hide the system tab bar so the global mini player
/// can reduce its bottom inset instead of leaving a fixed gap where the tab bar was.
@MainActor
@Observable
final class OtoTabShellChrome {
    private var tabBarSuppressionCountByTab: [OtoTab: Int] = [:]
    var selectedTab: OtoTab = .discover

    func beginTabBarSuppression(for tab: OtoTab) {
        tabBarSuppressionCountByTab[tab, default: 0] += 1
    }

    func endTabBarSuppression(for tab: OtoTab) {
        tabBarSuppressionCountByTab[tab, default: 0] = max(0, tabBarSuppressionCountByTab[tab, default: 0] - 1)
    }

    var isMiniPlayerBottomInsetCollapsed: Bool {
        (tabBarSuppressionCountByTab[selectedTab] ?? 0) > 0
    }
}

private struct OtoTabShellChromeKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: OtoTabShellChrome? = nil
}

private struct OtoHostTabKey: EnvironmentKey {
    static let defaultValue: OtoTab? = nil
}

extension EnvironmentValues {
    var otoTabShellChrome: OtoTabShellChrome? {
        get { self[OtoTabShellChromeKey.self] }
        set { self[OtoTabShellChromeKey.self] = newValue }
    }

    /// Set on each root `NavigationStack` inside the tab shell so mini-player inset tracking is scoped per tab.
    var otoHostTab: OtoTab? {
        get { self[OtoHostTabKey.self] }
        set { self[OtoHostTabKey.self] = newValue }
    }
}

enum OtoTab: Hashable {
    case discover
    case search
    case library

    var title: String {
        switch self {
        case .discover: String(localized: String.LocalizationValue("tab_discover"))
        case .search: String(localized: String.LocalizationValue("tab_search"))
        case .library: String(localized: String.LocalizationValue("tab_library"))
        }
    }

    var systemImage: String {
        switch self {
        case .discover: "square.grid.2x2.fill"
        case .search: "magnifyingglass"
        case .library: "heart.fill"
        }
    }
}

struct OtoTabShell: View {
    @Binding var showNowPlaying: Bool
    @Environment(\.setNowPlayingZoomSource) private var setNowPlayingZoomSource
    @State private var session = SessionStore.shared
    @State private var selectedTab: OtoTab = .discover
    @State private var shellChrome = OtoTabShellChrome()
    @State private var player = PlayerService.shared
    @State private var rootContentEpoch = 0
    @State private var showLoginSheet = false
    @State private var showAccountSheet = false
    #if os(iOS)
    @State private var isKeyboardVisible = false
    #endif

    private var shouldShowGlobalBar: Bool {
        #if os(iOS)
        player.currentTrack != nil && !isKeyboardVisible
        #else
        player.currentTrack != nil
        #endif
    }

    private var miniPlayerExtraBottomPadding: CGFloat {
        #if os(iOS)
        shellChrome.isMiniPlayerBottomInsetCollapsed ? 0 : 60
        #else
        16
        #endif
    }

    private var accountAvatarTapAction: () -> Void {
        {
            if session.isLoggedIn {
                showAccountSheet = true
            } else {
                showLoginSheet = true
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DiscoverView(showNowPlaying: $showNowPlaying, onAccountAvatarTap: accountAvatarTapAction)
            }
            .id(rootContentEpoch)
            .environment(\.otoHostTab, OtoTab.discover)
            .tag(OtoTab.discover)
            .tabItem {
                Label(OtoTab.discover.title, systemImage: OtoTab.discover.systemImage)
            }

            NavigationStack {
                SearchView(showNowPlaying: $showNowPlaying, onAccountAvatarTap: accountAvatarTapAction)
            }
            .id(rootContentEpoch)
            .environment(\.otoHostTab, OtoTab.search)
            .tag(OtoTab.search)
            .tabItem {
                Label(OtoTab.search.title, systemImage: OtoTab.search.systemImage)
            }

            if session.isLoggedIn {
                NavigationStack {
                    LibraryView(showNowPlaying: $showNowPlaying, onAccountAvatarTap: accountAvatarTapAction)
                }
                .id(rootContentEpoch)
                .environment(\.otoHostTab, OtoTab.library)
                .tag(OtoTab.library)
                .tabItem {
                    Label(OtoTab.library.title, systemImage: OtoTab.library.systemImage)
                }
            }
        }
        .tint(.otoAccent)
        .environment(\.otoTabShellChrome, shellChrome)
        .onAppear {
            shellChrome.selectedTab = selectedTab
            if !session.isLoggedIn, selectedTab == .library {
                selectedTab = .discover
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            shellChrome.selectedTab = newValue
        }
        .onChange(of: session.isLoggedIn) { _, newValue in
            if newValue, showLoginSheet {
                showLoginSheet = false
                selectedTab = .discover
                rootContentEpoch += 1
            }
            if !newValue, showAccountSheet {
                showAccountSheet = false
                selectedTab = .discover
                rootContentEpoch += 1
            }
        }
        .sheet(isPresented: $showLoginSheet) {
            OtoLoginSheet()
        }
        .sheet(isPresented: $showAccountSheet) {
            OtoAccountSheet()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if shouldShowGlobalBar {
                GlobalNowPlayingBar {
                    if let id = player.currentTrack?.id {
                        setNowPlayingZoomSource?(.miniBarTrack(id))
                    }
                    showNowPlaying = true
                }
                .padding(.horizontal, OtoMetrics.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, miniPlayerExtraBottomPadding)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: shouldShowGlobalBar)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: miniPlayerExtraBottomPadding)
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                isKeyboardVisible = frame.height > 0
            } else {
                isKeyboardVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        #endif
    }
}
