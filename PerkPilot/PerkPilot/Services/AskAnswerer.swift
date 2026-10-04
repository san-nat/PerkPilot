import Foundation

// MARK: - AskAnswerer
//
// Turns a complete AskQuery into a recommendation. The ordering principle:
// an unused expiring credit almost always beats earn-rate differences, so
// matching credits are checked FIRST, then earn rates, then the two are
// stacked into one conversational answer. Only cards he owns are ever
// recommended. Pure logic over in-memory models — unit-testable.

/// One recurring credit that matches the query and is still unused this period.
struct CreditMatch {
    var card: CardItem
    var benefit: BenefitItem
    /// Parsed dollar value of the credit (0 when unparseable).
    var creditValue: Double
    var periodLabel: String
}

struct AskAnswer {
    /// 2–4 sentence conversational answer (markdown **bold** allowed).
    var headline: String
    var credits: [CreditMatch]
    /// Top earn-rate cards (already filtered to his active cards).
    var ranked: [RewardsAdvisor.RankedCard]
    var category: SpendCategory
    var amount: Double
}

enum AskAnswerer {

    /// Curated credit patterns. Keywords are matched against the lowercased
    /// benefit name + how-to-use text; categories/merchants against the query.
    private struct CreditPattern {
        var keywords: [String]
        var categories: [SpendCategory]
        var merchantKeywords: [String]
    }

    private static let patterns: [CreditPattern] = [
        CreditPattern(keywords: ["doordash"], categories: [.dining], merchantKeywords: ["doordash"]),
        CreditPattern(keywords: ["grubhub"], categories: [.dining], merchantKeywords: ["grubhub", "doordash"]),
        CreditPattern(keywords: ["uber eats"], categories: [.dining], merchantKeywords: ["uber eats", "doordash"]),
        CreditPattern(keywords: ["resy"], categories: [.dining], merchantKeywords: ["resy"]),
        CreditPattern(keywords: ["uber cash"], categories: [.travel], merchantKeywords: ["uber"]),
        CreditPattern(keywords: ["lyft"], categories: [.travel], merchantKeywords: ["lyft"]),
        CreditPattern(keywords: ["airline incidental", "airline fee credit"], categories: [.travel], merchantKeywords: ["delta", "united", "american", "southwest", "jetblue", "alaska"]),
        CreditPattern(keywords: ["hotel credit"], categories: [.travel], merchantKeywords: ["hotel", "marriott", "hyatt", "hilton"]),
        CreditPattern(keywords: ["equinox"], categories: [.health], merchantKeywords: ["equinox", "gym", "fitness"]),
        CreditPattern(keywords: ["peloton"], categories: [.health], merchantKeywords: ["peloton"]),
        CreditPattern(keywords: ["instacart"], categories: [.groceries], merchantKeywords: ["instacart"]),
        CreditPattern(keywords: ["walmart+"], categories: [.shopping, .groceries], merchantKeywords: ["walmart"]),
        CreditPattern(keywords: ["digital entertainment"], categories: [.entertainment], merchantKeywords: ["netflix", "spotify", "hulu", "disney"]),
        CreditPattern(keywords: ["saks"], categories: [.shopping], merchantKeywords: ["saks"]),
        CreditPattern(keywords: ["lululemon"], categories: [.shopping], merchantKeywords: ["lululemon"]),
    ]

    /// Compose the full answer. All inputs are plain values — no SwiftData.
    static func answer(
        query: AskQuery,
        cards: [CardItem],
        mutedIds: Set<String>,
        completedKeys: Set<String>,
        ytd: [String: [SpendCategory: Double]],
        now: Date = Date()
    ) -> AskAnswer? {
        guard let amount = query.amount, let category = query.category else { return nil }
        let active = cards.filter { !$0.isArchived }
        let credits = matchingCredits(query: query, cards: active, mutedIds: mutedIds, completedKeys: completedKeys, now: now)
        let ranked = RewardsAdvisor.bestCard(
            merchant: query.merchant ?? category.displayName,
            amount: amount, category: category, ytd: ytd
        ).filter { rc in active.contains { $0.stableId == rc.cardStableId } }
        .prefix(3).map { $0 }
        let headline = composeHeadline(query: query, amount: amount, category: category, credits: credits, ranked: ranked)
        return AskAnswer(headline: headline, credits: credits, ranked: ranked, category: category, amount: amount)
    }

    // MARK: - Expiring credits

