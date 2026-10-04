import Foundation

// MARK: - StatementParser (CSV)
//
// First-class statement import. Auto-detects common US bank/issuer CSV
// formats (Chase, Amex, Citi, Capital One, Discover) and falls back to a
// generic header scan. When nothing matches, the caller gets the detected
// header row plus a suggested ColumnMapping so the UI can offer a manual
// mapping picker instead of guessing.
//
// Contract: the parser NEVER invents transactions. Rows it cannot parse
// are reported in `warnings` with their line number and reason, and the
// caller surfaces them for review.

/// One parsed CSV row, before it becomes a BankTransaction.
struct ParsedTransaction: Sendable {
    var date: Date
    var description: String
    var amount: Double  // signed: negative = money out (charge)
    var confidence: Double
    var sourceLine: Int
}

/// Column roles for the manual-mapping fallback UI.
struct ColumnMapping: Sendable, Equatable {
    var date: Int
    var description: Int
    /// Single signed-amount column (nil when using debit/credit pair).
    var amount: Int?
    var debit: Int?
    var credit: Int?
    /// How charges are signed in the amount column.
    var negativeIsCharge: Bool

    var isUsable: Bool {
        amount != nil || (debit != nil && credit != nil)
    }
}

struct CSVParseResult: Sendable {
    var transactions: [ParsedTransaction]
    /// The mapping that was used (auto-detected or caller-supplied).
    var mapping: ColumnMapping?
    /// Issuer profile that matched, e.g. "Chase" — shown in the import
    /// preview so the user can sanity-check the sign convention.
    var detectedProfile: String?
    /// Header row as seen, for the manual-mapping UI.
    var headers: [String]
    /// Human-readable problems, e.g. "Line 14: unparseable date 'N/A' — skipped".
    var warnings: [String]
    /// True when no known format matched and no mapping was supplied.
    var needsManualMapping: Bool
}

/// A known issuer layout.
private struct CSVProfile: Sendable {
    var name: String
    /// Header names that must (case-insensitively, substring) appear.
    var requiredHeaders: [String]
    var date: String
    var description: String
    var amount: String?
    var debit: String?
    var credit: String?
    var negativeIsCharge: Bool
}

enum StatementParser {
    // MARK: Known profiles

    private static let profiles: [CSVProfile] = [
        CSVProfile(
            name: "Chase",
            requiredHeaders: ["transaction date", "post date", "description", "amount"],
            date: "transaction date", description: "description",
            amount: "amount", negativeIsCharge: true
        ),
        CSVProfile(
            name: "American Express",
            requiredHeaders: ["date", "description", "amount"],
            date: "date", description: "description",
            amount: "amount", negativeIsCharge: false
        ),
        CSVProfile(
            name: "Citi",
            requiredHeaders: ["date", "description", "debit", "credit"],
            date: "date", description: "description",
            debit: "debit", credit: "credit", negativeIsCharge: true
        ),
        CSVProfile(
            name: "Capital One",
            requiredHeaders: ["transaction date", "description", "debit", "credit"],
            date: "transaction date", description: "description",
            debit: "debit", credit: "credit", negativeIsCharge: true
        ),
        CSVProfile(
            name: "Discover",
            requiredHeaders: ["trans. date", "description", "amount"],
            date: "trans. date", description: "description",
            amount: "amount", negativeIsCharge: false
        ),
        CSVProfile(
            name: "Wells Fargo",
            requiredHeaders: ["date", "description", "amount"],
            date: "date", description: "description",
            amount: "amount", negativeIsCharge: true
        ),
    ]

    // MARK: Entry point

