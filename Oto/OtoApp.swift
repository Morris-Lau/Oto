import SwiftUI

@main
struct OtoApp: App {
    init() {
        _ = NetworkConnectivityMonitor.shared
        OtoImagePipeline.bootstrap()
        #if os(iOS)
        OtoNavigationBarChrome.applyAppearance()
        NowPlayingInfoService.shared.configureRemoteCommands()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}
