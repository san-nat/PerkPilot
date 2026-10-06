import Foundation

// MARK: - SpendAuditService
//
// Flagship "Missed Rewards Audit": replays every imported charge transaction
// in chronological order against the optimal card for that spend, simulating
// annual caps in date order so the counterfactual stays honest instead of
// fantasy. Also tallies recurring credits that expired unused ("tracked
// expirations").
//
// Pure logic over plain structs — no SwiftData, no networking, fully
// unit-testable. Every dollar figure is an estimate built on the same
// conservative valuations as RewardsAdvisor.

/// Plain transaction input (BankTransaction maps to this).
struct AuditTransaction {
    var stableId: String
    var date: Date
    var cardStableId: String
    var merchant: String
    var amount: Double            // signed; negative = charge
    var category: SpendCategory
    var confidence: Double
    var flagged: Bool
}

/// Plain benefit input for the expired-credit tally.
struct AuditBenefit {
    var stableId: String
    var cardStableId: String
    var name: String
    var howToUse: String
    var cadence: Cadence
    var amountDisplay: String
    var enrollmentRequired: Bool
}

struct MissedOpportunity {
    var transactionId: String
    var date: Date
    var merchant: String
    var amount: Double            // abs dollars
    var category: SpendCategory
    var usedCardId: String
    var usedShortName: String
    var usedRateLabel: String
    var usedValueUSD: Double
    var optimalCardId: String
    var optimalShortName: String
    var optimalRateLabel: String
    var optimalValueUSD: Double
    /// optimal − actual, always >= the de minimis threshold.
    var missedUSD: Double
}

struct ExpiredCredit {
    var cardShortName: String
    var benefitName: String
    var amountDisplay: String
    var faceValue: Double
    var periodKey: String
    var periodLabel: String
}

struct AuditReport {
    var year: Int
    var opportunities: [MissedOpportunity]   // desc by missedUSD
    var missedEarnUSD: Double
    var expiredCredits: [ExpiredCredit]      // desc by faceValue
    var expiredCreditsUSD: Double
    var totalMissedUSD: Double
    var analyzedCount: Int
    var analyzedSpendUSD: Double
    var excludedLowConfidence: Int
    /// Projected full-year total; nil once the year is over.
    var annualizedProjectionUSD: Double?
    /// (category, missed $, spend $) — desc by missed.
    var missedByCategory: [(SpendCategory, Double, Double)]
    /// (cardId, shortName, missed $, spend $) — desc by missed.
    var missedByUsedCard: [(String, String, Double, Double)]
    /// Earliest statement import — expired credits are only counted
    /// from here on ("tracked expirations").
    var trackingStartDate: Date?
}

enum SpendAuditService {

    /// Map SwiftData models to plain audit inputs.
    static func input(from tx: BankTransaction) -> AuditTransaction {
        AuditTransaction(
            stableId: tx.stableId,
            date: tx.date,
            cardStableId: tx.cardStableId,
            merchant: tx.merchantRaw,
            amount: tx.amount,
            category: tx.category,
            confidence: tx.confidence,
            flagged: tx.isFlaggedForReview
        )
    }

    static func input(from benefit: BenefitItem) -> AuditBenefit? {
        guard let cadence = benefit.cadence, cadence.isRecurring else { return nil }
        return AuditBenefit(
            stableId: benefit.stableId,
            cardStableId: benefit.card?.stableId ?? "",
            name: benefit.name,
            howToUse: benefit.howToUse,
            cadence: cadence,
            amountDisplay: benefit.amountDisplay,
            enrollmentRequired: benefit.enrollmentRequired
        )
    }

