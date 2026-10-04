import Foundation

// MARK: - RewardMatcher
//
// Heuristic cross-check: "did this recurring credit actually get used?"
// For each recurring benefit it matches statement transactions by merchant
// keywords + expected-amount patterns within the benefit's period.
//
// This is a HEURISTIC, not bank verification. The UI must say so, and every
// status carries a confidence note. Manual confirm/override writes straight
// into the existing checklist (CompletionRecord) — the matcher never
// invents checkmarks on its own.

enum MatchConfidence: String, Sendable {
    case high
    case medium
    case low

    var displayName: String {
        switch self {
        case .high: return "High confidence"
        case .medium: return "Medium confidence"
        case .low: return "Low confidence"
        }
    }
}

enum RewardMatchStatus: Sendable {
    /// A transaction looks like the credit being used.
    case likelyReceived(confidence: MatchConfidence, transaction: BankTransaction, note: String)
    /// Statements exist for the period but nothing matched.
    case notDetected(note: String)
    /// No statements imported for this card+period — nothing to check.
    case noStatements
    /// The user already checked this off manually.
    case manuallyConfirmed
}

struct RewardMatchRule: Sendable {
    var merchantKeywords: [String]  // matched against normalized merchant
    /// Expected charge magnitude (positive), e.g. 15 for "$15/mo".
    /// nil = keyword-only match (lower confidence).
    var expectedAmount: Double?
}

enum RewardMatcher {
    // MARK: Curated merchant keywords by benefit

    /// stableId substring → merchant keywords. Curated from the researched
    /// catalog; the generic fallback below covers the rest.
    private static let keywordTable: [(String, [String])] = [
        ("uber", ["UBER"]),
        ("lyft", ["LYFT"]),
        ("doordash", ["DOORDASH"]),
        ("grubhub", ["GRUBHUB"]),
        ("instacart", ["INSTACART"]),
        ("peloton", ["PELOTON"]),
        ("walmart", ["WALMART"]),
        ("resy", ["RESY"]),
        ("equinox", ["EQUINOX"]),
        ("soulcycle", ["SOULCYCLE"]),
        ("lululemon", ["LULULEMON"]),
        ("saks", ["SAKS"]),
        ("whole-foods", ["WHOLE FOODS", "WHOLEFDS"]),
        ("best-buy", ["BEST BUY"]),
        ("oura", ["OURA"]),
        ("clear", ["CLEAR"]),
        ("delta-stays", ["DELTA"]),
        ("airline-fee", ["DELTA", "UNITED", "AMERICAN", "SOUTHWEST", "JETBLUE", "ALASKA"]),
        ("hotel", ["MARRIOTT", "HYATT", "HILTON", "IHG", "HOTEL"]),
        ("stubhub", ["STUBHUB"]),
        ("disney", ["DISNEY"]),
        ("hulu", ["HULU"]),
        ("espn", ["ESPN"]),
        ("walmart-plus", ["WALMART"]),
        ("entertainment", ["NETFLIX", "HULU", "DISNEY", "MAX", "PARAMOUNT", "PEACOCK"]),
    ]

    private static let stopwords: Set<String> = [
        "the", "a", "an", "credit", "statement", "monthly", "annual",
        "membership", "subscription", "fee", "enrollment",
    ]

    /// Build a match rule for a benefit: curated keywords first, then a
    /// generic fallback from the benefit's name tokens.
    static func rule(for benefit: BenefitItem) -> RewardMatchRule {
        let id = benefit.stableId.lowercased()
        for (key, keywords) in keywordTable where id.contains(key) {
            return RewardMatchRule(
                merchantKeywords: keywords,
                expectedAmount: expectedAmount(for: benefit)
            )
        }
        // Generic fallback: distinctive tokens from the benefit name.
        let tokens = benefit.name
            .uppercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 && !stopwords.contains($0.lowercased()) }
        return RewardMatchRule(
            merchantKeywords: Array(tokens.prefix(3)),
            expectedAmount: expectedAmount(for: benefit)
        )
    }

    /// Parse the per-period expected charge from amountDisplay, e.g.
    /// "$15/mo" → 15. Annual figures ("$200/yr") are divided to the
    /// benefit's cadence so monthly matching stays sane.
    static func expectedAmount(for benefit: BenefitItem) -> Double? {
        let text = benefit.amountDisplay
        guard let range = text.range(of: #"\$([\d,]+(?:\.\d{1,2})?)"#, options: .regularExpression) else {
            return nil
        }
        let numString = String(text[range]).replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard var value = Double(numString) else { return nil }
        let lower = text.lowercased()
        let cadence = benefit.cadence ?? .monthly
        if lower.contains("/yr") || lower.contains("annual") || lower.contains("per year") {
            switch cadence {
            case .monthly: value /= 12
            case .quarterly: value /= 4
            case .semiannual: value /= 2
            case .annual, .oneTime, .perUse: break
            }
        }
        return value
    }

    // MARK: Evaluation

    /// Evaluate one benefit against transactions in its period.
    /// - Parameters:
    ///   - benefit: the recurring benefit to check
    ///   - transactions: ALL imported transactions for the card in the period
    ///   - periodKey: e.g. "2026-10" (used only for messaging)
    ///   - alreadyCompleted: whether a CompletionRecord exists (manual check)
    static func evaluate(
        benefit: BenefitItem,
        transactions: [BankTransaction],
        periodKey: String,
        alreadyCompleted: Bool
    ) -> RewardMatchStatus {
        if alreadyCompleted { return .manuallyConfirmed }
        guard !transactions.isEmpty else { return .noStatements }

        let rule = rule(for: benefit)
        let charges = transactions.filter(\.isCharge)
        var best: (BankTransaction, MatchConfidence, String)?

        for tx in charges {
            for keyword in rule.merchantKeywords {
                guard tx.merchantNormalized.contains(keyword) else { continue }
                if let expected = rule.expectedAmount {
                    let diff = abs(tx.absAmount - expected) / expected
                    if diff <= 0.05 {
                        let note = "\(tx.merchantRaw) · $\(fmt(tx.absAmount)) matches the expected $\(fmt(expected)) charge."
                        return .likelyReceived(confidence: .high, transaction: tx, note: note)
                    } else if diff <= 0.25 {
                        let note = "\(tx.merchantRaw) · $\(fmt(tx.absAmount)) is near the expected $\(fmt(expected))."
                        best = best ?? (tx, .medium, note)
                    } else {
                        let note = "\(tx.merchantRaw) · $\(fmt(tx.absAmount)) mentions \(keyword.lowercased()) but not the expected $\(fmt(expected))."
                        if best == nil { best = (tx, .low, note) }
                    }
                } else {
                    let note = "\(tx.merchantRaw) mentions \(keyword.lowercased()); no expected amount to compare."
                    if best == nil { best = (tx, .low, note) }
                }
            }
        }
        if let (tx, conf, note) = best {
            return .likelyReceived(confidence: conf, transaction: tx, note: note)
        }
        let keywords = rule.merchantKeywords.joined(separator: ", ").lowercased()
        return .notDetected(note: "No \(periodKey) charge matched \(keywords.isEmpty ? "any known merchant" : keywords).")
    }

    private static func fmt(_ v: Double) -> String {
        String(format: "%.2f", v)
    }
}
