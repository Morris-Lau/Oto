import Foundation
import Observation

private struct PendingDownloadTaskInfo {
    let track: Track
    let downloadDirectory: URL
    let documentsDirectory: URL
}

private final class DownloadTaskMetadataStore: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int: PendingDownloadTaskInfo] = [:]

    func set(_ info: PendingDownloadTaskInfo, taskIdentifier: Int) {
        lock.lock()
        storage[taskIdentifier] = info
        lock.unlock()
    }

    func remove(taskIdentifier: Int) -> PendingDownloadTaskInfo? {
        lock.lock()
        defer { lock.unlock() }
        return storage.removeValue(forKey: taskIdentifier)
    }
}

@MainActor
@Observable
final class DownloadService {
    static let shared = DownloadService()

    private struct DownloadRecord: Codable {
        let track: Track
        /// Path under the app Documents directory, e.g. `OtoDownloads/Artist - Title [123].mp3`.
        let relativePath: String
        let downloadedAt: Date

        enum CodingKeys: String, CodingKey {
            case track, downloadedAt, relativePath
            case localFilePath
        }

        init(track: Track, relativePath: String, downloadedAt: Date) {
            self.track = track
            self.relativePath = relativePath
            self.downloadedAt = downloadedAt
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            track = try c.decode(Track.self, forKey: .track)
            downloadedAt = try c.decode(Date.self, forKey: .downloadedAt)
            if let rel = try c.decodeIfPresent(String.self, forKey: .relativePath) {
                relativePath = rel
            } else if let legacy = try c.decodeIfPresent(String.self, forKey: .localFilePath) {
                relativePath = Self.migrateLegacyLocalFilePath(legacy)
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .localFilePath,
                    in: c,
                    debugDescription: "Missing file path"
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(track, forKey: .track)
            try c.encode(downloadedAt, forKey: .downloadedAt)
            try c.encode(relativePath, forKey: .relativePath)
        }

        private static func migrateLegacyLocalFilePath(_ legacy: String) -> String {
            if let range = legacy.range(of: "/OtoDownloads/") {
                return "OtoDownloads/\(legacy[range.upperBound...])"
            }
            let name = (legacy as NSString).lastPathComponent
            return "OtoDownloads/\(name)"
        }
    }

    private enum StorageKeys {
        static let catalog = "storymusic.downloads.catalog"
    }

    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    fileprivate let taskMetadata = DownloadTaskMetadataStore()
    private let downloadDelegate: DownloadSessionDelegate
    private let downloadSession: URLSession

    private let documentsDirectory: URL
    private let applicationSupportDirectory: URL
    private let downloadDirectory: URL

    private var downloadsByID: [Int: DownloadRecord] = [:]
    private var inFlightDownloads: Set<Int> = []

    /// Fraction0...1 while downloading when total size is known; `nil` means indeterminate or not started yet.
    private(set) var downloadFractionByTrackID: [Int: Double] = [:]

    private var taskIdentifierToTrackID: [Int: Int] = [:]
    private var pendingContinuations: [Int: CheckedContinuation<Result<Void, Error>, Never>] = [:]
    private var filePreparationErrors: [Int: Error] = [:]

    var downloadedTracks: [Track] = []
    var isLoading: Bool {
        !inFlightDownloads.isEmpty
    }

    init(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        documentsDirectory: URL? = nil,
        applicationSupportDirectory: URL? = nil
    ) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
        let delegate = DownloadSessionDelegate()
        downloadDelegate = delegate
        let documents = documentsDirectory ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.documentsDirectory = documents
        self.applicationSupportDirectory =
            applicationSupportDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? documents
        downloadDirectory = documents.appendingPathComponent("OtoDownloads", isDirectory: true)
        let config = URLSessionConfiguration.default
        downloadSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        try? fileManager.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        delegate.owner = self
        restoreFromPersistence()
    }

    func isDownloaded(trackID: Int) -> Bool {
        guard let record = downloadsByID[trackID] else { return false }
        let url = documentsDirectory.appendingPathComponent(record.relativePath)
        return fileManager.fileExists(atPath: url.path)
    }

    func isDownloading(trackID: Int) -> Bool {
        inFlightDownloads.contains(trackID)
    }

    func downloadFraction(for trackID: Int) -> Double? {
        downloadFractionByTrackID[trackID]
    }

    func localFileURL(for trackID: Int) async -> URL? {
        guard let record = downloadsByID[trackID] else { return nil }
        let url = documentsDirectory.appendingPathComponent(record.relativePath)

        guard fileManager.fileExists(atPath: url.path) else {
            downloadsByID[trackID] = nil
            downloadedTracks = sortedTracks(from: downloadsByID)
            persist()
            return nil
        }

        return url
    }

