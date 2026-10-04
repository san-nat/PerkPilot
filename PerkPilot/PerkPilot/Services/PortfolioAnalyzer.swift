import Foundation

// MARK: - PortfolioAnalyzer
//
// "Should I get a new card?" engine. Aggregates YTD category spend across
// ALL imported statements, then scores ~12 popular cards Santosh does NOT
// hold by incremental annual value vs his current best card per category:
//   (eligible spend × (candidate rate − current best rate)) + usable credits − annual fee
//
// Overlap handling is explicit: spend already earning a top rate elsewhere
// (e.g. Whole Foods at 5% on his Prime Visa) is subtracted before scoring
// a candidate. Nothing is presented as guaranteed — valuations and
// assumptions are shown next to every number.

struct CandidateCard {
    var stableId: String
    var name: String
    var issuer: String
    var isChaseIssued: Bool
    var annualFee: Double
    var valuationUSDPerUnit: Double
    var unitLabel: String
    /// Units per $ by category; absent categories fall back to baseRate.
    var rates: [SpendCategory: Double]
    var baseRate: Double
    /// Annual bonus caps: category → (limit, overRate in units per $).
    var caps: [SpendCategory: (limit: Double, over: Double)]
    /// When true, only the single best-scoring category counts
    /// (e.g. Citi Custom Cash's top-category mechanic).
    var bestCategoryOnly: Bool
    /// Conservative $/yr of statement credits he'd plausibly use.
    var usableCredits: Double
    var creditsNote: String
    /// Merchant keywords whose spend is removed from a category before
    /// scoring (already earning a top rate on a card he holds).
    var overlapExclusions: [SpendCategory: [String]]
    var notes: [String]
}

struct CandidateLineItem {
    var category: SpendCategory
    var eligibleAnnualSpend: Double
    var candidatePct: Double     // effective reward % for this category
    var currentBestPct: Double
    var incrementalUSD: Double
}

struct CandidateVerdict {
    var candidate: CandidateCard
    var lineItems: [CandidateLineItem]   // desc by incrementalUSD
    var incrementalRewardsUSD: Double
    var usableCreditsUSD: Double
    var annualFeeUSD: Double
    var netAnnualUSD: Double
    var chaseCaution: String?
    var assumptions: [String]
}

enum PortfolioAnalyzer {
    // MARK: Candidate database (~12 popular cards he doesn't hold)

