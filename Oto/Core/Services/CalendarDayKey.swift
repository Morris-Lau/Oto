import Foundation

/// Shared local-calendar day stamp (`yyyy-MM-dd`) for daily cache invalidation and foreground refresh gating.
enum CalendarDayKey {
    static func string(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day else { return "" }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}