    func downloadIfNeeded(_ track: Track) async -> Result<Void, Error> {
        if isDownloaded(trackID: track.id) {
            return .success(())
        }

        guard !inFlightDownloads.contains(track.id) else {
            return .success(())
        }

        let source: URL
        do {
            source = try await resolveRemoteURL(for: track)
        } catch {
            return .failure(error)
        }

        return await withCheckedContinuation { continuation in
            let task = downloadSession.downloadTask(with: source)
            let taskIdentifier = task.taskIdentifier

            taskMetadata.set(
                PendingDownloadTaskInfo(
                    track: track,
                    downloadDirectory: downloadDirectory,
                    documentsDirectory: documentsDirectory
                ),
                taskIdentifier: taskIdentifier
            )
            taskIdentifierToTrackID[taskIdentifier] = track.id
            pendingContinuations[track.id] = continuation
            downloadFractionByTrackID[track.id] = 0
            inFlightDownloads.insert(track.id)
            task.resume()
        }
    }

    func removeDownload(for trackID: Int) {
        guard let record = downloadsByID[trackID] else { return }

        let fileURL = documentsDirectory.appendingPathComponent(record.relativePath)
        try? fileManager.removeItem(at: fileURL)
        downloadsByID[trackID] = nil
        downloadedTracks = sortedTracks(from: downloadsByID)
        persist()
    }

    // MARK: - Session delegate callbacks (MainActor)

    fileprivate func handleDownloadProgress(
        taskIdentifier: Int,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let trackID = taskIdentifierToTrackID[taskIdentifier] else { return }
        if totalBytesExpectedToWrite > 0 {
            let fraction = min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
            downloadFractionByTrackID[trackID] = fraction
        } else {
            downloadFractionByTrackID.removeValue(forKey: trackID)
        }
    }

    /// Called from delegate after the temp file is moved into place on disk.
    fileprivate func commitFinishedDownload(track: Track, relativePath: String) {
        let record = DownloadRecord(
            track: track,
            relativePath: relativePath,
            downloadedAt: Date()
        )
        downloadsByID[track.id] = record
        downloadedTracks = sortedTracks(from: downloadsByID)
        persist()
    }

    fileprivate func noteFilePreparationFailed(trackID: Int, error: Error) {
        filePreparationErrors[trackID] = error
    }

    fileprivate func completeDownloadTask(taskIdentifier: Int, urlSessionError: Error?) {
        guard let trackID = taskIdentifierToTrackID.removeValue(forKey: taskIdentifier) else { return }

        inFlightDownloads.remove(trackID)
        downloadFractionByTrackID.removeValue(forKey: trackID)

        let fileError = filePreparationErrors.removeValue(forKey: trackID)
        let resolvedError = urlSessionError ?? fileError

        guard let cont = pendingContinuations.removeValue(forKey: trackID) else { return }
        if let resolvedError {
            cont.resume(returning: .failure(resolvedError))
        } else {
            cont.resume(returning: .success(()))
        }
    }

    private func sortedTracks(from items: [Int: DownloadRecord]) -> [Track] {
        items.values
            .sorted { $0.downloadedAt > $1.downloadedAt }
            .map(\.track)
    }

    private func resolveRemoteURL(for track: Track) async throws -> URL {
        let audioURLString: String
        if !track.audioURL.isEmpty {
            audioURLString = track.audioURL.replacingOccurrences(of: "http://", with: "https://")
        } else {
            audioURLString = try await NetEaseService.shared.fetchAudioURL(for: track.id)
        }

        guard let remote = URL(string: audioURLString), !audioURLString.isEmpty else {
            throw DownloadServiceError.invalidAudioURL
        }

        return remote
    }