    static let candidates: [CandidateCard] = [
        CandidateCard(
            stableId: "cand-amex-gold", name: "Amex Gold", issuer: "American Express",
            isChaseIssued: false, annualFee: 325,
            valuationUSDPerUnit: 0.010, unitLabel: "MR",
            rates: [.dining: 4, .groceries: 4], baseRate: 1,
            caps: [.groceries: (limit: 25_000, over: 1)],
            bestCategoryOnly: false, usableCredits: 120,
            creditsNote: "$120 Uber Cash counted; $120 dining credit only if you order delivery",
            overlapExclusions: [.groceries: ["whole foods", "costco"]],
            notes: ["4x groceries = U.S. supermarkets, first $25k/yr", "Amex isn't accepted at Costco warehouses"]),
        CandidateCard(
            stableId: "cand-bcp", name: "Blue Cash Preferred", issuer: "American Express",
            isChaseIssued: false, annualFee: 95,
            valuationUSDPerUnit: 1.0, unitLabel: "$",
            rates: [.groceries: 0.06, .entertainment: 0.06, .gas: 0.03], baseRate: 0.01,
            caps: [.groceries: (limit: 6_000, over: 0.01)],
            bestCategoryOnly: false, usableCredits: 0,
            creditsNote: "No annual credits",
            overlapExclusions: [.groceries: ["whole foods", "costco"]],
            notes: ["6% groceries = U.S. supermarkets, first $6k/yr", "6% entertainment = streaming"]),
        CandidateCard(
            stableId: "cand-bce", name: "Blue Cash Everyday", issuer: "American Express",
            isChaseIssued: false, annualFee: 0,
            valuationUSDPerUnit: 1.0, unitLabel: "$",
            rates: [.groceries: 0.03, .gas: 0.03, .shopping: 0.03], baseRate: 0.01,
            caps: [.groceries: (limit: 6_000, over: 0.01), .shopping: (limit: 6_000, over: 0.01)],
            bestCategoryOnly: false, usableCredits: 0,
            creditsNote: "No annual credits",
            overlapExclusions: [.groceries: ["whole foods", "costco"]],
            notes: ["3% groceries = U.S. supermarkets, first $6k/yr", "3% shopping = online retail"]),
        CandidateCard(
            stableId: "cand-venture-x", name: "Capital One Venture X", issuer: "Capital One",
            isChaseIssued: false, annualFee: 395,
            valuationUSDPerUnit: 0.010, unitLabel: "mi",
            rates: [.travel: 2], baseRate: 2,
            caps: [:],
            bestCategoryOnly: false, usableCredits: 150,
            creditsNote: "$300 Capital One Travel credit, counted at half (portal booking required)",
            overlapExclusions: [:],
            notes: ["Miles valued conservatively at 1.0¢", "10k anniversary miles excluded from math"]),
        CandidateCard(
            stableId: "cand-savor", name: "Capital One Savor", issuer: "Capital One",
            isChaseIssued: false, annualFee: 95,
            valuationUSDPerUnit: 1.0, unitLabel: "$",
            rates: [.dining: 0.03, .entertainment: 0.03, .groceries: 0.03], baseRate: 0.01,
            caps: [:],
            bestCategoryOnly: false, usableCredits: 0,
            creditsNote: "No annual credits",
            overlapExclusions: [.groceries: ["whole foods", "costco"]],
            notes: []),
        CandidateCard(
            stableId: "cand-custom-cash", name: "Citi Custom Cash", issuer: "Citi",
            isChaseIssued: false, annualFee: 0,
            valuationUSDPerUnit: 1.0, unitLabel: "$",
            rates: [.dining: 0.05, .groceries: 0.05, .gas: 0.05, .travel: 0.05,
                    .entertainment: 0.05, .health: 0.05, .shopping: 0.05, .bills: 0.05],
            baseRate: 0.01,
            caps: [.dining: (limit: 6_000, over: 0.01), .groceries: (limit: 6_000, over: 0.01),
                   .gas: (limit: 6_000, over: 0.01), .travel: (limit: 6_000, over: 0.01),
                   .entertainment: (limit: 6_000, over: 0.01), .health: (limit: 6_000, over: 0.01),
                   .shopping: (limit: 6_000, over: 0.01), .bills: (limit: 6_000, over: 0.01)],
            bestCategoryOnly: true, usableCredits: 0,
            creditsNote: "No annual credits",
            overlapExclusions: [.groceries: ["whole foods", "costco"]],
            notes: ["5% applies to your TOP spend category only, $500/billing cycle"]),
        CandidateCard(
            stableId: "cand-double-cash", name: "Citi Double Cash", issuer: "Citi",
            isChaseIssued: false, annualFee: 0,
            valuationUSDPerUnit: 1.0, unitLabel: "$",
            rates: [:], baseRate: 0.02,
            caps: [:],
            bestCategoryOnly: false, usableCredits: 0,
            creditsNote: "No annual credits",
            overlapExclusions: [:],
            notes: ["Flat 2% cash back, no caps"]),
        CandidateCard(
            stableId: "cand-autograph", name: "Wells Fargo Autograph", issuer: "Wells Fargo",
            isChaseIssued: false, annualFee: 0,
            valuationUSDPerUnit: 0.010, unitLabel: "pt",
            rates: [.dining: 3, .travel: 3, .gas: 3, .entertainment: 3, .bills: 3], baseRate: 1,
            caps: [:],
            bestCategoryOnly: false, usableCredits: 0,
            creditsNote: "No annual credits",
            overlapExclusions: [:],
            notes: ["3x entertainment = streaming", "3x bills = phone plans"]),
        CandidateCard(
            stableId: "cand-active-cash", name: "Wells Fargo Active Cash", issuer: "Wells Fargo",
            isChaseIssued: false, annualFee: 0,
            valuationUSDPerUnit: 1.0, unitLabel: "$",
            rates: [:], baseRate: 0.02,
            caps: [:],
            bestCategoryOnly: false, usableCredits: 0,
            creditsNote: "No annual credits",
            overlapExclusions: [:],
            notes: ["Flat 2% cash back, no caps"]),
        CandidateCard(
            stableId: "cand-discover-it", name: "Discover it", issuer: "Discover",
            isChaseIssued: false, annualFee: 0,
            valuationUSDPerUnit: 1.0, unitLabel: "$",
            rates: [.dining: 0.05, .groceries: 0.05, .gas: 0.05, .shopping: 0.05, .entertainment: 0.05],
            baseRate: 0.01,
            caps: [.dining: (limit: 3_000, over: 0.01), .groceries: (limit: 3_000, over: 0.01),
                   .gas: (limit: 3_000, over: 0.01), .shopping: (limit: 3_000, over: 0.01),
                   .entertainment: (limit: 3_000, over: 0.01)],
            bestCategoryOnly: false, usableCredits: 0,
            creditsNote: "No annual credits",
            overlapExclusions: [.groceries: ["whole foods", "costco"]],
            notes: ["Rotating quarterly categories — counted at half the $6k/yr cap"]),
        CandidateCard(
            stableId: "cand-bilt", name: "Bilt", issuer: "Bilt",
            isChaseIssued: false, annualFee: 0,
            valuationUSDPerUnit: 0.010, unitLabel: "pt",
            rates: [.dining: 3, .travel: 2], baseRate: 1,
            caps: [:],
            bestCategoryOnly: false, usableCredits: 0,
            creditsNote: "No annual credits",
            overlapExclusions: [:],
            notes: ["Rent rewards excluded — no rent category in your data"]),
        CandidateCard(
            stableId: "cand-freedom-flex", name: "Chase Freedom Flex", issuer: "Chase",
            isChaseIssued: true, annualFee: 0,
            valuationUSDPerUnit: 0.015, unitLabel: "UR",
            rates: [.dining: 5, .groceries: 5, .gas: 5, .shopping: 5, .entertainment: 5],
            baseRate: 1,
            caps: [.dining: (limit: 3_000, over: 1), .groceries: (limit: 3_000, over: 1),
                   .gas: (limit: 3_000, over: 1), .shopping: (limit: 3_000, over: 1),
                   .entertainment: (limit: 3_000, over: 1)],
            bestCategoryOnly: false, usableCredits: 0,
            creditsNote: "No annual credits",
            overlapExclusions: [.groceries: ["whole foods", "costco"]],
            notes: ["Rotating quarterly categories — counted at half the $6k/yr cap",
                    "UR valued at 1.5¢ via your Sapphire Reserve"]),
    ]

