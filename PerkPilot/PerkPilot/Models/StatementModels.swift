import Foundation
import SwiftData

// MARK: - SpendCategory
//
// Keyword-based spend buckets. `.payment` / `.income` are money-in or
// account transfers and are excluded from spend totals.

enum SpendCategory: String, Codable, CaseIterable, Sendable {
    case dining
    case groceries
    case gas
    case travel
    case shopping
    case bills
    case health
    case entertainment
    case other
    case income
    case payment

    var displayName: String {
        switch self {
        case .dining: return "Dining"
        case .groceries: return "Groceries"
        case .gas: return "Gas"
        case .travel: return "Travel"
        case .shopping: return "Shopping"
        case .bills: return "Bills & Utilities"
        case .health: return "Health"
        case .entertainment: return "Entertainment"
        case .other: return "Other"
        case .income: return "Income / Credits"
        case .payment: return "Payments"
        }
    }

    var systemImage: String {
        switch self {
        case .dining: return "fork.knife"
        case .groceries: return "cart"
        case .gas: return "fuelpump"
        case .travel: return "airplane"
        case .shopping: return "bag"
        case .bills: return "bolt"
        case .health: return "cross.case"
        case .entertainment: return "film"
        case .other: return "ellipsis.circle"
        case .income: return "arrow.down.circle"
        case .payment: return "arrow.left.arrow.right"
        }
    }

    /// Categories that count toward "spend" (money out on purchases).
    var isSpend: Bool {
        switch self {
        case .income, .payment: return false
        default: return true
        }
    }
}

// MARK: - StatementSource

enum StatementSource: String, Codable, CaseIterable, Sendable {
    case csv
    case pdf

    var displayName: String {
        switch self {
        case .csv: return "CSV"
        case .pdf: return "PDF"
        }
    }
}

// MARK: - CategorySource

/// How a transaction got its category: keyword engine vs. the user.
enum CategorySource: String, Codable, Sendable {
    case auto
    case manual
}

// MARK: - StatementDocument

/// One imported statement file: a card + a calendar month + the raw file.
/// The file itself is never persisted — only parsed rows. Raw statement
/// data lives in this on-device SwiftData store and is never uploaded.
@Model
final class StatementDocument {
    @Attribute(.unique) var stableId: String
    var cardStableId: String
    /// Monthly period key, e.g. "2026-10".
    var periodKey: String
    var fileName: String
    var importedAt: Date
    var sourceRaw: String
    var transactionCount: Int
    var lowConfidenceCount: Int
    var note: String

    @Relationship(deleteRule: .cascade, inverse: \BankTransaction.document)
    var transactions: [BankTransaction]

    init(
        cardStableId: String,
        periodKey: String,
        fileName: String,
        source: StatementSource,
        importedAt: Date = Date(),
        transactionCount: Int = 0,
        lowConfidenceCount: Int = 0,
        note: String = ""
    ) {
        self.stableId = UUID().uuidString
        self.cardStableId = cardStableId
        self.periodKey = periodKey
        self.fileName = fileName
        self.importedAt = importedAt
        self.sourceRaw = source.rawValue
        self.transactionCount = transactionCount
        self.lowConfidenceCount = lowConfidenceCount
        self.note = note
        self.transactions = []
    }

    var source: StatementSource { StatementSource(rawValue: sourceRaw) ?? .csv }
}

// MARK: - MerchantCategoryOverride

/// A learned per-merchant category: when the user recategorizes a
/// transaction, future imports of the same normalized merchant reuse it.
@Model
final class MerchantCategoryOverride {
    @Attribute(.unique) var merchantNormalized: String
    var categoryRaw: String
    var updatedAt: Date

    init(merchantNormalized: String, category: SpendCategory, updatedAt: Date = Date()) {
        self.merchantNormalized = merchantNormalized
        self.categoryRaw = category.rawValue
        self.updatedAt = updatedAt
    }

    var category: SpendCategory {
        get { SpendCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}

// MARK: - BankTransaction

/// One parsed statement line. Amount is signed: negative = money out
/// (a charge), positive = money in (payment, refund, credit).
@Model
final class BankTransaction {
    @Attribute(.unique) var stableId: String
    var cardStableId: String
    var document: StatementDocument?
    var date: Date
    var merchantRaw: String
    var merchantNormalized: String
    /// Signed amount. Negative = charge.
    var amount: Double
    var categoryRaw: String
    var categorySourceRaw: String
    /// 0…1 parser/categorizer confidence. < 0.7 is flagged for review.
    var confidence: Double
    var isFlaggedForReview: Bool

    init(
        cardStableId: String,
        date: Date,
        merchantRaw: String,
        amount: Double,
        category: SpendCategory,
        categorySource: CategorySource = .auto,
        confidence: Double = 1.0,
        isFlaggedForReview: Bool = false
    ) {
        self.stableId = UUID().uuidString
        self.cardStableId = cardStableId
        self.date = date
        self.merchantRaw = merchantRaw
        self.merchantNormalized = CategoryEngine.normalizeMerchant(merchantRaw)
        self.amount = amount
        self.categoryRaw = category.rawValue
        self.categorySourceRaw = categorySource.rawValue
        self.confidence = confidence
        self.isFlaggedForReview = isFlaggedForReview
    }

    var category: SpendCategory {
        get { SpendCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var categorySource: CategorySource {
        get { CategorySource(rawValue: categorySourceRaw) ?? .auto }
        set { categorySourceRaw = newValue.rawValue }
    }

    /// Money out (a purchase). Refunds/payments are not spend.
    var isCharge: Bool { amount < 0 }
    var absAmount: Double { abs(amount) }
}
