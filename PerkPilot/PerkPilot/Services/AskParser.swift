import Foundation

// MARK: - AskParser
//
// Turns free text like "$200 restaurant spend, which card should I use?"
// into a structured query. Pure logic, no SwiftData — fully unit-testable.
//
// Strategy: find a dollar amount ($200, 200 dollars, "spend 200"), then a
// spend category / merchant keyword. If either is missing the caller asks
// ONE clarifying question instead of guessing.

/// Structured form of a "which card?" question.
struct AskQuery {
    var amount: Double?
    var category: SpendCategory?
    /// Normalized merchant keyword, e.g. "DOORDASH". Nil when only a
    /// category was mentioned.
    var merchant: String?
    /// Human-friendly merchant label for display, e.g. "DoorDash".
    var merchantDisplay: String?

    var isComplete: Bool { amount != nil && category != nil }

    /// The single clarifying question to ask, or nil when the query is
    /// complete (or so empty we can't even start).
    var clarifyingQuestion: String? {
        switch (amount, category) {
        case (nil, nil): return "How much are you spending, and on what?"
        case (nil, _): return "How much is the spend?"
        case (_, nil): return "What kind of spend is it — dining, groceries, gas, travel, gym…?"
        default: return nil
        }
    }

    /// Merge a fresh parse into a pending (incomplete) query. The newest
    /// parse wins for every field it mentions; the pending query fills the
    /// gaps. This handles both clarifying answers ("200") and topic
    /// changes ("actually, $300 for gas").
    func merged(with other: AskQuery) -> AskQuery {
        AskQuery(
            amount: other.amount ?? amount,
            category: other.category ?? category,
            merchant: other.merchant ?? merchant,
            merchantDisplay: other.merchantDisplay ?? merchantDisplay
        )
    }
}

enum AskParser {

    /// (keyword, category, normalized merchant, display name). Ordered —
    /// first substring hit wins, so specific merchants come first.
    private static let keywords: [(key: String, category: SpendCategory, merchant: String?, display: String?)] = [
        ("UBER EATS", .dining, "UBER EATS", "Uber Eats"),
        ("DOORDASH", .dining, "DOORDASH", "DoorDash"),
        ("GRUBHUB", .dining, "GRUBHUB", "Grubhub"),
        ("RESY", .dining, "RESY", "Resy"),
        ("OPENTABLE", .dining, "OPENTABLE", "OpenTable"),
        ("RESTAURANT", .dining, nil, nil),
        ("DINING", .dining, nil, nil),
        ("DINNER", .dining, nil, nil),
        ("LUNCH", .dining, nil, nil),
        ("FOOD", .dining, nil, nil),
        ("COFFEE", .dining, "STARBUCKS", "coffee"),
        ("WHOLE FOODS", .groceries, "WHOLE FOODS", "Whole Foods"),
        ("TRADER JOE", .groceries, "TRADER JOES", "Trader Joe's"),
        ("GROCER", .groceries, nil, nil),
        ("SUPERMARKET", .groceries, nil, nil),
        ("COSTCO", .groceries, "COSTCO", "Costco"),
        ("GAS STATION", .gas, nil, nil),
        ("FUEL", .gas, nil, nil),
        (" GAS ", .gas, nil, nil),
        ("SHELL", .gas, "SHELL", "Shell"),
        ("FLIGHT", .travel, nil, nil),
        ("HOTEL", .travel, nil, nil),
        ("AIRLINE", .travel, nil, nil),
        ("AIRBNB", .travel, "AIRBNB", "Airbnb"),
        ("RIDESHARE", .travel, nil, nil),
        ("TRAVEL", .travel, nil, nil),
        ("LYFT", .travel, "LYFT", "Lyft"),
        ("UBER", .travel, "UBER", "Uber"),
        ("EQUINOX", .health, "EQUINOX", "Equinox"),
        ("PELOTON", .health, "PELOTON", "Peloton"),
        ("FITNESS", .health, "GYM", "gym"),
        (" GYM ", .health, "GYM", "gym"),
        ("AMAZON", .shopping, "AMAZON", "Amazon"),
        ("SHOPPING", .shopping, nil, nil),
        ("APPLE STORE", .shopping, "APPLE", "Apple Store"),
        ("CLOTHES", .shopping, nil, nil),
        ("PHONE BILL", .bills, nil, nil),
        ("INTERNET", .bills, nil, nil),
        ("INSURANCE", .bills, nil, nil),
        ("UTILIT", .bills, nil, nil),
        ("NETFLIX", .entertainment, "NETFLIX", "Netflix"),
        ("SPOTIFY", .entertainment, "SPOTIFY", "Spotify"),
        ("CONCERT", .entertainment, nil, nil),
        ("MOVIE", .entertainment, nil, nil),
        ("SHOW", .entertainment, nil, nil),
    ]

    /// Parse free text into an AskQuery. Never throws; missing pieces are
    /// simply nil so the caller can ask a clarifying question.
    static func parse(_ text: String) -> AskQuery {
        let upper = " " + text.uppercased() + " "
        let amount = parseAmount(from: text)
        var category: SpendCategory?
        var merchant: String?
        var display: String?
        for entry in keywords where upper.contains(entry.key) {
            category = entry.category
            merchant = entry.merchant
            display = entry.display
            break
        }
        return AskQuery(amount: amount, category: category, merchant: merchant, merchantDisplay: display)
    }

    // MARK: - Amounts

    /// Matches (in priority order): $200 / 200$ / 200 dollars / 200 bucks /
    /// "spend 200" / "200 spend". Returns the earliest match.
    private static func parseAmount(from text: String) -> Double? {
        let patterns = [
            #"\$\s*([\d,]+(?:\.\d{1,2})?)"#,                       // $200, $ 200.50
            #"([\d,]+(?:\.\d{1,2})?)\s*\$\b"#,                     // 200$
            #"\b([\d,]+(?:\.\d{1,2})?)\s*(?:dollars?|bucks)\b"#,    // 200 dollars
            #"\b(?:spend|spending|bill|fee|cost|charge|purchase|payment|total|worth)\s+(?:of\s+|for\s+)?\$?\s*([\d,]+(?:\.\d{1,2})?)"#, // spend 200
            #"\$?\s*([\d,]+(?:\.\d{1,2})?)\s+(?:spend|spending|bill|fee|cost|worth)\b"#, // 200 spend
        ]
        var best: (range: Range<String.Index>, value: Double)?
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let ns = text as NSString
            for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) where m.numberOfRanges > 1 {
                let raw = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: "")
                guard let value = Double(raw), value > 0,
                      let range = Range(m.range, in: text) else { continue }
                if best == nil || range.lowerBound < best!.range.lowerBound {
                    best = (range, value)
                }
            }
        }
        return best?.value
    }
}