    // MARK: - Analysis

    /// Score every candidate against his current setup. Only positive-net
    /// cards are returned, ranked by net annual value.
    static func analyze(
        transactions: [BankTransaction],
        currentBestPct: [SpendCategory: Double],
        monthsCovered: Int,
        chaseCardsHeld: Int
    ) -> [CandidateVerdict] {
        let annualize = 12.0 / Double(max(monthsCovered, 1))
        let charges = transactions.filter { $0.isCharge && $0.category.isSpend }

        var verdicts: [CandidateVerdict] = []
        for candidate in candidates {
            var items: [CandidateLineItem] = []
            for (category, unitsPerDollar) in candidate.rates {
                let catYTD = charges
                    .filter { $0.category == category }
                    .reduce(0) { $0 + $1.absAmount }
                let excludedYTD = (candidate.overlapExclusions[category] ?? []).isEmpty ? 0 :
                    charges.filter { tx in
                        tx.category == category &&
                        (candidate.overlapExclusions[category] ?? []).contains(where: { tx.merchantNormalized.contains($0) })
                    }.reduce(0) { $0 + $1.absAmount }
                let eligibleAnnual = max(0, catYTD - excludedYTD) * annualize
                guard eligibleAnnual > 1 else { continue }

                // Candidate effective % with cap blending.
                var units = unitsPerDollar
                if let cap = candidate.caps[category], eligibleAnnual > cap.limit {
                    units = (cap.limit * unitsPerDollar + (eligibleAnnual - cap.limit) * cap.over) / eligibleAnnual
                }
                let candidatePct = units * candidate.valuationUSDPerUnit * 100
                let currentPct = (currentBestPct[category] ?? 0) * 100
                guard candidatePct > currentPct else { continue }
                items.append(CandidateLineItem(
                    category: category,
                    eligibleAnnualSpend: eligibleAnnual,
                    candidatePct: candidatePct,
                    currentBestPct: currentPct,
                    incrementalUSD: eligibleAnnual * (candidatePct - currentPct) / 100
                ))
            }

            if candidate.bestCategoryOnly {
                items = items.sorted { $0.incrementalUSD > $1.incrementalUSD }.prefix(1).map { $0 }
            }
            items.sort { $0.incrementalUSD > $1.incrementalUSD }

            let incremental = items.reduce(0) { $0 + $1.incrementalUSD }
            let net = incremental + candidate.usableCredits - candidate.annualFee
            guard net > 0 else { continue }

            var caution: String? = nil
            if candidate.isChaseIssued {
                caution = "You hold \(chaseCardsHeld) Chase cards. If 5+ personal cards were opened in the last 24 months you're likely over 5/24 and Chase approval is unlikely. (Business cards like your Ink cards don't use 5/24 slots.)"
            }

            verdicts.append(CandidateVerdict(
                candidate: candidate,
                lineItems: items,
                incrementalRewardsUSD: incremental,
                usableCreditsUSD: candidate.usableCredits,
                annualFeeUSD: candidate.annualFee,
                netAnnualUSD: net,
                chaseCaution: caution,
                assumptions: [
                    "Spend annualized from \(monthsCovered) month\(monthsCovered == 1 ? "" : "s") of statements (×\(String(format: "%.1f", annualize)))",
                    "1 \(candidate.unitLabel) ≈ \(String(format: "%.1f", candidate.valuationUSDPerUnit * 100))¢ (conservative)",
                    "You'd move this spend to the new card and keep everything else as-is",
                ]
            ))
        }
        return verdicts.sorted { $0.netAnnualUSD > $1.netAnnualUSD }
    }

    /// Annualized YTD spend by category (charges only), for the chart.
    static func annualizedSpendByCategory(_ txs: [BankTransaction], monthsCovered: Int) -> [(SpendCategory, Double)] {
        let annualize = 12.0 / Double(max(monthsCovered, 1))
        let grouped = Dictionary(grouping: txs.filter { $0.isCharge && $0.category.isSpend }, by: \.category)
        return grouped
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.absAmount } * annualize) }
            .sorted { $0.1 > $1.1 }
    }
}