    static func matchingCredits(
        query: AskQuery,
        cards: [CardItem],
        mutedIds: Set<String>,
        completedKeys: Set<String>,
        now: Date
    ) -> [CreditMatch] {
        var out: [CreditMatch] = []
        for card in cards {
            for benefit in card.benefits {
                guard let cadence = benefit.cadence, cadence.isRecurring,
                      !mutedIds.contains(benefit.stableId),
                      benefit.amountDisplay.contains("$"),
                      let periodKey = RecurrenceEngine.periodKey(cadence: cadence, date: now),
                      !completedKeys.contains("\(benefit.stableId)|\(periodKey)")
                else { continue }
                guard matchesPattern(benefit: benefit, query: query) else { continue }
                let label = RecurrenceEngine.periodLabel(cadence: cadence, date: now) ?? "this period"
                out.append(CreditMatch(
                    card: card, benefit: benefit,
                    creditValue: firstDollarAmount(in: benefit.amountDisplay),
                    periodLabel: label
                ))
            }
        }
        // Biggest credit first — a $300 annual credit beats a $10 monthly one.
        return out.sorted { $0.creditValue > $1.creditValue }.prefix(3).map { $0 }
    }

    private static func matchesPattern(benefit: BenefitItem, query: AskQuery) -> Bool {
        let text = (benefit.name + " " + benefit.howToUse).lowercased()
        for p in patterns {
            guard p.keywords.contains(where: { text.contains($0) }) else { continue }
            let merchantHit = query.merchant.map { m in
                p.merchantKeywords.contains { m.contains($0) }
            } ?? false
            let categoryHit = query.category.map { p.categories.contains($0) } ?? false
            if merchantHit || categoryHit { return true }
        }
        return false
    }

    /// First $ amount in a display string ("Up to $300 per calendar year" → 300).
    static func firstDollarAmount(in text: String) -> Double {
        guard let regex = try? NSRegularExpression(pattern: #"\$\s*([\d,]+(?:\.\d{1,2})?)"#) else { return 0 }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1,
              let v = Double(ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: ""))
        else { return 0 }
        return v
    }

    // MARK: - Headline

    private static func shortName(_ card: CardItem) -> String {
        RewardsAdvisor.profiles[card.stableId]?.shortName ?? card.canonicalName
    }

    private static func money(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "$%.0f", v) : String(format: "$%.2f", v)
    }

    private static func composeHeadline(
        query: AskQuery,
        amount: Double,
        category: SpendCategory,
        credits: [CreditMatch],
        ranked: [RewardsAdvisor.RankedCard]
    ) -> String {
        var parts: [String] = []
        if let top = credits.first {
            let cardName = shortName(top.card)
            var lead = "Use your **\(cardName)** — you still have its \(top.benefit.amountDisplay) \(top.benefit.name) for \(top.periodLabel). An unused credit beats any earn rate, so burn that first."
            if top.benefit.enrollmentRequired {
                lead += " Make sure you're enrolled first."
            }
            parts.append(lead)
            if top.creditValue > 0 && amount > top.creditValue, let earn = ranked.first {
                if earn.cardStableId == top.card.stableId {
                    parts.append("It covers about \(money(top.creditValue)) of the \(money(amount)); the rest on the same card earns \(earn.rateLabel).")
                } else {
                    // A credit and the best earn rate live on different cards: only
                    // suggest "stacking" when part of the spend can plausibly go
                    // through the credit's channel (e.g. delivery vs. dine-in).
                    parts.append("If part of this spend can go through \(top.benefit.name.lowercased()) separately, burn the \(money(top.creditValue)) credit on the \(cardName) there; the rest earns best on **\(earn.displayName)** (\(earn.rateLabel)).")
                }
            }
            for extra in credits.dropFirst() {
                parts.append("Also still unused: \(shortName(extra.card))'s \(extra.benefit.amountDisplay) \(extra.benefit.name).")
            }
        } else if let best = ranked.first {
            let where_ = query.merchantDisplay.map { " at \($0)" } ?? ""
            parts.append("For \(money(amount)) on \(category.displayName.lowercased())\(where_), use your **\(best.displayName)** — \(best.rateLabel), about \(money(best.rewardUSD)) back in value.")
            if ranked.count > 1 {
                parts.append("Runner-up: \(ranked[1].displayName) (\(ranked[1].rateLabel)).")
            }
            parts.append("No unused expiring credits matched this spend — these are estimates.")
        } else {
            parts.append("I couldn't rank cards for that spend — try adding a category like dining or travel.")
        }
        return parts.joined(separator: " ")
    }
}