    /// Parse CSV text. Pass a manual `mapping` to skip auto-detection
    /// (used by the column-mapping fallback UI).
    static func parseCSV(_ text: String, mapping: ColumnMapping? = nil) -> CSVParseResult {
        let rows = splitRows(text)
        guard !rows.isEmpty else {
            return CSVParseResult(transactions: [], mapping: nil, detectedProfile: nil, headers: [],
                                  warnings: ["The file appears to be empty."], needsManualMapping: false)
        }

        // Find the header row: first row (within the first 10) that looks
        // like column names rather than data.
        var headerIndex: Int?
        for i in 0..<min(10, rows.count) {
            if looksLikeHeader(rows[i]) { headerIndex = i; break }
        }
        guard let hi = headerIndex else {
            return CSVParseResult(transactions: [], mapping: nil, detectedProfile: nil, headers: rows[0],
                                  warnings: ["No header row found in the first 10 lines."],
                                  needsManualMapping: true)
        }
        let headers = rows[hi]
        let dataRows = Array(rows.dropFirst(hi + 1))

        let resolved: (mapping: ColumnMapping, profile: String?)?
        if let mapping, mapping.isUsable {
            resolved = (mapping, nil)
        } else {
            resolved = detectMapping(headers: headers)
        }
        guard let (mapping, profile) = resolved else {
            return CSVParseResult(
                transactions: [], mapping: nil, detectedProfile: nil, headers: headers,
                warnings: ["This CSV layout wasn't recognized. Map the columns manually — nothing was imported."],
                needsManualMapping: true
            )
        }

        var out: [ParsedTransaction] = []
        var warnings: [String] = []
        for (offset, row) in dataRows.enumerated() {
            let line = hi + 2 + offset  // 1-based line number in the file
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
            do {
                if let tx = try parseRow(row, mapping: mapping, line: line) {
                    out.append(tx)
                }
            } catch let e as RowError {
                warnings.append("Line \(line): \(e.message) — skipped.")
            } catch {
                warnings.append("Line \(line): couldn't parse — skipped.")
            }
        }
        return CSVParseResult(transactions: out, mapping: mapping, detectedProfile: profile,
                              headers: headers, warnings: warnings, needsManualMapping: false)
    }

    /// Suggest a mapping for the manual column-picker UI.
    static func suggestedMapping(headers: [String]) -> ColumnMapping {
        let lower = headers.map { $0.lowercased() }
        func find(_ names: [String]) -> Int? {
            lower.firstIndex { h in names.contains { h.contains($0) } }
        }
        return ColumnMapping(
            date: find(["date"]) ?? 0,
            description: find(["description", "merchant", "memo", "payee"]) ?? 1,
            amount: find(["amount"]),
            debit: find(["debit", "withdrawal", "charge"]),
            credit: find(["credit", "deposit", "payment"]),
            negativeIsCharge: true
        )
    }

    // MARK: Detection

    private static func detectMapping(headers: [String]) -> (mapping: ColumnMapping, profile: String?)? {
        let lower = headers.map { $0.lowercased() }
        func col(_ name: String) -> Int? {
            lower.firstIndex { $0.contains(name) }
        }
        // Known issuer profiles first.
        for p in profiles where p.requiredHeaders.allSatisfy({ r in lower.contains { $0.contains(r) } }) {
            guard let d = col(p.date), let desc = col(p.description) else { continue }
            if let a = p.amount, let ai = col(a) {
                return (ColumnMapping(date: d, description: desc, amount: ai,
                                      negativeIsCharge: p.negativeIsCharge), p.name)
            }
            if let db = p.debit, let cr = p.credit,
               let di = col(db), let ci = col(cr) {
                return (ColumnMapping(date: d, description: desc, debit: di, credit: ci,
                                      negativeIsCharge: true), p.name)
            }
        }
        // Generic fallback: date + description + amount-ish columns.
        guard let d = lower.firstIndex(where: { $0.contains("date") }),
              let desc = lower.firstIndex(where: { $0.contains("descript") || $0.contains("merchant") || $0.contains("memo") || $0.contains("payee") })
        else { return nil }
        if let a = lower.firstIndex(where: { $0 == "amount" || $0.contains("amount") }) {
            return (ColumnMapping(date: d, description: desc, amount: a, negativeIsCharge: true), "Generic")
        }
        if let db = lower.firstIndex(where: { $0.contains("debit") || $0.contains("withdrawal") }),
           let cr = lower.firstIndex(where: { $0.contains("credit") || $0.contains("deposit") }) {
            return (ColumnMapping(date: d, description: desc, debit: db, credit: cr, negativeIsCharge: true), "Generic")
        }
        return nil
    }