    /// Convenience overload straight from SwiftData models.
    static func audit(
        transactions: [BankTransaction],
        cards: [CardItem],
        completions: [CompletionRecord],
        mutes: [MutedReward],
        documents: [StatementDocument],
        now: Date = Date(),
        deMinimis: Double = 0.25,
        calendar: Calendar = .current
    ) -> AuditReport {
        let active = cards.filter { !$0.isArchived }
        return audit(
            transactions: transactions.map(input(from:)),
            activeCards: active.map {
                (stableId: $0.stableId,
                 shortName: RewardsAdvisor.profiles[$0.stableId]?.shortName ?? $0.canonicalName)
            },
            benefits: active.flatMap(\.benefits).compactMap(input(from:)),
            mutedBenefitIds: Set(mutes.map(\.benefitStableId)),
            completedKeys: Set(completions.map(\.lookupKey)),
            trackingStart: documents.map(\.importedAt).min(),
            now: now,
            deMinimis: deMinimis,
            calendar: calendar
        )
    }

    /// Pure core. `activeCards` = (stableId, shortName) of non-archived cards.
    static func audit(
        transactions: [AuditTransaction],
        activeCards: [(stableId: String, shortName: String)],
        benefits: [AuditBenefit] = [],
        mutedBenefitIds: Set<String> = [],
        completedKeys: Set<String> = [],
        trackingStart: Date? = nil,
        now: Date = Date(),
        deMinimis: Double = 0.25,
        calendar: Calendar = .current
    ) -> AuditReport {
        let year = calendar.component(.year, from: now)
        let activeIds = Set(activeCards.map(\.stableId))
        let shortName = Dictionary(uniqueKeysWithValues: activeCards.map { ($0.stableId, $0.shortName) })

        // Charges only, this year, confident enough. Everything else is
        // counted as excluded so the UI can say so honestly.
        var excluded = 0
        let charges: [AuditTransaction] = transactions.filter { tx in
            guard tx.amount < 0, tx.category.isSpend,
                  calendar.component(.year, from: tx.date) == year else { return false }
            guard !tx.flagged, tx.confidence >= 0.7 else { excluded += 1; return false }
            guard RewardsAdvisor.profiles[tx.cardStableId] != nil else { return false }
            return true
        }.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.stableId < $1.stableId
        }

        // Two ledgers, both in date order:
        // - actualLedger: what each card really spent (drives the rate the
        //   used card actually earned at that date).
        // - optimalLedger: what each card would have spent if every past
        //   transaction had gone to its optimal card (drives the honest
        //   counterfactual — caps in the "what if" world).
        var actualLedger: [String: [SpendCategory: Double]] = [:]
        var optimalLedger: [String: [SpendCategory: Double]] = [:]
        var opportunities: [MissedOpportunity] = []
        var spendByCard: [String: Double] = [:]
        var spendByCategory: [SpendCategory: Double] = [:]

        for tx in charges {
            let amount = abs(tx.amount)
            let norm = CategoryEngine.normalizeMerchant(tx.merchant)
            spendByCard[tx.cardStableId, default: 0] += amount
            spendByCategory[tx.category, default: 0] += amount

            guard let usedProfile = RewardsAdvisor.profiles[tx.cardStableId] else { continue }
            let used = rateUSD(usedProfile, category: tx.category, merchant: norm,
                               consumed: actualLedger, cardId: tx.cardStableId)
            let usedValue = used.usdPerDollar * amount

            var bestId = tx.cardStableId
            var best = used
            var bestValue = usedValue
            for id in activeIds {
                guard let profile = RewardsAdvisor.profiles[id] else { continue }
                let r = rateUSD(profile, category: tx.category, merchant: norm,
                                consumed: optimalLedger, cardId: id)
                let v = r.usdPerDollar * amount
                if v > bestValue {
                    bestValue = v
                    best = r
                    bestId = id
                }
            }

            let missed = bestValue - usedValue
            if bestId != tx.cardStableId, missed >= deMinimis {
                opportunities.append(MissedOpportunity(
                    transactionId: tx.stableId,
                    date: tx.date,
                    merchant: tx.merchant,
                    amount: amount,
                    category: tx.category,
                    usedCardId: tx.cardStableId,
                    usedShortName: shortName[tx.cardStableId] ?? tx.cardStableId,
                    usedRateLabel: used.rateLabel,
                    usedValueUSD: usedValue,
                    optimalCardId: bestId,
                    optimalCardShortName: shortName[bestId] ?? bestId,
                    optimalRateLabel: best.rateLabel,
                    optimalValueUSD: bestValue,
                    missedUSD: missed
                ))
            }

            actualLedger[tx.cardStableId, default: [:]][tx.category, default: 0] += amount
            optimalLedger[bestId, default: [:]][tx.category, default: 0] += amount
        }

