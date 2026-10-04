import Foundation
import SwiftData

/// A single benefit/credit belonging to a card. Stable identity across
/// catalog revisions; dated terms live in future BenefitVersion records
/// (Phase 2). Tips are nested here, never standalone benefits.
@Model
final class BenefitItem {
    @Attribute(.unique) var stableId: String
    var name: String
    var cadenceRaw: String
    var amountDisplay: String
    var howToUse: String
    var enrollmentRequired: Bool
    var lesserKnown: Bool
    var sources: [String]

    var card: CardItem?

    @Relationship(deleteRule: .cascade, inverse: \TipItem.benefit)
    var tips: [TipItem]

    init(
        stableId: String,
        name: String,
        cadenceRaw: String,
        amountDisplay: String,
        howToUse: String,
        enrollmentRequired: Bool,
        lesserKnown: Bool,
        sources: [String] = [],
        tips: [TipItem] = []
    ) {
        self.stableId = stableId
        self.name = name
        self.cadenceRaw = cadenceRaw
        self.amountDisplay = amountDisplay
        self.howToUse = howToUse
        self.enrollmentRequired = enrollmentRequired
        self.lesserKnown = lesserKnown
        self.sources = sources
        self.tips = tips
    }

    var cadence: Cadence? { Cadence(rawValue: cadenceRaw) }
}
