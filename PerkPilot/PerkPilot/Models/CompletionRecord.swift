import Foundation
import SwiftData

/// One durable checkmark: a benefit marked used for a given period.
/// Uniqueness is (benefitStableId, periodKey).
@Model
final class CompletionRecord {
    var benefitStableId: String
    var periodKey: String
    var completedAt: Date

    init(benefitStableId: String, periodKey: String, completedAt: Date = Date()) {
        self.benefitStableId = benefitStableId
        self.periodKey = periodKey
        self.completedAt = completedAt
    }

    /// Lookup key used by the checklist UI.
    var lookupKey: String { "\(benefitStableId)|\(periodKey)" }
}
