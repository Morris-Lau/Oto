import Foundation
import Observation

enum SessionPersistence {
    static let cookieStringKey = "storymusic.session.cookie-string"

    static func loadCookieString(from defaults: UserDefaults = .standard) -> String? {
        guard let cookieString = defaults.string(forKey: cookieStringKey),
              !cookieString.isEmpty else {
            return nil
        }
        return cookieString
    }

    static func saveCookieString(_ cookieString: String, to defaults: UserDefaults = .standard) {
        guard !cookieString.isEmpty else {
            clearCookieString(from: defaults)
            return
        }
        defaults.set(cookieString, forKey: cookieStringKey)
    }

    static func clearCookieString(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: cookieStringKey)
    }
}

@MainActor
@Observable
final class SessionStore {
    static let shared = SessionStore()

    private init() {}

    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var inflightRefresh: Task<Void, Never>?
    @ObservationIgnored private var hasBootstrappedPersistence = false

    var isLoadingStatus = false
    var isLoggedIn = false
    var profile: UserProfileSummary?
    var playlists: [UserPlaylistSummary] = []
    var collectedPlaylists: [UserPlaylistSummary] = []
    var collectedAlbums: [AlbumSummary] = []
    var likedSongs: [Track] = []
    var qrSession: QRLoginSession?
    var qrState: QRLoginState = .idle
    var qrStatusText = OtoL10n.text("session_qr_hint_default")

    private var likedSongIDs: Set<Int> = []

    /// Restores cookies then applies the last persisted Library snapshot when a session cookie exists (cold start).
    func applyLibraryCacheIfAvailable() async {
        await bootstrapPersistenceIfNeeded()
        guard SessionPersistence.loadCookieString() != nil,
              let snapshot = LibraryCacheStore.load() else {
            return
        }
        profile = snapshot.profile.toModel()
        playlists = snapshot.playlists.map { $0.toModel() }
        collectedPlaylists = snapshot.collectedPlaylists.map { $0.toModel() }
        collectedAlbums = snapshot.collectedAlbums
        likedSongs = snapshot.likedSongs
        likedSongIDs = Set(likedSongs.map(\.id))
        isLoggedIn = profile != nil
    }

    /// 回到前台时把持久化 Cookie 再次写入 API client，减轻长时间挂起后内存会话与磁盘不一致导致的接口失败。
    func reapplyPersistedNetEaseCookies() async {
        guard let cookieString = SessionPersistence.loadCookieString(), !cookieString.isEmpty else {
            return
        }
        await NetEaseService.shared.restoreCookies(from: cookieString)
    }

    /// 合并并发 `refresh` 调用，避免后完成的请求用旧会话覆盖刚登录成功的状态。
    /// - Parameter force: 在「刚完成扫码 / 手机号登录」等会改写 Cookie 的操作之后传 `true`：
    ///   会先等待已在进行的刷新结束，再**强制**用新会话拉取一次。否则若仅 `await` 到的是登录前发起的任务，会直接返回而仍显示未登录。
    func refresh(force: Bool = false) async {
        if let inflightRefresh {
            await inflightRefresh.value
            if !force { return }
        }
        let task = Task { await self.performRefresh() }
        inflightRefresh = task
        defer { inflightRefresh = nil }
        await task.value
    }

    private func performRefresh() async {
        await bootstrapPersistenceIfNeeded()
        isLoadingStatus = true
        defer { isLoadingStatus = false }

        do {
            let profile = try await NetEaseService.shared.fetchCurrentUserProfile()
            self.profile = profile
            self.isLoggedIn = profile != nil

            if let profile {
                async let shelvesTask = NetEaseService.shared.fetchCurrentUserPlaylistShelves()
                async let albumsTask = NetEaseService.shared.fetchCurrentUserAlbumSublist()
                async let likedSongsTask = NetEaseService.shared.fetchLikedSongs(userID: profile.id)

                if let shelves = try? await shelvesTask {
                    playlists = shelves.created
                    collectedPlaylists = shelves.collected
                } else {
                    playlists = []
                    collectedPlaylists = []
                }
                collectedAlbums = (try? await albumsTask) ?? []
                likedSongs = (try? await likedSongsTask) ?? []
                likedSongIDs = Set(likedSongs.map(\.id))
                LibraryCacheStore.save(
                    profile: profile,
                    playlists: playlists,
                    collectedPlaylists: collectedPlaylists,
                    collectedAlbums: collectedAlbums,
                    likedSongs: likedSongs
                )
                qrState = .success
                qrStatusText = OtoL10n.text("session_logged_in", profile.nickname)
                await persistCurrentCookies()
            } else {
                playlists = []
                collectedPlaylists = []
                collectedAlbums = []
                likedSongs = []
                likedSongIDs = []
                qrState = .idle
                qrStatusText = OtoL10n.text("session_not_logged_in")
                clearPersistedCookies()
            }
        } catch {
            qrState = .failed(error.localizedDescription)
            qrStatusText = OtoL10n.text("session_status_failed", error.localizedDescription)
        }
    }

