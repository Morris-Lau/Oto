import Foundation
import os

/// Thin `os.Logger` wrapper so app code has one place to configure categories.
/// Use `.public` on non-PII interpolations so values appear in Console; omit it
/// (the Logger default) for anything potentially sensitive (cookies, tokens).
enum OtoLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "app.oto"

    static let audio      = Logger(subsystem: subsystem, category: "audio")
    static let nowPlaying = Logger(subsystem: subsystem, category: "nowPlaying")
    static let cache      = Logger(subsystem: subsystem, category: "cache")
    static let general    = Logger(subsystem: subsystem, category: "general")
}
