import Foundation
import PDFKit

// MARK: - PDFStatementParser (best-effort)
//
// PDF statements vary wildly by issuer, so this is deliberately humble:
// PDFKit text extraction plus line-item heuristics. Every parsed row gets
// a confidence score, and anything below 0.7 is flagged for user review.
// The import UI shows the low-confidence share up front so the user can
// decide whether to trust it or use CSV instead.

struct PDFParseResult: Sendable {
    var transactions: [ParsedTransaction]
    var warnings: [String]
    /// Share of rows below the review threshold (0…1).
    var lowConfidenceShare: Double
}

enum PDFStatementParser {
    /// Extract raw text from a PDF statement.
    static func extractText(from data: Data) -> String? {
        guard let doc = PDFDocument(data: data) else { return nil }
        var out = ""
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            out += page.string ?? ""
            out += "\n"
        }
        return out.isEmpty ? nil : out
    }

    /// Heuristic line-item extraction. Expects lines shaped like:
    ///   10/04  UBER TRIP HELP.UBER.COM        $15.00
    /// i.e. a leading date and a trailing amount.
    static func parseLineItems(_ text: String) -> PDFParseResult {
        // Date at line start: MM/DD or MM/DD/YY(YY), separators / - .
        let datePattern = #"^(\d{1,2}[/\-.]\d{1,2}(?:[/\-.]\d{2,4})?)\s+(.*)$"#
        // Amount at line end: optional $, commas, optional parens.
        let amountPattern = #"\(?\$?[\d,]+\.\d{2}\)?\s*$"#
        let dateRE = try? NSRegularExpression(pattern: datePattern)
        let amountRE = try? NSRegularExpression(pattern: amountPattern)

        var out: [ParsedTransaction] = []
        var warnings: [String] = []
        var lineNo = 0
        for rawLine in text.components(separatedBy: .newlines) {
            lineNo += 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let range = NSRange(line.startIndex..., in: line)
            guard let dm = dateRE?.firstMatch(in: line, range: range),
                  dm.numberOfRanges >= 3,
                  let dateRange = Range(dm.range(at: 1), in: line),
                  let restRange = Range(dm.range(at: 2), in: line)
            else { continue }  // Not a transaction line; skip silently.

            let dateString = String(line[dateRange])
            let rest = String(line[restRange])
            let restNS = NSRange(rest.startIndex..., in: rest)
            guard let am = amountRE?.firstMatch(in: rest, range: restNS),
                  let amtRange = Range(am.range, in: rest)
            else {
                warnings.append("Line \(lineNo): date found but no trailing amount — skipped.")
                continue
            }
            let amountString = String(rest[amtRange]).trimmingCharacters(in: .whitespaces)
            var desc = rest.replacingCharacters(in: amtRange, with: "")
                .trimmingCharacters(in: .whitespaces)
            // Drop reference numbers glued to the description's tail.
            desc = desc.replacingOccurrences(of: #"\s{2,}\S+$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)

            guard let date = StatementParser.parseDate(normalizeYear(dateString)),
                  let rawAmount = StatementParser.parseAmount(amountString),
                  !desc.isEmpty
            else {
                warnings.append("Line \(lineNo): couldn't parse date/amount — skipped.")
                continue
            }

            // PDF statements rarely declare sign convention; assume the
            // common case (positive numbers = charges) and mark it.
            // The import preview tells the user to flip if it looks wrong.
            let confidence = strictLine(line) ? 0.8 : 0.6
            out.append(ParsedTransaction(
                date: date, description: desc,
                amount: -abs(rawAmount),  // assume charge; user confirms in preview
                confidence: confidence, sourceLine: lineNo
            ))
        }

        let low = out.filter { $0.confidence < 0.7 }.count
        let share = out.isEmpty ? 0 : Double(low) / Double(out.count)
        if out.isEmpty {
            warnings.append("No transaction lines recognized. PDF layouts vary — CSV import is more reliable.")
        }
        return PDFParseResult(transactions: out, warnings: warnings, lowConfidenceShare: share)
    }

    // MARK: Helpers

    /// "10/04" → "10/04/<current year>" so the date parser can cope.
    private static func normalizeYear(_ s: String) -> String {
        let parts = s.split { "/-.".contains($0) }
        guard parts.count == 2 else { return s }
        let year = Calendar.current.component(.year, from: Date())
        return "\(s)/\(year)"
    }

    /// A "strict" line has exactly one amount-like token and a clean shape.
    private static func strictLine(_ line: String) -> Bool {
        let tokens = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let amountTokens = tokens.filter {
            $0.range(of: #"^\(?\$?[\d,]+\.\d{2}\)?$"#, options: .regularExpression) != nil
        }
        return amountTokens.count == 1 && tokens.count >= 3
    }
}
