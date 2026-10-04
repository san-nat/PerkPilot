import Foundation

// MARK: - CategoryEngine
//
// Pure keyword categorizer. Precedence:
//   1. Per-merchant learned override (user recategorized before)
//   2. Keyword rules (first match wins, ordered by specificity)
//   3. .other
//
// Nothing here touches SwiftData — the caller passes overrides in, which
// keeps the engine unit-testable and reusable by future features
// (e.g. the "best card for this purchase" advisor).

enum CategoryEngine {
    /// Normalize a raw merchant string for matching and override keys:
    /// uppercase, strip store numbers (#1234), punctuation, and extra spaces.
    static func normalizeMerchant(_ raw: String) -> String {
        var s = raw.uppercased()
        s = s.replacingOccurrences(of: #"#\d+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[^A-Z0-9 &']"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// (keyword, category) — ordered; first substring hit wins.
    private static let rules: [(String, SpendCategory)] = [
        // Payments / transfers first — they must not count as spend.
        ("AUTOPAY", .payment), ("PAYMENT", .payment), ("TRANSFER", .payment),
        ("VENMO CASHOUT", .payment), ("ZELLE", .payment),
        // Income / credits
        ("REFUND", .income), ("CASHBACK", .income), ("REWARD", .income),
        ("INTEREST", .income), ("CREDIT ADJUSTMENT", .income),

        // Dining
        ("DOORDASH", .dining), ("UBER EATS", .dining), ("GRUBHUB", .dining),
        ("SEAMLESS", .dining), ("POSTMATES", .dining), ("INSTACART", .groceries),
        ("STARBUCKS", .dining), ("CHIPOTLE", .dining), ("MCDONALD", .dining),
        ("RESTAURANT", .dining), ("PIZZA", .dining), ("SUSHI", .dining),
        ("CAFE", .dining), ("COFFEE", .dining), ("DINER", .dining),
        ("TACO", .dining), ("BURGER", .dining), ("BBQ", .dining),
        ("RESY", .dining), ("OPENTABLE", .dining), ("EAT", .dining),

        // Groceries
        ("WHOLE FOODS", .groceries), ("WHOLEFDS", .groceries),
        ("TRADER JOE", .groceries), ("KROGER", .groceries),
        ("MEIJER", .groceries), ("COSTCO", .groceries),
        ("SAM'S CLUB", .groceries), ("SAMS CLUB", .groceries),
        ("WALMART", .groceries), ("TARGET", .groceries),
        ("GROCER", .groceries), ("MARKET", .groceries),

        // Gas
        ("SHELL", .gas), ("EXXON", .gas), ("MOBIL", .gas),
        ("CHEVRON", .gas), ("BP ", .gas), ("SPEEDWAY", .gas),
        ("MARATHON", .gas), ("SUNOCO", .gas), ("FUEL", .gas),
        ("GAS STATION", .gas),

        // Travel
        ("DELTA", .travel), ("UNITED", .travel), ("AMERICAN AIR", .travel),
        ("SOUTHWEST", .travel), ("JETBLUE", .travel), ("ALASKA AIR", .travel),
        ("AIRBNB", .travel), ("MARRIOTT", .travel), ("HYATT", .travel),
        ("HILTON", .travel), ("IHG", .travel), ("HOTEL", .travel),
        ("UBER", .travel), ("LYFT", .travel), ("PARKING", .travel),
        ("TOLL", .travel), ("AIRLINE", .travel), ("EXPEDIA", .travel),
        ("BOOKING COM", .travel), ("AMTRAK", .travel), ("HERTZ", .travel),
        ("ENTERPRISE", .travel), ("AVIS", .travel),

        // Shopping
        ("AMAZON", .shopping), ("BEST BUY", .shopping), ("APPLE", .shopping),
        ("NIKE", .shopping), ("LULULEMON", .shopping), ("SAKS", .shopping),
        ("NORDSTROM", .shopping), ("MACY", .shopping), ("COSTCO COM", .shopping),
        ("ETSY", .shopping), ("EBAY", .shopping), ("IKEA", .shopping),
        ("HOME DEPOT", .shopping), ("LOWE", .shopping), ("STORE", .shopping),
        ("SHOP", .shopping),

        // Bills & utilities
        ("COMCAST", .bills), ("XFINITY", .bills), ("AT&T", .bills),
        ("T-MOBILE", .bills), ("TMOBILE", .bills), ("VERIZON", .bills),
        ("DTE", .bills), ("CONSUMERS ENERGY", .bills), ("ELECTRIC", .bills),
        ("WATER", .bills), ("INSURANCE", .bills), ("GEICO", .bills),
        ("PROGRESSIVE", .bills), ("CITY OF", .bills), ("UTILITY", .bills),
        ("APPLE COM BILL", .bills), ("ICLOUD", .bills),

        // Health
        ("PHARMACY", .health), ("CVS", .health), ("WALGREENS", .health),
        ("DENTIST", .health), ("MEDICAL", .health), ("HOSPITAL", .health),
        ("DOCTOR", .health), ("GYM", .health), ("EQUINOX", .health),
        ("PELOTON", .health),

        // Entertainment
        ("NETFLIX", .entertainment), ("SPOTIFY", .entertainment),
        ("AMC", .entertainment), ("THEATER", .entertainment),
        ("STUBHUB", .entertainment), ("TICKETMASTER", .entertainment),
        ("DISNEY", .entertainment), ("HULU", .entertainment),
        ("STEAM", .entertainment), ("GOLF", .entertainment),
    ]

    /// Categorize a normalized merchant. Returns category + confidence.
    /// - Parameter override: a learned per-merchant category (always wins).
    static func categorize(
        normalizedMerchant: String,
        override: SpendCategory? = nil
    ) -> (category: SpendCategory, confidence: Double) {
        if let override { return (override, 1.0) }
        // Specific multi-word hits that a shorter keyword would shadow.
        if normalizedMerchant.contains("APPLE COM BILL") || normalizedMerchant.contains("ICLOUD") {
            return (.bills, 0.9)
        }
        if normalizedMerchant.contains("UBER EATS") {
            return (.dining, 0.9)
        }
        for (keyword, category) in rules {
            if normalizedMerchant.contains(keyword) {
                return (category, 0.85)
            }
        }
        return (.other, 0.4)
    }

    /// Convenience: raw merchant straight to a category.
    static func categorize(rawMerchant: String, override: SpendCategory? = nil)
        -> (category: SpendCategory, confidence: Double)
    {
        categorize(normalizedMerchant: normalizeMerchant(rawMerchant), override: override)
    }
}
