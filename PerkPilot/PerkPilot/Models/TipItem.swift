import Foundation
import SwiftData

/// A lesser-known trick, workaround, or strategy note attached to its
/// parent benefit. Tips never appear as checklist rows on their own.
@Model
final class TipItem {
    @Attribute(.unique) var stableId: String
    var text: String
    var sources: [String]

    var benefit: BenefitItem?

    init(stableId: String, text: String, sources: [String] = []) {
        self.stableId = stableId
        self.text = text
        self.sources = sources
    }
}