    private static func looksLikeHeader(_ row: [String]) -> Bool {
        let joined = row.joined(separator: " ").lowercased()
        let hits = ["date", "description", "amount", "debit", "credit", "memo", "category", "balance"]
            .filter { joined.contains($0) }.count
        // Headers rarely parse as dates/amounts; data rows rarely name columns.
        return hits >= 2
    }

    // MARK: Row parsing

    private struct RowError: Error { var message: String }

    private static func parseRow(_ row: [String], mapping: ColumnMapping, line: Int) throws -> ParsedTransaction? {
        func cell(_ i: Int?) -> String {
            guard let i, i < row.count else { return "" }
            return row[i].trimmingCharacters(in: .whitespaces)
        }
        let dateString = cell(mapping.date)
        let desc = cell(mapping.description)
        guard !desc.isEmpty else { throw RowError(message: "empty description") }
        guard let date = parseDate(dateString) else {
            throw RowError(message: "unparseable date '\(dateString)'")
        }

        let amount: Double
        if let ai = mapping.amount {
            guard let v = parseAmount(cell(ai)) else {
                throw RowError(message: "unparseable amount '\(cell(ai))'")
            }
            // Normalize so negative = money out (charge).
            amount = mapping.negativeIsCharge ? v : -v
        } else if let di = mapping.debit, let ci = mapping.credit {
            let d = parseAmount(cell(di)) ?? 0
            let c = parseAmount(cell(ci)) ?? 0
            if d == 0 && c == 0 { throw RowError(message: "empty debit and credit") }
            amount = c - d  // debit = money out (negative), credit = money in
        } else {
            throw RowError(message: "no amount column mapped")
        }
        // Skip zero-amount rows (balance markers, etc.).
        guard amount != 0 else { return nil }
        return ParsedTransaction(date: date, description: desc, amount: amount,
                                 confidence: 0.95, sourceLine: line)
    }

    // MARK: Value parsing

    static func parseDate(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let formats = [
            "MM/dd/yyyy", "M/d/yyyy", "MM-dd-yyyy", "M-d-yyyy",
            "yyyy-MM-dd", "MM/dd/yy", "M/d/yy",
            "MMM d, yyyy", "MMMM d, yyyy",
        ]
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in formats {
            f.dateFormat = fmt
            if let d = f.date(from: t) { return d }
        }
        return nil
    }

    /// "$1,234.56" → 1234.56, "(123.45)" → -123.45, "" → nil.
    static func parseAmount(_ s: String) -> Double? {
        var t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        var parenNegative = false
        if t.hasPrefix("(") && t.hasSuffix(")") {
            parenNegative = true
            t = String(t.dropFirst().dropLast())
        }
        t = t.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let v = Double(t) else { return nil }
        return parenNegative ? -abs(v) : v
    }

    // MARK: CSV splitting (handles quoted commas and quoted newlines)

    static func splitRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var current: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        func endField() { current.append(field); field = "" }
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if inQuotes, i + 1 < chars.count, chars[i + 1] == "\"" {
                    field.append("\""); i += 1
                } else {
                    inQuotes.toggle()
                }
            } else if c == "," && !inQuotes {
                endField()
            } else if (c == "\n" || c == "\r") && !inQuotes {
                if c == "\r", i + 1 < chars.count, chars[i + 1] == "\n" { i += 1 }
                endField(); rows.append(current); current = []
            } else {
                field.append(c)
            }
            i += 1
        }
        endField()
        if !(current.count == 1 && current[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            rows.append(current)
        }
        return rows
    }
}