        opportunities.sort { $0.missedUSD > $1.missedUSD }
        let missedEarn = opportunities.reduce(0) { $0 + $1.missedUSD }

        let expired = expiredCredits(
            benefits: benefits, mutedIds: mutedBenefitIds, completedKeys: completedKeys,
            charges: charges, trackingStart: trackingStart, now: now,
            shortName: shortName, calendar: calendar
        )
        let expiredUSD = expired.reduce(0) { $0 + $1.faceValue }

        // Annualized projection while the year is still in progress.
        var projection: Double? = nil
        let total = missedEarn + expiredUSD
        if let dayOfYear = calendar.ordinality(of: .day, in: .year, for: now),
           let daysInYear = calendar.range(of: .day, in: .year, for: now)?.count,
           dayOfYear < daysInYear, dayOfYear > 0 {
            projection = total * Double(daysInYear) / Double(dayOfYear)
        }

        // Breakdowns.
        var missByCat: [SpendCategory: Double] = [:]
        for o in opportunities { missByCat[o.category, default: 0] += o.missedUSD }
        let byCategory = missByCat
            .map { (cat: $0.key, missed: $0.value, spend: spendByCategory[$0.key] ?? 0) }
            .sorted { $0.missed > $1.missed }

        var missByCard: [String: Double] = [:]
        for o in opportunities { missByCard[o.usedCardId, default: 0] += o.missedUSD }
        let byCard = missByCard
            .map { (id: $0.key, name: shortName[$0.key] ?? $0.key, missed: $0.value,
                    spend: spendByCard[$0.key] ?? 0) }
            .sorted { $0.missed > $1.missed }

