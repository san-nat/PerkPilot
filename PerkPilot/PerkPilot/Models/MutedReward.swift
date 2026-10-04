import Foundation
import SwiftData

/// Why the user muted a reward.
enum MuteReason: String, Codable, CaseIterable, Sendable {
    case noMonetaryValue
    case notInterested
    case notValuable
    case other

    var displayName: String {
        switch self {
        case .noMonetaryValue: return "No monetary value"
        case .notInterested: return "Not interested"
        case .notValuable: return "Not valuable to me"
        case .other: return "Other"
        }
    }
}

/// A muted reward: excluded from checklists but kept in the library.
/// Muting never deletes the benefit or its history.
@Model
final class MutedReward {
    @Attribute(.unique) var benefitStableId: String
    var reasonRaw: String
    var note: String
    var mutedAt: Date

    init(benefitStableId: String, reason: MuteReason, note: String = "", mutedAt: Date = Date()) {
        self.benefitStableId = benefitStableId
        self.reasonRaw = reason.rawValue
        self.note = note
        self.mutedAt = mutedAt
    }

    var reason: MuteReason { MuteReason(rawValue: reasonRaw) ?? .other }
}
