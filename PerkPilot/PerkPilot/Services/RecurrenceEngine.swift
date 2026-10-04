import Foundation

/// Pure calendar math for checklist periods. Period keys are stable strings:
/// monthly "2026-10", quarterly "2026-Q4", semi-annual "2026-H2", annual "2026".
/// One-time and per-use benefits never generate tasks.
enum RecurrenceEngine {

    /// The period key for a cadence on a date, or nil for non-recurring cadences.
    static func periodKey(cadence: Cadence, date: Date, calendar: Calendar = .current) -> String? {
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard let year = comps.year, let month = comps.month else { return nil }
        switch cadence {
        case .monthly:
            return String(format: "%04d-%02d", year, month)
        case .quarterly:
            return "\(year)-Q\((month - 1) / 3 + 1)"
        case .semiannual:
            return "\(year)-H\(month <= 6 ? 1 : 2)"
        case .annual:
            return "\(year)"
        case .oneTime, .perUse:
            return nil
        }
    }

    /// Human label for the current period, e.g. "October 2026", "Q4 2026".
    static func periodLabel(cadence: Cadence, date: Date, calendar: Calendar = .current) -> String? {
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard let year = comps.year, let month = comps.month else { return nil }
        let monthName = calendar.monthSymbols[month - 1]
        switch cadence {
        case .monthly:
            return "\(monthName) \(year)"
        case .quarterly:
            return "Q\((month - 1) / 3 + 1) \(year)"
        case .semiannual:
            return "H\(month <= 6 ? 1 : 2) \(year)"
        case .annual:
            return "\(year)"
        case .oneTime, .perUse:
            return nil
        }
    }

    /// The start/end dates of the period containing `date`.
    static func periodRange(
        cadence: Cadence,
        date: Date,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date)? {
        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        switch cadence {
        case .monthly:
            comps.day = 1
        case .quarterly:
            comps.month = ((comps.month! - 1) / 3) * 3 + 1
            comps.day = 1
        case .semiannual:
            comps.month = comps.month! <= 6 ? 1 : 7
            comps.day = 1
        case .annual:
            comps.month = 1
            comps.day = 1
        case .oneTime, .perUse:
            return nil
        }
        guard let start = calendar.date(from: comps) else { return nil }
        let add: DateComponents
        switch cadence {
        case .monthly: add = DateComponents(month: 1)
        case .quarterly: add = DateComponents(month: 3)
        case .semiannual: add = DateComponents(month: 6)
        case .annual: add = DateComponents(year: 1)
        case .oneTime, .perUse: return nil
        }
        guard let end = calendar.date(byAdding: add, to: start) else { return nil }
        return (start, end)
    }
}
