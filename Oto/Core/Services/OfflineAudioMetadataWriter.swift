import Foundation
import UIKit

// MARK: - ID3v2.3 (MP3)

enum MP3ID3TagEmbedder {
    /// Prepends a new ID3v2.3 tag (title, artist, album, cover) and strips any existing leading ID3 tag.
    static func embed(audio data: Data, title: String, artist: String, album: String, coverJPEG: Data) -> Data {
        let audioOnly = stripLeadingID3Tag(from: data)
        var frames = Data()
        if !title.isEmpty { frames.append(makeTextFrame(id: "TIT2", text: title)) }
        if !artist.isEmpty { frames.append(makeTextFrame(id: "TPE1", text: artist)) }
        if !album.isEmpty { frames.append(makeTextFrame(id: "TALB", text: album)) }
        frames.append(makeAPICFrame(jpegData: coverJPEG))

        let tagSize = UInt32(frames.count)
        var tag = Data([0x49, 0x44, 0x33, 3, 0, 0])
        tag.append(synchsafe4(tagSize))
        tag.append(frames)
        return tag + audioOnly
    }

    private static func synchsafe4(_ value: UInt32) -> Data {
        Data([
            UInt8((value >> 21) & 0x7F),
            UInt8((value >> 14) & 0x7F),
            UInt8((value >> 7) & 0x7F),
            UInt8(value & 0x7F),
        ])
    }

    private static func stripLeadingID3Tag(from data: Data) -> Data {
        guard data.count >= 10 else { return data }
        guard data[0] == 0x49, data[1] == 0x44, data[2] == 0x33 else { return data }
        let version = data[3]
        guard version == 3 || version == 4 else { return data }
        let size = unsynchsafe(bytes: [data[6], data[7], data[8], data[9]])
        let total = 10 + Int(size)
        guard total <= data.count, total >= 10 else { return data }
        return data.subdata(in: total..<data.count)
    }

    private static func unsynchsafe(bytes: [UInt8]) -> UInt32 {
        guard bytes.count == 4 else { return 0 }
        return (UInt32(bytes[0]) << 21) | (UInt32(bytes[1]) << 14) | (UInt32(bytes[2]) << 7) | UInt32(bytes[3])
    }

    /// ID3v2.3 text frame; encoding 1 = UTF-16 with BOM.
    private static func makeTextFrame(id: String, text: String) -> Data {
        var content = Data()
        content.append(1)
        content.append(0xFF)
        content.append(0xFE)
        for unit in text.utf16 {
            content.append(UInt8(truncatingIfNeeded: unit))
            content.append(UInt8(truncatingIfNeeded: unit >> 8))
        }
        content.append(0)
        content.append(0)

        var frame = Data()
        frame.append(contentsOf: id.utf8)
        appendBigEndianUInt32(&frame, UInt32(content.count))
        frame.append(contentsOf: [0x00, 0x00])
        frame.append(content)
        return frame
    }

    private static func makeAPICFrame(jpegData: Data) -> Data {
        var content = Data()
        content.append(0)
        content.append(contentsOf: "image/jpeg".utf8)
        content.append(0)
        content.append(3)
        content.append(0)
        content.append(jpegData)

        var frame = Data()
        frame.append(contentsOf: "APIC".utf8)
        appendBigEndianUInt32(&frame, UInt32(content.count))
        frame.append(contentsOf: [0x00, 0x00])
        frame.append(content)
        return frame
    }

    private static func appendBigEndianUInt32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }
}

// MARK: - After download

enum OfflineAudioMetadataWriter {
    /// Embeds ID3 tag with cover for `.mp3` files so system apps (Files, Music) can show artwork.
    static func embedIfAppropriate(fileURL: URL, track: Track) async {
        guard fileURL.pathExtension.lowercased() == "mp3" else { return }
        guard let jpeg = await fetchCoverJPEG(from: track.coverURL) else { return }
        do {
            let raw = try Data(contentsOf: fileURL)
            let tagged = MP3ID3TagEmbedder.embed(
                audio: raw,
                title: track.title,
                artist: track.artist,
                album: track.album,
                coverJPEG: jpeg
            )
            try tagged.write(to: fileURL, options: .atomic)
        } catch {}
    }

    private static func fetchCoverJPEG(from urlString: String) async -> Data? {
        let normalized = urlString.replacingOccurrences(of: "http://", with: "https://")
        guard let url = URL(string: normalized), !normalized.isEmpty else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return nil }
            return image.jpegData(compressionQuality: 0.85)
        } catch {
            return nil
        }
    }
}
