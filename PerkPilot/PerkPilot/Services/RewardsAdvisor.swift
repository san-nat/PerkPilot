import Foundation

// MARK: - RewardsAdvisor
//
// Best-card-for-this-purchase engine. Pure logic over a bundled earn-rate
// table for Santosh's 12 cards — no SwiftData, no networking, fully
// unit-testable. Every number is an estimate: point valuations are
// conservative and shown next to each verdict, never hidden.

/// USD value of one reward unit.
struct RewardValuation {
    /// e.g. 0.015 = 1 UR point ≈ 1.5¢ via the Sapphire Reserve travel portal.
    var usdPerUnit: Double
    var unitLabel: String   // "UR", "MR", "mi", "$"
    var basisNote: String   // shown in UI
}

struct EarnCap {
    /// Bonus rate applies to the first $annualLimit of yearly spend here.
    var annualLimit: Double
    var overRate: Double    // units per $ after the cap
    var note: String
}

struct MerchantBoost {
    /// Lowercase substrings matched against the normalized merchant.
    var keywords: [String]
    var rate: Double        // units per $
    var note: String
}

struct EarnProfile {
    var cardStableId: String
    var displayName: String
    var shortName: String
    var valuation: RewardValuation
    /// Units per $1 for uncategorized spend.
    var baseRate: Double
    var rates: [SpendCategory: Double]
    var caps: [SpendCategory: EarnCap]
    var boosts: [MerchantBoost]
    var notes: [String]
}

enum RewardsAdvisor {
    // MARK: Valuations (conservative, displayed in UI)

    static let ur  = RewardValuation(usdPerUnit: 0.015, unitLabel: "UR", basisNote: "via Sapphire Reserve portal")
    static let mr  = RewardValuation(usdPerUnit: 0.010, unitLabel: "MR", basisNote: "conservative baseline")
    static let skyMiles = RewardValuation(usdPerUnit: 0.010, unitLabel: "mi", basisNote: "conservative")
    static let rapidRewards = RewardValuation(usdPerUnit: 0.012, unitLabel: "RR", basisNote: "conservative")
    static let cash = RewardValuation(usdPerUnit: 1.0, unitLabel: "$", basisNote: "face value")
    static let samsCash = RewardValuation(usdPerUnit: 1.0, unitLabel: "$", basisNote: "Sam's Cash")

    // MARK: Earn table — his 12 cards (2026 terms)

