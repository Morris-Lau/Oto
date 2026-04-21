import Foundation

extension Array where Element == LyricLine {
    /// Matches `NowPlayingLyricsPanel` logic: before the first timestamp, the current line is the first line.
    func lyricContext(at time: Double) -> (previous: String, current: String, next: String) {
        guard !isEmpty else { return ("", "", "") }
        if let idx = lastIndex(where: { $0.time <= time }) {
            let previous = idx > startIndex ? self[index(before: idx)].text : ""
            let current = self[idx].text
            let next = index(after: idx) < endIndex ? self[index(after: idx)].text : ""
            return (previous, current, next)
        }
        let current = self[0].text
        let next = count > 1 ? self[1].text : ""
        return ("", current, next)
    }

    func focusedLyricIndex(at time: Double) -> Int {
        guard !isEmpty else { return 0 }
        if let idx = lastIndex(where: { $0.time <= time }) {
            return idx
        }
        return 0
    }
}
