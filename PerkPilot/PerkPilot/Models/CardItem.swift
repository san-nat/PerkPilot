import Foundation
import SwiftData

/// A credit card product in the wallet. Mirrors the catalog's CardCatalog +
/// the user's wallet membership (UserCard) in one object for Phase 1 simplicity.
@Model
final class CardItem {
    @Attribute(.unique) var stableId: String
    var canonicalName: String
    var issuer: String
    var annualFeeDisplay: String
    var addedAt: Date
    var isArchived: Bool
    var archivedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \BenefitItem.card)
    var benefits: [BenefitItem]

    init(
        stableId: String,
        canonicalName: String,
        issuer: String,
        annualFeeDisplay: String,
        addedAt: Date = Date(),
        isArchived: Bool = false,
        archivedAt: Date? = nil,
        benefits: [BenefitItem] = []
    ) {
        self.stableId = stableId
        self.canonicalName = canonicalName
        self.issuer = issuer
        self.annualFeeDisplay = annualFeeDisplay
        self.addedAt = addedAt
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.benefits = benefits
    }

    /// Benefits that generate checklist tasks (recurring cadences only).
    var recurringBenefits: [BenefitItem] {
        benefits.filter { $0.cadence?.isRecurring == true }
    }
}
