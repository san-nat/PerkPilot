import Foundation
import SwiftData

// MARK: - TransactionStore
//
// The single doorway for statement data: import, search, aggregates,
// recategorization, deletion. Everything stays in the on-device SwiftData
// store — this type has no networking and never will; that is the whole
// point of the privacy guarantee.

enum TransactionStore {
    // MARK: Import

    /// Persist parsed rows under a new StatementDocument. Normalizes
    /// merchants, applies learned overrides, and auto-categorizes.
    @discardableResult
    static func importParsed(
        _ parsed: [ParsedTransaction],
        cardStableId: String,
        periodKey: String,
        fileName: String,
        source: StatementSource,
        context: ModelContext
    ) -> StatementDocument {
        let overrides = fetchOverrides(context: context)
        let doc = StatementDocument(
            cardStableId: cardStableId,
            periodKey: periodKey,
            fileName: fileName,
            source: source
        )
        var low = 0
        for p in parsed {
            let normalized = CategoryEngine.normalizeMerchant(p.description)
            let override = overrides[normalized]
            let (category, catConf) = CategoryEngine.categorize(
                normalizedMerchant: normalized,
                override: override?.category
            )
            let confidence = min(p.confidence, catConf)
            let flagged = confidence < 0.7
            if flagged { low += 1 }
            let tx = BankTransaction(
                cardStableId: cardStableId,
                date: p.date,
                merchantRaw: p.description,
                amount: p.amount,
                category: category,
                categorySource: override == nil ? .auto : .manual,
                confidence: confidence,
                isFlaggedForReview: flagged
            )
            tx.document = doc
            doc.transactions.append(tx)
            context.insert(tx)
        }
        doc.transactionCount = parsed.count
        doc.lowConfidenceCount = low
        context.insert(doc)
        try? context.save()
        return doc
    }

    // MARK: Fetch

    static func transactions(
        cardStableId: String? = nil,
        periodKey: String? = nil,
        context: ModelContext
    ) -> [BankTransaction] {
        // Simple predicate on the card, then in-memory period filtering:
        // optional-chaining through the document relationship inside a
        // #Predicate is unreliable across SwiftData backends.
        let predicate: Predicate<BankTransaction>? = cardStableId.map { id in
            #Predicate { $0.cardStableId == id }
        }
        var descriptor = FetchDescriptor<BankTransaction>(
            predicate: predicate, sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 5000
        let all = (try? context.fetch(descriptor)) ?? []
        guard let periodKey else { return all }
        return all.filter { $0.document?.periodKey == periodKey }
    }

    static func documents(cardStableId: String? = nil, context: ModelContext) -> [StatementDocument] {
        let predicate: Predicate<StatementDocument>? = cardStableId.map { id in
            #Predicate { $0.cardStableId == id }
        }
        let descriptor = FetchDescriptor<StatementDocument>(
            predicate: predicate, sortBy: [SortDescriptor(\.periodKey, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: Search

    struct SearchFilters: Sendable {
        var query: String = ""
        var cardStableId: String? = nil
        var from: Date? = nil
        var to: Date? = nil
        var category: SpendCategory? = nil
        var flaggedOnly: Bool = false
    }

    /// Full-text search across merchant text and amounts, with filters.
    /// Pure in-memory over a bounded fetch — statements are small.
    static func search(_ filters: SearchFilters, context: ModelContext) -> [BankTransaction] {
        let all = transactions(cardStableId: filters.cardStableId, context: context)
        let q = filters.query.trimmingCharacters(in: .whitespaces).lowercased()
        return all.filter { tx in
            if filters.flaggedOnly, !tx.isFlaggedForReview { return false }
            if let cat = filters.category, tx.category != cat { return false }
            if let from = filters.from, tx.date < from { return false }
            if let to = filters.to, tx.date >= to { return false }
            guard !q.isEmpty else { return true }
            if tx.merchantRaw.lowercased().contains(q) { return true }
            if tx.merchantNormalized.lowercased().contains(q) { return true }
            // Amount search: "15", "15.00", "$15"
            let digits = q.filter { $0.isNumber || $0 == "." }
            if !digits.isEmpty, let v = Double(digits), abs(tx.absAmount - v) < 0.005 { return true }
            return false
        }
    }

    // MARK: Aggregates

    /// Spend totals by category for a card+month. Payments/income excluded.
    static func monthlySpendByCategory(
        cardStableId: String? = nil,
        periodKey: String,
        context: ModelContext
    ) -> [(category: SpendCategory, total: Double)] {
        let txs = transactions(cardStableId: cardStableId, periodKey: periodKey, context: context)
            .filter { $0.isCharge && $0.category.isSpend }
        let grouped = Dictionary(grouping: txs, by: \.category)
        return grouped
            .map { (category: $0.key, total: $0.value.reduce(0) { $0 + $1.absAmount }) }
            .sorted { $0.total > $1.total }
    }

    static func monthlySpendTotal(
        cardStableId: String? = nil,
        periodKey: String,
        context: ModelContext
    ) -> Double {
        monthlySpendByCategory(cardStableId: cardStableId, periodKey: periodKey, context: context)
            .reduce(0) { $0 + $1.total }
    }

    // MARK: Recategorize (learns the merchant override)

    static func recategorize(_ tx: BankTransaction, to category: SpendCategory, context: ModelContext) {
        tx.category = category
        tx.categorySource = .manual
        let key = tx.merchantNormalized
        let descriptor = FetchDescriptor<MerchantCategoryOverride>(
            predicate: #Predicate { $0.merchantNormalized == key }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.category = category
            existing.updatedAt = Date()
        } else {
            context.insert(MerchantCategoryOverride(merchantNormalized: key, category: category))
        }
        try? context.save()
    }

    static func fetchOverrides(context: ModelContext) -> [String: MerchantCategoryOverride] {
        let all = (try? context.fetch(FetchDescriptor<MerchantCategoryOverride>())) ?? []
        return Dictionary(uniqueKeysWithValues: all.map { ($0.merchantNormalized, $0) })
    }

    // MARK: Delete

    static func deleteDocument(_ doc: StatementDocument, context: ModelContext) {
        context.delete(doc)  // transactions cascade via the relationship
        try? context.save()
    }

    static func deleteAllStatements(context: ModelContext) {
        try? context.delete(model: StatementDocument.self)
        try? context.delete(model: BankTransaction.self)
        try? context.delete(model: MerchantCategoryOverride.self)
        try? context.save()
    }
}
