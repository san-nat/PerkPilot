import Foundation

/// Recurrence cadence for a benefit, matching the seed catalog vocabulary.
enum Cadence: String, Codable, CaseIterable, Sendable {
    case monthly
    case quarterly
    case semiannual = "semi-annual"
    case annual
    case oneTime = "one-time"
    case perUse = "per-use"

    /// Whether this cadence generates checklist tasks (vs. library-only perks).
    var isRecurring: Bool {
        switch self {
        case .monthly, .quarterly, .semiannual, .annual: return true
        case .oneTime, .perUse: return false
        }
    }

    var displayName: String {
        switch self {
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .semiannual: return "Semi-annual"
        case .annual: return "Annual"
        case .oneTime: return "One-time"
        case .perUse: return "Per use"
        }
    }
}