    static let profiles: [String: EarnProfile] = {
        var p: [String: EarnProfile] = [:]

        p["amex-platinum"] = EarnProfile(
            cardStableId: "amex-platinum", displayName: "Amex Platinum", shortName: "Platinum",
            valuation: mr, baseRate: 1, rates: [.travel: 1],
            caps: [:],
            boosts: [MerchantBoost(
                keywords: ["delta", "united", "american airlines", "southwest", "jetblue", "alaska air", "british airways", "air france", "klm", "lufthansa"],
                rate: 5, note: "5x on flights booked direct or via Amex Travel")],
            notes: ["5x flights booked direct or via Amex Travel", "5x prepaid hotels via Amex Travel"])

        p["chase-sapphire-reserve"] = EarnProfile(
            cardStableId: "chase-sapphire-reserve", displayName: "Sapphire Reserve", shortName: "Reserve",
            valuation: ur, baseRate: 1, rates: [.dining: 3, .travel: 3],
            caps: [:], boosts: [], notes: [])

        p["chase-sapphire-preferred"] = EarnProfile(
            cardStableId: "chase-sapphire-preferred", displayName: "Sapphire Preferred", shortName: "Preferred",
            valuation: ur, baseRate: 1,
            rates: [.dining: 3, .groceries: 3, .travel: 2, .entertainment: 3],
            caps: [:], boosts: [],
            notes: ["3x groceries = online groceries", "3x entertainment = streaming services"])

        p["chase-ink-business-preferred"] = EarnProfile(
            cardStableId: "chase-ink-business-preferred", displayName: "Ink Business Preferred", shortName: "Ink Pref",
            valuation: ur, baseRate: 1,
            rates: [.bills: 3, .shopping: 3],
            caps: [
                .bills: EarnCap(annualLimit: 150_000, overRate: 1, note: "internet, cable & phone — first $150k/yr"),
                .shopping: EarnCap(annualLimit: 150_000, overRate: 1, note: "shipping & advertising — first $150k/yr"),
            ],
            boosts: [], notes: [])

        p["delta-skymiles-reserve"] = EarnProfile(
            cardStableId: "delta-skymiles-reserve", displayName: "Delta Reserve", shortName: "Delta",
            valuation: skyMiles, baseRate: 1, rates: [.travel: 1],
            caps: [:],
            boosts: [MerchantBoost(keywords: ["delta"], rate: 3, note: "3x on Delta purchases")],
            notes: [])

        p["robinhood-gold"] = EarnProfile(
            cardStableId: "robinhood-gold", displayName: "Robinhood Gold", shortName: "Robinhood",
            valuation: cash, baseRate: 0.03, rates: [:],
            caps: [:], boosts: [], notes: ["Flat 3% cash back, no caps"])

        p["costco-anywhere-visa"] = EarnProfile(
            cardStableId: "costco-anywhere-visa", displayName: "Costco Anywhere Visa", shortName: "Costco",
            valuation: cash, baseRate: 0.01,
            rates: [.gas: 0.05, .dining: 0.03, .travel: 0.03],
            caps: [.gas: EarnCap(annualLimit: 7_000, overRate: 0.01, note: "5% gas on first $7k/yr, then 1%")],
            boosts: [MerchantBoost(keywords: ["costco"], rate: 0.02, note: "2% at Costco warehouses")],
            notes: [])

        p["chase-prime-visa"] = EarnProfile(
            cardStableId: "chase-prime-visa", displayName: "Prime Visa", shortName: "Prime",
            valuation: cash, baseRate: 0.01,
            rates: [.dining: 0.02, .gas: 0.02],
            caps: [:],
            boosts: [
                MerchantBoost(keywords: ["amazon"], rate: 0.05, note: "5% at Amazon.com"),
                MerchantBoost(keywords: ["whole foods"], rate: 0.05, note: "5% at Whole Foods Market"),
            ],
            notes: [])

        p["sams-club-mastercard"] = EarnProfile(
            cardStableId: "sams-club-mastercard", displayName: "Sam's Club Mastercard", shortName: "Sam's Club",
            valuation: samsCash, baseRate: 0.01,
            rates: [.gas: 0.05, .dining: 0.03],
            caps: [.gas: EarnCap(annualLimit: 6_000, overRate: 0.01, note: "5% gas on first $6k/yr, then 1%")],
            boosts: [], notes: [])

        p["southwest-premier"] = EarnProfile(
            cardStableId: "southwest-premier", displayName: "Southwest Premier", shortName: "Southwest",
            valuation: rapidRewards, baseRate: 1,
            rates: [.groceries: 2, .dining: 2],
            caps: [
                .groceries: EarnCap(annualLimit: 8_000, overRate: 1, note: "first $8k/anniversary yr, shared with dining"),
                .dining: EarnCap(annualLimit: 8_000, overRate: 1, note: "first $8k/anniversary yr, shared with groceries"),
            ],
            boosts: [], notes: [])

        p["chase-freedom-unlimited"] = EarnProfile(
            cardStableId: "chase-freedom-unlimited", displayName: "Freedom Unlimited", shortName: "Freedom",
            valuation: ur, baseRate: 1.5, rates: [:],
            caps: [:], boosts: [], notes: ["Flat 1.5x UR everywhere"])

        p["chase-ink-business-unlimited"] = EarnProfile(
            cardStableId: "chase-ink-business-unlimited", displayName: "Ink Business Unlimited", shortName: "Ink Unltd",
            valuation: ur, baseRate: 1.5, rates: [:],
            caps: [:], boosts: [], notes: ["Flat 1.5x UR everywhere"])

        return p
    }()

    // MARK: - Ranking

    struct RankedCard {
        var cardStableId: String
        var displayName: String
        var shortName: String
        var rewardUSD: Double
        /// Reward as a percent of the purchase (e.g. 4.5 = 4.5%).
        var effectivePct: Double
        var rateLabel: String   // "3x UR ≈ 4.5%" or "3%"
        var why: String
        var capHit: Bool
    }