    /// Renames legacy `12345.ext` files to `Artist - Title [12345].ext` when restoring.
    private func relativePathForRestoredDocumentFile(track: Track, fileURL: URL) -> (relativePath: String, renamed: Bool) {
        let stem = fileURL.deletingPathExtension().lastPathComponent
        guard stem == String(track.id) else {
            return (relativePathUnderDocuments(fileURL: fileURL), false)
        }
        let ext = fileURL.pathExtension
        let newStem = downloadFileStem(for: track)
        let destination = downloadDirectory.appendingPathComponent("\(newStem).\(ext)")
        if destination.standardizedFileURL == fileURL.standardizedFileURL {
            return (relativePathUnderDocuments(fileURL: fileURL), false)
        }
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: fileURL, to: destination)
            return (relativePathUnderDocuments(fileURL: destination), true)
        } catch {
            return (relativePathUnderDocuments(fileURL: fileURL), false)
        }
    }

    private func restoreFromPersistence() {
        guard let data = userDefaults.data(forKey: StorageKeys.catalog) else {
            downloadedTracks = []
            return
        }

        guard let decoded = try? JSONDecoder().decode([DownloadRecord].self, from: data) else {
            downloadedTracks = []
            return
        }

        var migrated = false
        var validRecords: [Int: DownloadRecord] = [:]

        for record in decoded {
            guard let resolvedURL = resolveStoredFileURL(for: record) else { continue }
            if resolvedURL.path.hasPrefix(documentsDirectory.path) {
                let (relPath, renamed) = relativePathForRestoredDocumentFile(
                    track: record.track,
                    fileURL: resolvedURL
                )
                if renamed { migrated = true }
                validRecords[record.track.id] = DownloadRecord(
                    track: record.track,
                    relativePath: relPath,
                    downloadedAt: record.downloadedAt
                )
            } else if let moved = migrateFromLegacyLocation(record: record, sourceURL: resolvedURL) {
                validRecords[record.track.id] = moved
                migrated = true
            }
        }

        downloadsByID = validRecords
        downloadedTracks = sortedTracks(from: downloadsByID)
        if migrated { persist() }
    }

    private func resolveStoredFileURL(for record: DownloadRecord) -> URL? {
        let primary = documentsDirectory.appendingPathComponent(record.relativePath)
        if fileManager.fileExists(atPath: primary.path) { return primary }
        let fileName = URL(fileURLWithPath: record.relativePath).lastPathComponent
        let legacy = applicationSupportDirectory.appendingPathComponent("OtoDownloads").appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: legacy.path) {
            return legacy
        }
        return nil
    }

    private func relativePathUnderDocuments(fileURL: URL) -> String {
        let docPath = documentsDirectory.standardizedFileURL.path
        let path = fileURL.standardizedFileURL.path
        guard path.hasPrefix(docPath) else {
            return "OtoDownloads/\(fileURL.lastPathComponent)"
        }
        var remainder = String(path.dropFirst(docPath.count))
        if remainder.hasPrefix("/") { remainder.removeFirst() }
        return remainder
    }

    private func migrateFromLegacyLocation(record: DownloadRecord, sourceURL: URL) -> DownloadRecord? {
        try? fileManager.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        let dest = downloadDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        do {
            if fileManager.fileExists(atPath: dest.path) {
                try fileManager.removeItem(at: dest)
            }
            try fileManager.moveItem(at: sourceURL, to: dest)
            let (rel, _) = relativePathForRestoredDocumentFile(track: record.track, fileURL: dest)
            return DownloadRecord(track: record.track, relativePath: rel, downloadedAt: record.downloadedAt)
        } catch {
            return nil
        }
    }

    private func persist() {
        let orderedRecords = sortedTracks(from: downloadsByID).compactMap { track in
            downloadsByID[track.id]
        }

        if let data = try? JSONEncoder().encode(orderedRecords) {
            userDefaults.set(data, forKey: StorageKeys.catalog)
        }
    }
}

// MARK: - URLSession delegate

