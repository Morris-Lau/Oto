import Foundation
@preconcurrency import NeteaseCloudMusicAPI

actor NetEaseService: NetEaseServiceProtocol {
    static let shared = NetEaseService()

    private var client: NCMClient
    private var cache: [Int: MusicStory] = [:]
    /// 与 `audioURLCache` / 磁盘 L2 对应；cookie 变化时清空 L1+L2，避免串账号命中旧 URL。
    private var audioURLCacheCookieFingerprint: String?
    /// L1：进程内内存。
    private var audioURLCache: [Int: CachedAudioInfo] = [:]
    private let fallbackBaseURL = "https://music.163.com/song/media/outer/url?id="
    /// 直链通常带时效（常短于 30min）；TTL 过长会导致缓存命中但 CDN 已 403。
    private let audioURLCacheTTL: TimeInterval = 10 * 60

    private struct CachedAudioInfo {
        let info: AudioInfo
        let expiresAt: Date
    }

    private init() {
        self.client = NetEaseService.makeConfiguredClient()
    }

    func fetchStory(for trackId: Int) async throws -> MusicStory {
        if let cached = cache[trackId] {
            return cached
        }

        // 当前使用 mock 数据作为兜底
        let story = try await MockNetEaseService.shared.fetchStory(for: trackId)
        cache[trackId] = story
        return story
    }

    /// 搜索歌曲
    /// - Parameters:
    ///   - query: 搜索关键词
    ///   - limit: 返回数量限制
    /// - Returns: 解析后的 Track 数组
    func searchSongs(query: String, limit: Int = 20, offset: Int = 0) async throws -> [Track] {
        let response = try await client.cloudsearch(keywords: query, type: .single, limit: limit, offset: offset)
        return parseSearchResponse(response)
    }

    func searchArtists(query: String, limit: Int = 20, offset: Int = 0) async throws -> [ArtistSummary] {
        let response = try await client.cloudsearch(keywords: query, type: .artist, limit: limit, offset: offset)
        return parseArtistSearchResponse(response)
    }

    func searchAlbums(query: String, limit: Int = 20, offset: Int = 0) async throws -> [AlbumSummary] {
        let response = try await client.cloudsearch(keywords: query, type: .album, limit: limit, offset: offset)
        return parseAlbumSearchResponse(response)
    }

    func searchPlaylists(query: String, limit: Int = 20, offset: Int = 0) async throws -> [PlaylistSummary] {
        let response = try await client.cloudsearch(keywords: query, type: .playlist, limit: limit, offset: offset)
        return parsePlaylistSearchResponse(response)
    }

    /// 获取歌曲播放 URL
    /// - Parameter trackId: 歌曲 ID
    /// - Returns: 可直接播放的音频 URL 字符串
    func fetchAudioURL(for trackId: Int) async throws -> String {
        try await fetchAudioInfo(for: trackId).url
    }

    struct AudioInfo {
        let url: String
        let type: String?
    }

    func fetchAudioInfo(for trackId: Int) async throws -> AudioInfo {
        if let hit = audioInfoIfCached(trackId: trackId) {
            return hit
        }
        let response = try await client.songUrlV1(ids: [trackId], level: .exhigh)
        let info: AudioInfo
        if let data = response.body["data"] as? [[String: Any]],
           let first = data.first,
           let url = first["url"] as? String,
           !url.isEmpty {
            info = AudioInfo(url: RemoteURLNormalizer.sanitize(url), type: first["type"] as? String)
        } else {
            info = AudioInfo(url: "\(fallbackBaseURL)\(trackId).mp3", type: nil)
        }
        storeAudioInfosInCache([trackId: info])
        return info
    }

    /// 批量获取歌曲播放 URL
    /// - Parameter trackIds: 歌曲 ID 数组
    /// - Returns: 字典 [trackId: audioURL]
    func fetchAudioURLs(for trackIds: [Int]) async throws -> [Int: String] {
        let infos = try await fetchAudioInfos(for: trackIds)
        return infos.mapValues { $0.url }
    }

    func fetchAudioInfos(for trackIds: [Int]) async throws -> [Int: AudioInfo] {
        guard !trackIds.isEmpty else { return [:] }
        var result: [Int: AudioInfo] = [:]
        result.reserveCapacity(trackIds.count)
        var missing: [Int] = []
        var seenMissing = Set<Int>()
        for id in trackIds {
            if let hit = audioInfoIfCached(trackId: id) {
                result[id] = hit
            } else if seenMissing.insert(id).inserted {
                missing.append(id)
            }
        }
        if !missing.isEmpty {
            let response = try await client.songUrlV1(ids: missing, level: .exhigh)
            var fetched: [Int: AudioInfo] = [:]
            if let data = response.body["data"] as? [[String: Any]] {
                for item in data {
                    if let id = item["id"] as? Int,
                       let url = item["url"] as? String,
                       !url.isEmpty {
                        fetched[id] = AudioInfo(url: RemoteURLNormalizer.sanitize(url), type: item["type"] as? String)
                    }
                }
            }
            for trackId in missing where fetched[trackId] == nil {
                fetched[trackId] = AudioInfo(url: "\(fallbackBaseURL)\(trackId).mp3", type: nil)
            }
            storeAudioInfosInCache(fetched)
            for (id, info) in fetched {
                result[id] = info
            }
        }
        return result
    }

    func fetchLyrics(for trackID: Int) async throws -> [LyricLine] {
        let response = try await client.lyric(id: trackID)
        guard let lrc = response.body["lrc"] as? [String: Any],
              let rawLyric = lrc["lyric"] as? String else {
            return []
        }
        let mainLines = parseLyricLines(from: rawLyric)

        let translationText = (response.body["tlyric"] as? [String: Any])?["lyric"] as? String ?? ""
        guard !translationText.isEmpty else {
            return mainLines
        }
        let translationLines = parseLyricLines(from: translationText)
        return mergeTranslations(into: mainLines, translations: translationLines)
    }

    private func mergeTranslations(into mainLines: [LyricLine], translations: [LyricLine]) -> [LyricLine] {
        guard !translations.isEmpty else { return mainLines }
        return mainLines.map { line in
            let match = translations.first { abs($0.time - line.time) <= 0.05 }
            return LyricLine(time: line.time, text: line.text, translation: match?.text)
        }
    }

    /// 获取每日推荐歌曲（接口返回多少首就拉多少首，不做截断）。
    /// - Returns: 解析后的 Track 数组（已填充 audioURL）
    func fetchDailyRecommendations() async throws -> [Track] {
        let response = try await client.recommendSongs()
        let tracks = parseRecommendSongsResponse(response)
        return try await fillAudioURLs(for: tracks)
    }

    func fetchRecommendedPlaylists(limit: Int = 6) async throws -> [PlaylistSummary] {
        let response = try await client.personalized(limit: limit)
        let playlists = response.body["result"] as? [[String: Any]] ?? []
        return Array(playlists.compactMap(parsePlaylist).prefix(limit))
    }

    func fetchDailyRecommendedPlaylists(limit: Int = 6) async throws -> [PlaylistSummary] {
        let response = try await client.recommendResource()
        let playlists = response.body["recommend"] as? [[String: Any]] ?? []
        return Array(playlists.compactMap(parsePlaylist).prefix(limit))
    }

    /// 基于红心：从「我喜欢的音乐」中抽取种子，拉取相似歌曲并排除已在红心中的曲目。
    func fetchDiscoverLikedSimilarTracks(userID: Int, limit: Int = 24) async throws -> [Track] {
        let listResponse = try await client.likelist(uid: userID)
        let rawIDs = listResponse.body["ids"] as? [Any] ?? []
        let likedIDs: Set<Int> = Set(rawIDs.compactMap { item -> Int? in
            if let intValue = item as? Int { return intValue }
            if let number = item as? NSNumber { return number.intValue }
            return nil
        })
        guard !likedIDs.isEmpty else { return [] }

        let seeds = likedIDs.shuffled().prefix(3)
        var seen = likedIDs
        var collected: [Track] = []

        for seed in seeds {
            let simi = try await client.simiSong(id: seed, limit: 18, offset: 0)
            let songs = simi.body["songs"] as? [[String: Any]] ?? []
            for raw in songs {
                guard let track = parseSong(raw), !seen.contains(track.id) else { continue }
                seen.insert(track.id)
                collected.append(track)
                if collected.count >= limit {
                    let trimmed = tracksTrimmedToEvenCount(Array(collected.prefix(limit)))
                    return try await fillAudioURLs(for: trimmed)
                }
            }
        }

        return try await fillAudioURLs(for: tracksTrimmedToEvenCount(collected))
    }

    /// 两排横向展示时避免单行多一个；仅在大于 1 且奇数时去掉最后一首（剩 1 首仍展示）。
    private func tracksTrimmedToEvenCount(_ tracks: [Track]) -> [Track] {
        guard tracks.count > 1, !tracks.count.isMultiple(of: 2) else { return tracks }
        return Array(tracks.dropLast())
    }

    func fetchRecommendedArtists(limit: Int = 6) async throws -> [ArtistSummary] {
        let response = try await client.toplistArtist(type: .zh, limit: 100, offset: 0)
        let list = response.body["list"] as? [String: Any] ?? [:]
        let artists = list["artists"] as? [[String: Any]] ?? []
        let parsed = artists.compactMap { parseArtist($0) }
        guard parsed.count > limit else { return parsed }
        return Array(parsed.shuffled().prefix(limit))
    }

    func fetchPersonalFM(limit: Int = 3) async throws -> [Track] {
        let response = try await client.personalFm()
        let payloads = extractPersonalFMSongPayloads(from: response.body)
        return try await fillAudioURLs(for: Array(payloads.compactMap(parseSong).prefix(limit)))
    }

    func fmTrash(trackID: Int) async throws {
        _ = try await client.fmTrash(id: trackID)
    }

    /// `/personal/fm/mode` 等接口有时返回 `data: [{ "song": { ... } }]`，或与云搜索不同的单曲字典。
    private func extractPersonalFMSongPayloads(from body: [String: Any]) -> [[String: Any]] {
        if let rows = body["data"] as? [[String: Any]] {
            return rows.map(unwrapSongIfWrapped)
        }
        if let row = body["data"] as? [String: Any] {
            if let songs = row["songs"] as? [[String: Any]] {
                return songs.map(unwrapSongIfWrapped)
            }
            return [unwrapSongIfWrapped(row)]
        }
        return []
    }

    private func unwrapSongIfWrapped(_ item: [String: Any]) -> [String: Any] {
        if var song = item["song"] as? [String: Any] {
            if song["id"] == nil, let id = intFromJSONField(item["id"]) {
                song["id"] = id
            }
            return song
        }
        return item
    }

    private func intFromJSONField(_ value: Any?) -> Int? {
        switch value {
        case let i as Int: return i
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s)
        default: return nil
        }
    }

    func createQRCodeLogin() async throws -> QRLoginSession {
        let keyResponse = try await client.loginQrKey()
        guard let key = (keyResponse.body["data"] as? [String: Any])?["unikey"] as? String
                ?? keyResponse.body["unikey"] as? String else {
            throw NSError(domain: "Oto.QRLogin", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: String.LocalizationValue("err_qr_no_key"))])
        }

        let qrResponse = try await client.loginQrCreate(key: key, qrimg: true)
        let qrData = qrResponse.body["data"] as? [String: Any] ?? qrResponse.body
        guard let qrURL = qrData["qrurl"] as? String else {
            throw NSError(domain: "Oto.QRLogin", code: -2, userInfo: [NSLocalizedDescriptionKey: String(localized: String.LocalizationValue("err_qr_no_url"))])
        }

        return QRLoginSession(key: key, qrURL: qrURL)
    }

    func pollQRCodeLogin(key: String) async throws -> QRLoginState {
        let response = try await client.loginQrCheck(key: key)
        let code = response.body["code"] as? Int ?? 0
        let message = response.body["message"] as? String ?? String(localized: String.LocalizationValue("err_qr_login_failed"))

        switch code {
        case 800: return .expired
        case 801: return .waitingScan
        case 802: return .waitingConfirm
        case 803: return .success
        default: return .failed(message)
        }
    }

    /// 发送手机号登录短信验证码（网易云「PC登录」流程）。
    func sendPhoneLoginCaptcha(phone: String, countryCode: String = "86") async throws {
        let trimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "Oto.PhoneAuth", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: String.LocalizationValue("err_phone_required"))])
        }
        do {
            _ = try await client.captchaSent(phone: trimmed, ctcode: countryCode)
        } catch {
            throw Self.mapPhoneAuthError(error)
        }
    }

    /// 手机号登录（仅短信验证码）。
    func loginWithPhone(phone: String, countryCode: String = "86", smsCaptcha: String) async throws {
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPhone.isEmpty else {
            throw NSError(domain: "Oto.PhoneAuth", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: String.LocalizationValue("err_phone_required"))])
        }
        let trimmedCaptcha = smsCaptcha.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCaptcha.isEmpty else {
            throw NSError(domain: "Oto.PhoneAuth", code: 2, userInfo: [NSLocalizedDescriptionKey: String(localized: String.LocalizationValue("err_sms_required"))])
        }

        do {
            let response = try await client.loginCellphone(
                phone: trimmedPhone,
                password: "",
                countrycode: countryCode,
                captcha: trimmedCaptcha
            )
            // 手机号登录在风控、频控时常见 HTTP 200 + body.code=10004，Netease SDK 不会抛错，需自行校验。
            try Self.validateCellphoneLoginBody(response.body)
        } catch {
            throw Self.mapPhoneAuthError(error)
        }
    }

    func fetchCurrentUserProfile() async throws -> UserProfileSummary? {
        let response = try await client.loginStatus()
        guard let userID = extractCurrentUserID(from: response) else {
            return nil
        }

        let detailResponse = try await client.userDetail(uid: userID)
        let profile = detailResponse.body["profile"] as? [String: Any] ?? response.body["profile"] as? [String: Any] ?? [:]

        let nickname = profile["nickname"] as? String ?? String(localized: String.LocalizationValue("default_nickname"))
        let signature = profile["signature"] as? String ?? ""
        let avatarURL = RemoteURLNormalizer.sanitize(profile["avatarUrl"] as? String)

        return UserProfileSummary(
            id: userID,
            nickname: nickname,
            signature: signature,
            avatarURL: avatarURL
        )
    }

    /// 拉取当前用户「自建」与「收藏」歌单（`/api/user/playlist` 分页直至取完）
    /// - Note: 多页时使用独立 `NCMClient` + cookie 快照并行请求，避免在 actor 内串行排队；歌单详情页不再批量预取播放 URL（播放/下载时会按需补齐）。
    func fetchCurrentUserPlaylistShelves(pageSize: Int = 100) async throws -> (created: [UserPlaylistSummary], collected: [UserPlaylistSummary]) {
        let response = try await client.loginStatus()
        guard let userID = extractCurrentUserID(from: response) else {
            return ([], [])
        }

        let cookieSnapshot = currentCookieString()
        var allRaw: [[String: Any]] = []
        var nextWaveStart = 0
        let safetyMaxOffset = 5000
        let parallelPages = 4

        while nextWaveStart <= safetyMaxOffset {
            var waveOffsets: [Int] = []
            waveOffsets.reserveCapacity(parallelPages)
            for i in 0..<parallelPages {
                let o = nextWaveStart + i * pageSize
                guard o <= safetyMaxOffset else { break }
                waveOffsets.append(o)
            }
            if waveOffsets.isEmpty { break }

            let pairs = try await Self.fetchUserPlaylistPagesParallel(
                cookieString: cookieSnapshot,
                userID: userID,
                limit: pageSize,
                offsets: waveOffsets
            )
            let sorted = pairs.sorted { $0.0 < $1.0 }

            var reachedEnd = false
            for (_, batch) in sorted {
                if batch.isEmpty {
                    reachedEnd = true
                    break
                }
                allRaw.append(contentsOf: batch)
                if batch.count < pageSize {
                    reachedEnd = true
                    break
                }
            }
            if reachedEnd { break }
            nextWaveStart = (waveOffsets.last ?? nextWaveStart) + pageSize
        }

        var created: [UserPlaylistSummary] = []
        var collected: [UserPlaylistSummary] = []
        created.reserveCapacity(allRaw.count)
        collected.reserveCapacity(allRaw.count / 4)
        var seenIDs = Set<Int>()

        for item in allRaw {
            let creatorID = Self.jsonIntField((item["creator"] as? [String: Any])?["userId"])
            let isCreatedByCurrentUser = creatorID == userID
            guard let summary = parseUserPlaylistSummary(from: item, includeCreator: !isCreatedByCurrentUser) else {
                continue
            }
            guard seenIDs.insert(summary.id).inserted else { continue }
            if isCreatedByCurrentUser {
                created.append(summary)
            } else {
                collected.append(summary)
            }
        }

        return (created, collected)
    }

    private func parseUserPlaylistSummary(from item: [String: Any], includeCreator: Bool) -> UserPlaylistSummary? {
        guard let id = item["id"] as? Int,
              let name = item["name"] as? String else {
            return nil
        }

        let creatorName: String? = includeCreator
            ? (item["creator"] as? [String: Any])?["nickname"] as? String
            : nil

        return UserPlaylistSummary(
            id: id,
            name: name,
            trackCount: item["trackCount"] as? Int ?? 0,
            playCount: item["playCount"] as? Int ?? 0,
            coverURL: playlistCoverImageURL(from: item),
            creatorName: creatorName
        )
    }

    private func jsonBool(_ value: Any?) -> Bool {
        switch value {
        case let b as Bool: return b
        case let i as Int: return i != 0
        case let n as NSNumber: return n.boolValue
        default: return false
        }
    }

    /// 当前账号收藏的专辑（`/api/album/sublist`）
    func fetchCurrentUserAlbumSublist(limit: Int = 50, offset: Int = 0) async throws -> [AlbumSummary] {
        let response = try await client.albumSublist(limit: limit, offset: offset)
        let body = response.body
        let rawAlbums = extractAlbumSublistPayload(from: body)
        return rawAlbums.compactMap(parseAlbumSublistRow)
    }

    private func parseAlbumSublistRow(_ item: [String: Any]) -> AlbumSummary? {
        if let nested = item["album"] as? [String: Any] {
            return parseAlbum(nested)
        }
        return parseAlbum(item)
    }

    private func extractAlbumSublistPayload(from body: [String: Any]) -> [[String: Any]] {
        if let data = body["data"] as? [[String: Any]] {
            return data
        }
        if let data = body["data"] as? [String: Any] {
            if let albums = data["albums"] as? [[String: Any]] { return albums }
            if let list = data["list"] as? [[String: Any]] { return list }
        }
        if let albums = body["albums"] as? [[String: Any]] {
            return albums
        }
        return []
    }

    func fetchLikedSongs(userID: Int, limit: Int = 50) async throws -> [Track] {
        let response = try await client.likelist(uid: userID)
        let rawIDs = response.body["ids"] as? [Any] ?? []
        let ids = Array(rawIDs.compactMap { item -> Int? in
            if let intValue = item as? Int {
                return intValue
            }
            if let number = item as? NSNumber {
                return number.intValue
            }
            return nil
        }.prefix(limit))

        guard !ids.isEmpty else { return [] }

        let detailResponse = try await client.songDetail(ids: ids)
        let detailTracks = parseSongListResponse(detailResponse)
        let hydratedTracks = try await fillAudioURLs(for: detailTracks)
        let trackByID = Dictionary(uniqueKeysWithValues: hydratedTracks.map { ($0.id, $0) })

        return ids.compactMap { trackByID[$0] }
    }

    func setSongLiked(trackID: Int, like: Bool) async throws {
        _ = try await client.like(id: trackID, like: like)
    }

    func addTrackToPlaylist(trackID: Int, playlistID: Int) async throws {
        let response = try await client.playlistTracks(op: "add", pid: playlistID, trackIds: [trackID])
        if let code = Self.jsonIntField(response.body["code"]), code != 200 {
            let msg = (response.body["message"] as? String)
                ?? (response.body["msg"] as? String)
                ?? String(localized: String.LocalizationValue("err_add_to_playlist"))
            throw NSError(domain: "Oto.Playlist", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    func fetchPlaylistDetail(id: Int) async throws -> PlaylistDetailModel {
        async let detailResponse = client.playlistDetail(id: id)
        async let trackResponse = client.playlistTrackAll(id: id, limit: 200, offset: 0)

        let detail = try await detailResponse
        let trackList = try await trackResponse

        let playlist = detail.body["playlist"] as? [String: Any] ?? [:]
        let name = playlist["name"] as? String ?? String(localized: String.LocalizationValue("default_playlist_name"))
        let description = playlist["description"] as? String ?? ""
        let coverURL = RemoteURLNormalizer.sanitize(playlist["coverImgUrl"] as? String)
        let playCount = playlist["playCount"] as? Int ?? 0
        let trackCount = playlist["trackCount"] as? Int ?? 0
        // 不在此批量请求 song/url：列表可立即展示；开始播放或下载时由 PlayerService / DownloadService 按需补全 audioURL。
        let tracks = parseSongListResponse(trackList)

        return PlaylistDetailModel(
            id: id,
            name: name,
            description: description,
            coverURL: coverURL,
            playCount: playCount,
            trackCount: trackCount,
            tracks: tracks
        )
    }

    func fetchAlbumDetail(id: Int) async throws -> AlbumDetailModel {
        let response = try await client.album(id: id)
        let album = response.body["album"] as? [String: Any] ?? [:]
        let songs = response.body["songs"] as? [[String: Any]] ?? []

        //专辑接口里每首歌的 `al` 有时不带 `picUrl`，只有顶层 `album` 有封面；列表用空字符串会整页加载失败占位图。
        let albumCover = RemoteURLNormalizer.sanitize(
            album["picUrl"] as? String ?? album["blurPicUrl"] as? String ?? ""
        )
        let parsed = songs.compactMap { parseSong($0) }.map { track -> Track in
            guard track.coverURL.isEmpty else { return track }
            return Track(
                id: track.id,
                title: track.title,
                artist: track.artist,
                album: track.album,
                albumID: track.albumID,
                artistID: track.artistID,
                coverURL: albumCover,
                audioURL: track.audioURL,
                audioType: track.audioType
            )
        }
        let artist = ((album["artists"] as? [[String: Any]])?.first?["name"] as? String)
            ?? (album["artist"] as? [String: Any])?["name"] as? String
            ?? String(localized: String.LocalizationValue("default_unknown_artist"))

        let publishInfo: String
        if let publishTime = album["publishTime"] as? Int64, publishTime > 0 {
            let date = Date(timeIntervalSince1970: TimeInterval(publishTime) / 1000)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy.MM.dd"
            publishInfo = formatter.string(from: date)
        } else {
            publishInfo = String(localized: String.LocalizationValue("publish_info_album"))
        }

        return AlbumDetailModel(
            id: id,
            name: album["name"] as? String ?? String(localized: String.LocalizationValue("default_album")),
            artist: artist,
            coverURL: albumCover,
            publishInfo: publishInfo,
            tracks: parsed
        )
    }

    func fetchArtistDetail(id: Int) async throws -> ArtistDetailModel {
        async let detailResponse = client.artistDetail(id: id)
        async let topSongResponse = client.artistTopSong(id: id)
        async let albumResponse = client.artistAlbum(id: id, limit: 100, offset: 0)

        let detail = try await detailResponse
        let topSongs = try await topSongResponse
        let albums = try await albumResponse

        let data = detail.body["data"] as? [String: Any] ?? [:]
        let artist = data["artist"] as? [String: Any] ?? [:]
        let aliases = artist["alias"] as? [String] ?? []
        let fansCount = (data["secondaryExpertIdentiy"] as? [String: Any])?["fansCount"] as? Int ?? 0
        let hotSongs = topSongs.body["songs"] as? [[String: Any]] ?? []
        let hotAlbums = albums.body["hotAlbums"] as? [[String: Any]] ?? []

        return ArtistDetailModel(
            id: id,
            name: artist["name"] as? String ?? String(localized: String.LocalizationValue("default_artist")),
            alias: aliases.joined(separator: " / "),
            avatarURL: RemoteURLNormalizer.sanitize(artist["cover"] as? String ?? artist["img1v1Url"] as? String ?? ""),
            fansCount: fansCount,
            topTracks: hotSongs.compactMap { parseSong($0) },
            featuredAlbums: hotAlbums.compactMap(parseAlbum)
        )
    }

    func restoreCookies(from cookieString: String) {
        guard !cookieString.isEmpty else { return }
        if audioURLCacheCookieFingerprint != cookieString {
            clearAudioURLCache()
            audioURLCacheCookieFingerprint = cookieString
        }
        client.setCookie(cookieString)
    }

    func currentCookieString() -> String? {
        let cookies = client.currentCookies
        guard !cookies.isEmpty else { return nil }

        return cookies
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "; ")
    }

    func logoutAndResetClient() async throws {
        let activeClient = client
        defer {
            client = NetEaseService.makeConfiguredClient()
            clearAudioURLCache()
            audioURLCacheCookieFingerprint = nil
        }
        _ = try await activeClient.logout()
    }

    // MARK: - 私有解析方法

    /// L1 → L2 → 未命中则返回 nil，由调用方走 L3（`song/url`）。
    private func audioInfoIfCached(trackId: Int) -> AudioInfo? {
        if let entry = audioURLCache[trackId] {
            if entry.expiresAt > Date() { return entry.info }
            audioURLCache[trackId] = nil
        }
        if let disk = AudioURLCacheStore.read(trackId: trackId, fingerprint: audioURLCacheCookieFingerprint) {
            let info = AudioInfo(url: disk.url, type: disk.type)
            audioURLCache[trackId] = CachedAudioInfo(info: info, expiresAt: disk.expiresAt)
            return info
        }
        return nil
    }

    private func storeAudioInfosInCache(_ infos: [Int: AudioInfo]) {
        let expiresAt = Date().addingTimeInterval(audioURLCacheTTL)
        for (id, info) in infos {
            audioURLCache[id] = CachedAudioInfo(info: info, expiresAt: expiresAt)
        }
        let diskPayload = Dictionary(uniqueKeysWithValues: infos.map { id, info in
            (id, AudioURLCacheStore.Entry(url: info.url, type: info.type))
        })
        AudioURLCacheStore.writeBatch(trackIdsAndInfo: diskPayload, expiresAt: expiresAt, fingerprint: audioURLCacheCookieFingerprint)
    }

    private func clearAudioURLCache() {
        audioURLCache.removeAll(keepingCapacity: false)
        AudioURLCacheStore.clearAll()
    }

    private func fillAudioURLs(for tracks: [Track]) async throws -> [Track] {
        let ids = tracks.map(\.id)
        let infos = try await fetchAudioInfos(for: ids)
        return tracks.map { track in
            let info = infos[track.id]
            return Track(
                id: track.id,
                title: track.title,
                artist: track.artist,
                album: track.album,
                albumID: track.albumID,
                artistID: track.artistID,
                coverURL: track.coverURL,
                audioURL: info?.url ?? "",
                audioType: info?.type
            )
        }
    }

    private func parseSearchResponse(_ response: APIResponse) -> [Track] {
        guard let result = response.body["result"] as? [String: Any],
              let songs = result["songs"] as? [[String: Any]] else {
            return []
        }
        return songs.compactMap { parseSong($0) }
    }

    private func parseRecommendSongsResponse(_ response: APIResponse) -> [Track] {
        guard let data = response.body["data"] as? [String: Any],
              let songs = data["dailySongs"] as? [[String: Any]] else {
            return []
        }
        return songs.compactMap { parseSong($0) }
    }

    private func parseArtistSearchResponse(_ response: APIResponse) -> [ArtistSummary] {
        guard let result = response.body["result"] as? [String: Any],
              let artists = result["artists"] as? [[String: Any]] else {
            return []
        }
        return artists.compactMap(parseArtist)
    }

    private func parseAlbumSearchResponse(_ response: APIResponse) -> [AlbumSummary] {
        guard let result = response.body["result"] as? [String: Any],
              let albums = result["albums"] as? [[String: Any]] else {
            return []
        }
        return albums.compactMap(parseAlbum)
    }

    private func parsePlaylistSearchResponse(_ response: APIResponse) -> [PlaylistSummary] {
        guard let result = response.body["result"] as? [String: Any],
              let playlists = result["playlists"] as? [[String: Any]] else {
            return []
        }
        return playlists.compactMap(parsePlaylist)
    }

    private func parseSongListResponse(_ response: APIResponse) -> [Track] {
        guard let songs = response.body["songs"] as? [[String: Any]] else {
            return []
        }
        return songs.compactMap { parseSong($0) }
    }

    private nonisolated static func jsonIntField(_ value: Any?) -> Int? {
        switch value {
        case let i as Int: return i
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s)
        default: return nil
        }
    }

    private func extractCurrentUserID(from response: APIResponse) -> Int? {
        if let profile = response.body["profile"] as? [String: Any],
           let userID = Self.jsonIntField(profile["userId"]) {
            return userID
        }

        if let account = response.body["account"] as? [String: Any] {
            if let userID = Self.jsonIntField(account["id"]) { return userID }
            if let userID = Self.jsonIntField(account["userId"]) { return userID }
        }

        return nil
    }

    /// 校验 `/api/w/login/cellphone` 业务结果：有 `account` / `profile` 或 `code == 200` 视为成功。
    private nonisolated static func validateCellphoneLoginBody(_ body: [String: Any]) throws {
        if body["account"] != nil || body["profile"] != nil { return }
        guard let code = jsonIntField(body["code"]) else { return }
        guard code != 200 else { return }

        var msg = (body["message"] as? String)
            ?? (body["msg"] as? String)
            ?? String(localized: String.LocalizationValue("err_login_rejected"))
        if [10003, 10004].contains(code) {
            msg += "\n" + String(localized: String.LocalizationValue("session_phone_login_risk_try_qr"))
        }
        throw NSError(domain: "Oto.PhoneAuth", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
    }

    private nonisolated static func mapPhoneAuthError(_ error: Error) -> Error {
        guard let ncm = error as? NCMError else { return error }
        if case .apiError(let apiCode, let body) = ncm {
            var msg = (body["msg"] as? String)
                ?? (body["message"] as? String)
                ?? ncm.localizedDescription
            if let businessCode = jsonIntField(body["code"]), [10003, 10004].contains(businessCode) {
                msg += "\n" + String(localized: String.LocalizationValue("session_phone_login_risk_try_qr"))
            }
            return NSError(domain: "Oto.PhoneAuth", code: apiCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return error
    }

    /// JSON 解码后的歌单项在并发边界传递；`[String: Any]` 本身非 Sendable，故用 unchecked 包装（数据来自 API，仅在本方法内消费）。
    private struct UserPlaylistPageRows: @unchecked Sendable {
        let offset: Int
        let rows: [[String: Any]]
    }

    /// 并行分页拉取用户歌单（每页独立 client，避免阻塞主 service actor）。
    private nonisolated static func fetchUserPlaylistPagesParallel(
        cookieString: String?,
        userID: Int,
        limit: Int,
        offsets: [Int]
    ) async throws -> [(Int, [[String: Any]])] {
        try await withThrowingTaskGroup(of: UserPlaylistPageRows.self) { group in
            for offset in offsets {
                group.addTask {
                    let c = makeConfiguredClient()
                    if let cookieString, !cookieString.isEmpty {
                        c.setCookie(cookieString)
                    }
                    let playlistResponse = try await c.userPlaylist(uid: userID, limit: limit, offset: offset)
                    let batch = playlistResponse.body["playlist"] as? [[String: Any]] ?? []
                    return UserPlaylistPageRows(offset: offset, rows: batch)
                }
            }
            var results: [(Int, [[String: Any]])] = []
            results.reserveCapacity(offsets.count)
            for try await row in group {
                results.append((row.offset, row.rows))
            }
            return results
        }
    }

    private nonisolated static func makeConfiguredClient() -> NCMClient {
        let client = NCMClient()
        let manager = UnblockManager()
        manager.register(ServerUnblockSource.gd())
        client.unblockManager = manager
        client.autoUnblock = true
        return client
    }

    private func parseSong(_ song: [String: Any]) -> Track? {
        guard let id = intFromJSONField(song["id"]),
              let name = song["name"] as? String else {
            return nil
        }
        let artists = song["ar"] as? [[String: Any]] ?? song["artists"] as? [[String: Any]] ?? []
        let artistName = artists.first?["name"] as? String ?? String(localized: String.LocalizationValue("default_unknown_artist"))
        let album = song["al"] as? [String: Any] ?? song["album"] as? [String: Any]
        let albumName = album?["name"] as? String ?? String(localized: String.LocalizationValue("default_unknown_album"))
        return Track(
            id: id,
            title: name,
            artist: artistName,
            album: albumName,
            albumID: album?["id"] as? Int,
            artistID: artists.first?["id"] as? Int,
            coverURL: songCoverURL(from: song, album: album),
            audioURL: ""
        )
    }

    /// 私人 FM、云搜索等接口字段不完全一致：`al` / `album`、顶层 `picUrl` 等。
    private func songCoverURL(from song: [String: Any], album: [String: Any]?) -> String {
        let candidates: [String?] = [
            album?["picUrl"] as? String,
            album?["blurPicUrl"] as? String,
            song["picUrl"] as? String,
            song["coverUrl"] as? String,
            (song["al"] as? [String: Any])?["picUrl"] as? String,
            (song["album"] as? [String: Any])?["picUrl"] as? String
        ]
        for raw in candidates {
            if let raw {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return RemoteURLNormalizer.sanitize(trimmed) }
            }
        }
        return ""
    }

    private func parseArtist(_ artist: [String: Any]) -> ArtistSummary? {
        guard let id = artist["id"] as? Int,
              let name = artist["name"] as? String else {
            return nil
        }

        return ArtistSummary(
            id: id,
            name: name,
            alias: (artist["alias"] as? [String] ?? []).joined(separator: " / "),
            avatarURL: RemoteURLNormalizer.sanitize(artist["img1v1Url"] as? String ?? artist["picUrl"] as? String ?? "")
        )
    }

    private func parseAlbum(_ album: [String: Any]) -> AlbumSummary? {
        guard let id = album["id"] as? Int,
              let name = album["name"] as? String else {
            return nil
        }

        let artistName = ((album["artists"] as? [[String: Any]])?.first?["name"] as? String)
            ?? (album["artist"] as? [String: Any])?["name"] as? String
            ?? String(localized: String.LocalizationValue("default_unknown_artist"))

        return AlbumSummary(
            id: id,
            name: name,
            artist: artistName,
            coverURL: RemoteURLNormalizer.sanitize(album["picUrl"] as? String ?? album["blurPicUrl"] as? String ?? ""),
            trackCount: album["size"] as? Int ?? album["trackCount"] as? Int ?? 0
        )
    }

    private func parsePlaylist(_ playlist: [String: Any]) -> PlaylistSummary? {
        guard let id = playlist["id"] as? Int,
              let name = playlist["name"] as? String else {
            return nil
        }

        let creatorName = (playlist["creator"] as? [String: Any])?["nickname"] as? String ?? String(localized: String.LocalizationValue("default_creator"))

        return PlaylistSummary(
            id: id,
            name: name,
            creatorName: creatorName,
            coverURL: playlistCoverImageURL(from: playlist),
            trackCount: playlist["trackCount"] as? Int ?? 0
        )
    }

    /// Recommend APIs often expose `picUrl`; detail/list responses use `coverImgUrl`.
    private func playlistCoverImageURL(from playlist: [String: Any]) -> String {
        let keys = ["coverImgUrl", "picUrl", "coverUrl", "blurPicUrl"]
        for key in keys {
            if let raw = playlist[key] as? String {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return RemoteURLNormalizer.sanitize(trimmed) }
            }
        }
        return ""
    }

    private func parseLyricLines(from rawLyric: String) -> [LyricLine] {
        rawLyric
            .split(whereSeparator: \.isNewline)
            .compactMap { parseLyricLine(String($0)) }
            .sorted { $0.time < $1.time }
    }

    private func parseLyricLine(_ rawLine: String) -> LyricLine? {
        guard let closingBracket = rawLine.firstIndex(of: "]"),
              rawLine.first == "[" else {
            return nil
        }

        let timestamp = String(rawLine[rawLine.index(after: rawLine.startIndex)..<closingBracket])
        let text = String(rawLine[rawLine.index(after: closingBracket)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let time = parseLyricTimestamp(timestamp), !text.isEmpty else {
            return nil
        }

        return LyricLine(time: time, text: text)
    }

    private func parseLyricTimestamp(_ rawTimestamp: String) -> Double? {
        let parts = rawTimestamp.split(separator: ":")
        guard parts.count == 2,
              let minutes = Double(parts[0]),
              let seconds = Double(parts[1]) else {
            return nil
        }
        return minutes * 60 + seconds
    }
}