    /// 停止二维码轮询（例如切换到手机号登录时）。
    func cancelQRLoginPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func startQRCodeLogin() {
        pollingTask?.cancel()

        pollingTask = Task {
            await MainActor.run {
                qrState = .waitingScan
                qrStatusText = OtoL10n.text("session_qr_generating")
                qrSession = nil
            }

            do {
                let session = try await NetEaseService.shared.createQRCodeLogin()
                await MainActor.run {
                    qrSession = session
                    qrStatusText = OtoL10n.text("session_qr_scan_prompt")
                }

                while !Task.isCancelled {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    let state = try await NetEaseService.shared.pollQRCodeLogin(key: session.key)

                    await MainActor.run {
                        qrState = state
                        switch state {
                        case .idle:
                            qrStatusText = OtoL10n.text("session_qr_preparing")
                        case .waitingScan:
                            qrStatusText = OtoL10n.text("session_qr_waiting_scan")
                        case .waitingConfirm:
                            qrStatusText = OtoL10n.text("session_qr_waiting_confirm")
                        case .expired:
                            qrStatusText = OtoL10n.text("session_qr_expired")
                        case .success:
                            qrStatusText = OtoL10n.text("session_qr_success_syncing")
                        case let .failed(message):
                            qrStatusText = message
                        }
                    }

                    if state == .success {
                        await refresh(force: true)
                        pollingTask?.cancel()
                        break
                    }

                    if state == .expired {
                        pollingTask?.cancel()
                        break
                    }
                }
            } catch {
                await MainActor.run {
                    qrState = .failed(error.localizedDescription)
                    qrStatusText = OtoL10n.text("session_qr_login_failed", error.localizedDescription)
                }
            }
        }
    }

    @discardableResult
    func sendPhoneLoginCaptcha(phone: String) async -> Bool {
        cancelQRLoginPolling()
        qrStatusText = OtoL10n.text("session_sms_sending")
        do {
            try await NetEaseService.shared.sendPhoneLoginCaptcha(phone: phone)
            qrStatusText = OtoL10n.text("session_sms_sent")
            return true
        } catch {
            qrStatusText = OtoL10n.text("session_sms_send_failed", error.localizedDescription)
            return false
        }
    }

    func loginWithPhone(phone: String, smsCaptcha: String) async {
        cancelQRLoginPolling()
        qrStatusText = OtoL10n.text("session_logging_in")
        do {
            try await NetEaseService.shared.loginWithPhone(
                phone: phone,
                smsCaptcha: smsCaptcha
            )
            qrStatusText = OtoL10n.text("session_login_success_syncing")
            await refresh(force: true)
        } catch {
            qrStatusText = OtoL10n.text("session_login_failed", error.localizedDescription)
        }
    }

    func logout() async {
        pollingTask?.cancel()
        qrSession = nil
        qrState = .idle
        profile = nil
        playlists = []
        collectedPlaylists = []
        collectedAlbums = []
        likedSongs = []
        likedSongIDs = []
        isLoggedIn = false
        qrStatusText = OtoL10n.text("session_logged_out")
        clearPersistedCookies()
        DailyRecommendationsStore.clear()
        DiscoverHomeCacheStore.clear()
        LibraryCacheStore.clear()
        DiscoverDailyRefreshCoordinator.resetForegroundRefreshSchedule()
        MusicDetailCacheStore.clearAll()

        do {
            try await NetEaseService.shared.logoutAndResetClient()
        } catch {
            qrStatusText = OtoL10n.text("session_logout_remote_failed", error.localizedDescription)
        }
    }

    private func bootstrapPersistenceIfNeeded() async {
        guard !hasBootstrappedPersistence else { return }
        hasBootstrappedPersistence = true

        guard let cookieString = SessionPersistence.loadCookieString() else {
            return
        }

        await NetEaseService.shared.restoreCookies(from: cookieString)
    }

    private func persistCurrentCookies() async {
        if let cookieString = await NetEaseService.shared.currentCookieString(), !cookieString.isEmpty {
            SessionPersistence.saveCookieString(cookieString)
        }
    }

    private func clearPersistedCookies() {
        SessionPersistence.clearCookieString()
    }

    func isTrackLiked(_ trackID: Int) -> Bool {
        likedSongIDs.contains(trackID)
    }

    func toggleLikedState(for track: Track) async {
        guard isLoggedIn else {
            qrStatusText = OtoL10n.text("session_like_need_login")
            return
        }

        let shouldLike = !likedSongIDs.contains(track.id)

        do {
            try await NetEaseService.shared.setSongLiked(trackID: track.id, like: shouldLike)

            if shouldLike {
                likedSongIDs.insert(track.id)
                if let existingIndex = likedSongs.firstIndex(where: { $0.id == track.id }) {
                    likedSongs.remove(at: existingIndex)
                }
                likedSongs.insert(track, at: 0)
            } else {
                likedSongIDs.remove(track.id)
                likedSongs.removeAll { $0.id == track.id }
            }
        } catch {
            qrStatusText = OtoL10n.text("session_like_update_failed", error.localizedDescription)
        }
    }
}
