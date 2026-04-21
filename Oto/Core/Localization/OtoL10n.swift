import Foundation

/// Formatted / non-view strings. SwiftUI views can use `Text("catalog_key")` for simple keys.
enum OtoL10n {
    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let format = String(localized: String.LocalizationValue(key))
        if arguments.isEmpty {
            return format
        }
        return String(format: format, locale: .current, arguments: arguments)
    }
}
