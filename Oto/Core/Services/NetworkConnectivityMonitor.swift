import Foundation
import Network
import Observation

/// 反映设备当前是否具备可用网络路径（与系统「设置 → 无线局域网」一致，用于发现页等离线文案）。
@MainActor
@Observable
final class NetworkConnectivityMonitor {
    static let shared = NetworkConnectivityMonitor()

    private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "works.storymusic.network-path")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                self?.isOnline = online
            }
        }
        monitor.start(queue: queue)
    }
}