private nonisolated func downloadFileStem(for track: Track) -> String {
    let artist = sanitizeFilenameFragment(track.artist)
    let title = sanitizeFilenameFragment(track.title)
    let core: String
    if artist.isEmpty && title.isEmpty {
        core = "Track \(track.id)"
    } else if artist.isEmpty {
        core = title
    } else if title.isEmpty {
        core = artist
    } else {
        core = "\(artist) - \(title)"
    }
    let idSuffix = " [\(track.id)]"
    let combined = core + idSuffix
    let maxChars = 180
    if combined.count <= maxChars { return combined }
    let budget = max(1, maxChars - idSuffix.count)
    var trimmed = String(core.prefix(budget)).trimmingCharacters(in: .whitespacesAndNewlines)
    while trimmed.hasSuffix("-") || trimmed.hasSuffix("–") {
        trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if trimmed.isEmpty { return "Track \(track.id)\(idSuffix)" }
    return trimmed + idSuffix
}

private nonisolated func sanitizeFilenameFragment(_ raw: String) -> String {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let illegal = CharacterSet(charactersIn: "/:\\?%*|\"<>\u{0000}")
    s = s.components(separatedBy: illegal).joined(separator: " ")
    s = s.replacingOccurrences(of: "\n", with: " ")
    s = s.replacingOccurrences(of: "\r", with: " ")
    while s.contains("  ") {
        s = s.replacingOccurrences(of: "  ", with: " ")
    }
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

private nonisolated func removeExistingDownloadsForTrack(
    trackID: Int,
    in downloadDirectory: URL,
    fileManager: FileManager
) {
    guard let fileURLs = try? fileManager.contentsOfDirectory(at: downloadDirectory, includingPropertiesForKeys: nil) else {
        return
    }
    let idBracketSuffix = " [\(trackID)]"
    let legacyNumericStem = String(trackID)
    for fileURL in fileURLs {
        let stem = fileURL.deletingPathExtension().lastPathComponent
        if stem == legacyNumericStem || stem.hasSuffix(idBracketSuffix) {
            try? fileManager.removeItem(at: fileURL)
        }
    }
}

private nonisolated func moveDownloadIntoPlace(
    tempURL: URL,
    track: Track,
    downloadDirectory: URL,
    documentsDirectory: URL,
    response: URLResponse?,
    fileManager: FileManager
) throws -> String {
    let fileExtension = preferredFileExtensionNonisolated(from: response, fallbackURL: tempURL)
    removeExistingDownloadsForTrack(trackID: track.id, in: downloadDirectory, fileManager: fileManager)
    let stem = downloadFileStem(for: track)
    let destination = downloadDirectory.appendingPathComponent("\(stem).\(fileExtension)")

    try fileManager.moveItem(at: tempURL, to: destination)
    return relativePathUnderDocumentsNonisolated(documentsDirectory: documentsDirectory, fileURL: destination)
}

private nonisolated func relativePathUnderDocumentsNonisolated(documentsDirectory: URL, fileURL: URL) -> String {
    let docPath = documentsDirectory.standardizedFileURL.path
    let path = fileURL.standardizedFileURL.path
    guard path.hasPrefix(docPath) else {
        return "OtoDownloads/\(fileURL.lastPathComponent)"
    }
    var remainder = String(path.dropFirst(docPath.count))
    if remainder.hasPrefix("/") { remainder.removeFirst() }
    return remainder
}

private nonisolated func preferredFileExtensionNonisolated(from response: URLResponse?, fallbackURL: URL) -> String {
    if let suggestedExtension = response?.suggestedFilename?
        .split(separator: ".")
        .last?
        .lowercased(),
       !suggestedExtension.isEmpty {
        return String(suggestedExtension)
    }

    let responsePathExtension = response?.url?.pathExtension.lowercased() ?? ""
    if !responsePathExtension.isEmpty {
        return responsePathExtension
    }

    let fallbackPathExtension = fallbackURL.pathExtension.lowercased()
    if !fallbackPathExtension.isEmpty {
        return fallbackPathExtension
    }

    return "mp3"
}

private final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var owner: DownloadService?

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let owner else { return }
        let taskIdentifier = downloadTask.taskIdentifier
        Task { @MainActor in
            owner.handleDownloadProgress(
                taskIdentifier: taskIdentifier,
                totalBytesWritten: totalBytesWritten,
                totalBytesExpectedToWrite: totalBytesExpectedToWrite
            )
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let owner else { return }
        let taskIdentifier = downloadTask.taskIdentifier
        let response = downloadTask.response

        guard let info = owner.taskMetadata.remove(taskIdentifier: taskIdentifier) else {
            return
        }

        // The temp `location` URL is only valid until this delegate method returns; move synchronously.
        let relativePath: String
        do {
            relativePath = try moveDownloadIntoPlace(
                tempURL: location,
                track: info.track,
                downloadDirectory: info.downloadDirectory,
                documentsDirectory: info.documentsDirectory,
                response: response,
                fileManager: .default
            )
        } catch {
            Task { @MainActor in
                owner.noteFilePreparationFailed(trackID: info.track.id, error: error)
                owner.completeDownloadTask(taskIdentifier: taskIdentifier, urlSessionError: error)
            }
            return
        }

        let fileURL = info.documentsDirectory.appendingPathComponent(relativePath)
        Task {
            await OfflineAudioMetadataWriter.embedIfAppropriate(fileURL: fileURL, track: info.track)
            await MainActor.run {
                owner.commitFinishedDownload(track: info.track, relativePath: relativePath)
                owner.completeDownloadTask(taskIdentifier: taskIdentifier, urlSessionError: nil)
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let owner, let error else { return }
        let taskIdentifier = task.taskIdentifier
        Task { @MainActor in
            owner.completeDownloadTask(taskIdentifier: taskIdentifier, urlSessionError: error)
        }
    }
}

enum DownloadServiceError: Error {
    case invalidAudioURL
}