    /// YTD charge spend per card per category (money out only).
    static func ytdSpendByCardCategory(_ txs: [BankTransaction], now: Date = Date()) -> [String: [SpendCategory: Double]] {
        let year = Calendar.current.component(.year, from: now)
        var out: [String: [SpendCategory: Double]] = [:]
        for tx in txs where tx.isCharge && tx.category.isSpend {
            guard Calendar.current.component(.year, from: tx.date) == year else { continue }
            out[tx.cardStableId, default: [:]][tx.category, default: 0] += tx.absAmount
        }
        return out
    }

    /// Effective USD reward per $1 for one card/category/merchant.
    static func effectiveRateUSD(
        _ profile: EarnProfile,
        category: SpendCategory,
        merchantNormalized: String,
        ytdCategorySpend: Double
    ) -> (usdPerDollar: Double, rateLabel: String, why: String, capHit: Bool) {
        var rate = profile.rates[category] ?? profile.baseRate
        var why = profile.rates[category] != nil
            ? "\(formatRate(rate, profile.valuation)) on \(category.displayName.lowercased())"
            : "Base \(formatRate(profile.baseRate, profile.valuation))"
        var capHit = false

        for boost in profile.boosts {
            if boost.keywords.contains(where: { merchantNormalized.contains($0) }) {
                rate = boost.rate
                why = boost.note
                break
            }
        }

        if let cap = profile.caps[category], ytdCategorySpend >= cap.annualLimit {
            rate = cap.overRate
            capHit = true
            why += " — cap reached (\(cap.note))"
        }

        return (rate * profile.valuation.usdPerUnit, formatRate(rate, profile.valuation), why, capHit)
    }

    /// His current best effective % per category (caps respected via YTD).
    static func currentBestPctByCategory(ytd: [String: [SpendCategory: Double]]) -> [SpendCategory: Double] {
        var best: [SpendCategory: Double] = [:]
        for cat in SpendCategory.allCases where cat.isSpend {
            var m = 0.0
            for (_, profile) in profiles {
                let spent = ytd[profile.cardStableId]?[cat] ?? 0
                let r = effectiveRateUSD(profile, category: cat, merchantNormalized: "", ytdCategorySpend: spent)
                m = max(m, r.usdPerDollar)
            }
            best[cat] = m
        }
        return best
    }

    /// Rank his cards for one purchase. Respects annual caps via YTD spend.
    static func bestCard(
        merchant: String,
        amount: Double,
        category: SpendCategory,
        ytd: [String: [SpendCategory: Double]]
    ) -> [RankedCard] {
        guard amount > 0 else { return [] }
        let normalized = CategoryEngine.normalizeMerchant(merchant)
        return profiles.values
            .sorted { $0.cardStableId < $1.cardStableId }
            .map { profile in
                let spent = ytd[profile.cardStableId]?[category] ?? 0
                let r = effectiveRateUSD(profile, category: category, merchantNormalized: normalized, ytdCategorySpend: spent)
                return RankedCard(
                    cardStableId: profile.cardStableId,
                    displayName: profile.displayName,
                    shortName: profile.shortName,
                    rewardUSD: r.usdPerDollar * amount,
                    effectivePct: r.usdPerDollar * 100,
                    rateLabel: r.rateLabel,
                    why: r.why,
                    capHit: r.capHit
                )
            }
            .sorted { $0.rewardUSD > $1.rewardUSD }
    }

    // MARK: - Formatting

    static func formatRate(_ rate: Double, _ valuation: RewardValuation) -> String {
        if valuation.unitLabel == "$" {
            let pct = rate * 100
            return pct.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(pct))%"
                : String(format: "%.1f%%", pct)
        }
        let pct = rate * valuation.usdPerUnit * 100
        let r = rate.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(rate))" : String(format: "%.1f", rate)
        let p = pct.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(pct))" : String(format: "%.1f", pct)
        return "\(r)x \(valuation.unitLabel) ≈ \(p)%"
    }
}
