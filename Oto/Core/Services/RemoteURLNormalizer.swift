import Foundation

enum RemoteURLNormalizer {
    static func sanitize(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("//") {
            return "https:" + trimmed
        }
        return trimmed.replacingOccurrences(of: "http://", with: "https://", options: .caseInsensitive)
    }

    static func sanitize(_ value: String?) -> String {
        sanitize(value ?? "")
    }

    static func canonicalURL(_ url: URL) -> URL {
        var normalized = url
        if normalized.scheme == nil, normalized.host != nil {
            var components = URLComponents(url: normalized, resolvingAgainstBaseURL: false)
            components?.scheme = "https"
            if let resolved = components?.url {
                normalized = resolved
            }
        }
        if normalized.scheme?.caseInsensitiveCompare("http") == .orderedSame {
            var components = URLComponents(url: normalized, resolvingAgainstBaseURL: false)
            components?.scheme = "https"
            normalized = components?.url ?? normalized
        }
        return normalized
    }

    static func url(from value: String) -> URL? {
        let sanitized = sanitize(value)
        guard !sanitized.isEmpty, let url = URL(string: sanitized) else { return nil }
        return canonicalURL(url)
    }
}