        return AuditReport(
            year: year,
            opportunities: opportunities,
            missedEarnUSD: missedEarn,
            expiredCredits: expired,
            expiredCreditsUSD: expiredUSD,
            totalMissedUSD: total,
            analyzedCount: charges.count,
            analyzedSpendUSD: charges.reduce(0) { $0 + abs($1.amount) },
            excludedLowConfidence: excluded,
            annualizedProjectionUSD: projection,
            missedByCategory: byCategory,
            missedByUsedCard: byCard,
            trackingStartDate: trackingStart
        )
    }

    // MARK: - Rates with honest cap simulation

    /// Effective USD reward per $1, honoring annual caps from the given
    /// consumption ledger. Southwest's $8k cap is shared across groceries +
    /// dining, so those two categories draw from one pool.
    private static func rateUSD(
        _ profile: EarnProfile,
        category: SpendCategory,
        merchant: String,
        consumed: [String: [SpendCategory: Double]],
        cardId: String
    ) -> (usdPerDollar: Double, rateLabel: String, why: String, capHit: Bool) {
        var ledger = consumed
        if cardId == "southwest-premier",
           category == .groceries || category == .dining {
            let shared = (consumed[cardId]?[.groceries] ?? 0) + (consumed[cardId]?[.dining] ?? 0)
            ledger[cardId] = [.groceries: shared, .dining: shared]
        }
        let ytd = ledger[cardId]?[category] ?? 0
        return RewardsAdvisor.effectiveRateUSD(
            profile, category: category,
            merchantNormalized: merchant, ytdCategorySpend: ytd
        )
    }

    // MARK: - Expired credits ("tracked expirations")

    /// Benefit name keywords → spend categories where the credit could
    /// plausibly have been used. Mirrors AskAnswerer's credit patterns.
    private static let creditCategoryPatterns: [(keywords: [String], categories: [SpendCategory])] = [
        (["doordash"], [.dining]), (["grubhub"], [.dining]), (["uber eats"], [.dining]),
        (["resy"], [.dining]),
        (["uber cash"], [.travel]), (["lyft"], [.travel]),
        (["airline incidental", "airline fee credit"], [.travel]),
        (["hotel credit"], [.travel]),
        (["equinox"], [.health]), (["peloton"], [.health]),
        (["instacart"], [.groceries]),
        (["walmart+"], [.shopping, .groceries]),
        (["digital entertainment"], [.entertainment]),
        (["saks"], [.shopping]), (["lululemon"], [.shopping]),
    ]

    private static func plausibleCategories(for benefit: AuditBenefit) -> [SpendCategory]? {
        let text = (benefit.name + " " + benefit.howToUse).lowercased()
        for p in creditCategoryPatterns where p.keywords.contains(where: { text.contains($0) }) {
            return p.categories
        }
        return nil   // unmapped: can't judge plausibility
    }

    /// Fully elapsed periods of `cadence` between `start` and `now`
    /// (the period containing `now` is still usable — excluded).
    private static func elapsedPeriods(
        cadence: Cadence, from start: Date, to now: Date, calendar: Calendar
    ) -> [(key: String, label: String)] {
        let step: DateComponents
        switch cadence {
        case .monthly: step = DateComponents(month: 1)
        case .quarterly: step = DateComponents(month: 3)
        case .semiannual: step = DateComponents(month: 6)
        case .annual: step = DateComponents(year: 1)
        case .oneTime, .perUse: return []
        }
        guard var cursor = RecurrenceEngine.periodRange(cadence: cadence, date: start, calendar: calendar)?.start
        else { return [] }
        let currentKey = RecurrenceEngine.periodKey(cadence: cadence, date: now, calendar: calendar)
        var out: [(String, String)] = []
        for _ in 0..<60 {   // safety bound: 5 years of monthly periods
            guard let key = RecurrenceEngine.periodKey(cadence: cadence, date: cursor, calendar: calendar),
                  key != currentKey,
                  let label = RecurrenceEngine.periodLabel(cadence: cadence, date: cursor, calendar: calendar)
            else { break }
            out.append((key, label))
            guard let next = calendar.date(byAdding: step, to: cursor), next < now else { break }
            cursor = next
        }
        return out
    }

    private static func expiredCredits(
        benefits: [AuditBenefit],
        mutedIds: Set<String>,
        completedKeys: Set<String>,
        charges: [AuditTransaction],
        trackingStart: Date?,
        now: Date,
        shortName: [String: String],
        calendar: Calendar
    ) -> [ExpiredCredit] {
        guard let trackingStart else { return [] }
        var out: [ExpiredCredit] = []
        for benefit in benefits {
            guard !mutedIds.contains(benefit.stableId),
                  benefit.amountDisplay.contains("$") else { continue }
            let faceValue = AskAnswerer.firstDollarAmount(in: benefit.amountDisplay)
            guard faceValue > 0 else { continue }
            let plausible = plausibleCategories(for: benefit)
            for period in elapsedPeriods(cadence: benefit.cadence, from: trackingStart, to: now, calendar: calendar) {
                let key = "\(benefit.stableId)|\(period.key)"
                guard !completedKeys.contains(key) else { continue }
                // Plausibility: was there spend in this period where the
                // credit could have been used? No data at all → count it
                // (unknown); data but nothing plausible → skip.
                if let plausible {
                    let periodTxs = charges.filter {
                        RecurrenceEngine.periodKey(cadence: benefit.cadence, date: $0.date, calendar: calendar) == period.key
                    }
                    if !periodTxs.isEmpty,
                       !periodTxs.contains(where: { plausible.contains($0.category) }) {
                        continue
                    }
                }
                out.append(ExpiredCredit(
                    cardShortName: shortName[benefit.cardStableId] ?? benefit.cardStableId,
                    benefitName: benefit.name,
                    amountDisplay: benefit.amountDisplay,
                    faceValue: faceValue,
                    periodKey: period.key,
                    periodLabel: period.label
                ))
            }
        }
        return out.sorted { $0.faceValue > $1.faceValue }
    }
}
