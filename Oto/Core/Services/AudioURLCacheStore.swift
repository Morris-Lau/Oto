import Foundation

/// L2：播放直链磁盘缓存（与 `NetEaseService` 内存 L1、接口 L3 组成三级缓存）。
/// 按曲目分文件写入，避免单次读写巨大 JSON；cookie 指纹不一致时整目录作废。
enum AudioURLCacheStore {
    struct Entry: Sendable {
        let url: String
        let type: String?
    }

    private static let rootFolderName = "audio-url-cache-v2"
    private static let fingerprintFileName = "session-fingerprint.txt"
    private static let tracksFolderName = "tracks"

    private static var rootDirectory: URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Oto: application-support directory unavailable — AudioURLCacheStore")
        }
        return base.appendingPathComponent("Oto", isDirectory: true).appendingPathComponent(rootFolderName, isDirectory: true)
    }

    private static var fingerprintURL: URL {
        rootDirectory.appendingPathComponent(fingerprintFileName)
    }

    private static var tracksDirectory: URL {
        rootDirectory.appendingPathComponent(tracksFolderName, isDirectory: true)
    }

    private static func trackFileURL(trackId: Int) -> URL {
        tracksDirectory.appendingPathComponent("\(trackId).json")
    }

    private struct Row: Codable {
        let url: String
        let type: String?
        let expiresAt: TimeInterval
    }

    /// 与内存侧一致：空字符串表示未登录或无 cookie 快照。
    private static func normalizedFingerprint(_ fingerprint: String?) -> String {
        fingerprint ?? ""
    }

    private static func ensureLayout(fingerprint: String?) {
        try? FileManager.default.createDirectory(at: tracksDirectory, withIntermediateDirectories: true)
        let fp = normalizedFingerprint(fingerprint)
        let data = Data(fp.utf8)
        if (try? Data(contentsOf: fingerprintURL)) != data {
            try? data.write(to: fingerprintURL, options: [.atomic])
        }
    }

    static func read(trackId: Int, fingerprint: String?) -> (url: String, type: String?, expiresAt: Date)? {
        let expected = normalizedFingerprint(fingerprint)
        guard let onDisk = try? String(contentsOf: fingerprintURL, encoding: .utf8), onDisk == expected else {
            return nil
        }
        let url = trackFileURL(trackId: trackId)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let row = try? JSONDecoder().decode(Row.self, from: data) else {
            return nil
        }
        let expiresAt = Date(timeIntervalSince1970: row.expiresAt)
        guard expiresAt > Date() else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return (row.url, row.type, expiresAt)
    }

    static func writeBatch(trackIdsAndInfo: [Int: Entry], expiresAt: Date, fingerprint: String?) {
        guard !trackIdsAndInfo.isEmpty else { return }
        ensureLayout(fingerprint: fingerprint)
        let exp = expiresAt.timeIntervalSince1970
        let encoder = JSONEncoder()
        for (id, info) in trackIdsAndInfo {
            let row = Row(url: info.url, type: info.type, expiresAt: exp)
            guard let data = try? encoder.encode(row) else { continue }
            try? data.write(to: trackFileURL(trackId: id), options: [.atomic])
        }
    }

    static func clearAll() {
        if FileManager.default.fileExists(atPath: rootDirectory.path) {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
    }
}
