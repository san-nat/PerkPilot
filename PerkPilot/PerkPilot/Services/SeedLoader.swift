import Foundation
import SwiftData

// MARK: - Seed DTOs (mirror SeedData.json)

struct SeedTip: Decodable {
    var stableId: String
    var text: String
    var sources: [String]
}

struct SeedBenefit: Decodable {
    var stableId: String
    var name: String
    var cadence: String
    var amountDisplay: String
    var howToUse: String
    var enrollmentRequired: Bool
    var lesserKnown: Bool
    var sources: [String]
    var tips: [SeedTip]
}

struct SeedCard: Decodable {
    var stableId: String
    var canonicalName: String
    var issuer: String
    var annualFeeDisplay: String
    var benefits: [SeedBenefit]
}

struct SeedManifest: Decodable {
    var catalogVersion: String
    var schemaVersion: Int
    var locale: String
    var exportedAt: String
    var cardCount: Int
    var benefitCount: Int
    var checksum: String
    var cards: [SeedCard]
}

// MARK: - Loader

/// Imports the bundled SeedData.json into SwiftData. Idempotent: re-importing
/// the same catalog version writes nothing new, and it never touches user
/// state (checkmarks, mutes, archives, reminders).
enum SeedLoader {
    private static let versionKey = "perkPilot.seedCatalogVersion"

    static var lastImportedVersion: String? {
        UserDefaults.standard.string(forKey: versionKey)
    }

    /// Loads the bundled manifest, throwing on any contract violation.
    static func loadManifest() throws -> SeedManifest {
        guard let url = Bundle.main.url(forResource: "SeedData", withExtension: "json") else {
            throw SeedError.missingBundle
        }
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(SeedManifest.self, from: data)
        try validate(manifest)
        return manifest
    }

    /// Contract checks: counts, stable-ID uniqueness, cadence vocabulary,
    /// and the provenance rule (every benefit carries at least one source).
    static func validate(_ manifest: SeedManifest) throws {
        guard manifest.cards.count == manifest.cardCount else { throw SeedError.countMismatch("cards") }
        let benefits = manifest.cards.flatMap(\.benefits)
        guard benefits.count == manifest.benefitCount else { throw SeedError.countMismatch("benefits") }

        var seen = Set<String>()
        for card in manifest.cards {
            guard seen.insert(card.stableId).inserted else { throw SeedError.duplicateId(card.stableId) }
            for b in card.benefits {
                guard seen.insert(b.stableId).inserted else { throw SeedError.duplicateId(b.stableId) }
                guard Cadence(rawValue: b.cadence) != nil else { throw SeedError.unknownCadence(b.cadence) }
                guard !b.sources.isEmpty else { throw SeedError.missingSource(b.stableId) }
                for t in b.tips {
                    guard seen.insert(t.stableId).inserted else { throw SeedError.duplicateId(t.stableId) }
                    guard !t.text.isEmpty else { throw SeedError.emptyTip(t.stableId) }
                }
            }
        }
    }

    /// Imports on first launch (or when the bundled catalog version changes).
    /// Pass `force: true` from Settings to re-run validation + upsert.
    static func importIfNeeded(_ context: ModelContext, force: Bool = false) throws {
        let manifest = try loadManifest()
        guard force || lastImportedVersion != manifest.catalogVersion else { return }
        try upsert(manifest, into: context)
        try context.save()
        UserDefaults.standard.set(manifest.catalogVersion, forKey: versionKey)
    }

    private static func upsert(_ manifest: SeedManifest, into context: ModelContext) throws {
        for seed in manifest.cards {
            let card = try fetchOrCreateCard(seed, in: context)
            for sb in seed.benefits {
                let benefit = fetchOrCreateBenefit(sb, on: card, in: context)
                for st in sb.tips where !benefit.tips.contains(where: { $0.stableId == st.stableId }) {
                    benefit.tips.append(TipItem(stableId: st.stableId, text: st.text, sources: st.sources))
                }
            }
        }
    }

    private static func fetchOrCreateCard(_ seed: SeedCard, in context: ModelContext) throws -> CardItem {
        let id = seed.stableId
        var desc = FetchDescriptor<CardItem>(predicate: #Predicate { $0.stableId == id })
        desc.fetchLimit = 1
        if let existing = try context.fetch(desc).first {
            // Refresh catalog-owned fields; never touch wallet state.
            existing.canonicalName = seed.canonicalName
            existing.issuer = seed.issuer
            existing.annualFeeDisplay = seed.annualFeeDisplay
            return existing
        }
        let card = CardItem(
            stableId: seed.stableId,
            canonicalName: seed.canonicalName,
            issuer: seed.issuer,
            annualFeeDisplay: seed.annualFeeDisplay
        )
        context.insert(card)
        return card
    }

    private static func fetchOrCreateBenefit(_ seed: SeedBenefit, on card: CardItem, in context: ModelContext) -> BenefitItem {
        if let existing = card.benefits.first(where: { $0.stableId == seed.stableId }) {
            existing.name = seed.name
            existing.cadenceRaw = seed.cadence
            existing.amountDisplay = seed.amountDisplay
            existing.howToUse = seed.howToUse
            existing.enrollmentRequired = seed.enrollmentRequired
            existing.lesserKnown = seed.lesserKnown
            existing.sources = seed.sources
            return existing
        }
        let benefit = BenefitItem(
            stableId: seed.stableId,
            name: seed.name,
            cadenceRaw: seed.cadence,
            amountDisplay: seed.amountDisplay,
            howToUse: seed.howToUse,
            enrollmentRequired: seed.enrollmentRequired,
            lesserKnown: seed.lesserKnown,
            sources: seed.sources
        )
        benefit.card = card
        card.benefits.append(benefit)
        context.insert(benefit)
        return benefit
    }
}

enum SeedError: Error, LocalizedError {
    case missingBundle
    case countMismatch(String)
    case duplicateId(String)
    case unknownCadence(String)
    case missingSource(String)
    case emptyTip(String)

    var errorDescription: String? {
        switch self {
        case .missingBundle: return "SeedData.json is missing from the app bundle."
        case .countMismatch(let what): return "Seed manifest \(what) count does not match the payload."
        case .duplicateId(let id): return "Duplicate stable ID in seed data: \(id)."
        case .unknownCadence(let c): return "Unknown cadence in seed data: \(c)."
        case .missingSource(let id): return "Benefit without a source (provenance required): \(id)."
        case .emptyTip(let id): return "Empty tip text: \(id)."
        }
    }
}
