import SwiftUI
import SwiftData

// MARK: - StatementsView
//
// The Statements hub: imported documents, full-text transaction search,
// and per-card / per-month spend breakdowns. Deep-linkable to a tab via
// `initialSection` (used by the Today bento tile).

enum StatementsSection: String, CaseIterable {
    case documents
    case search
    case spend

    var title: String {
        switch self {
        case .documents: return "Documents"
        case .search: return "Search"
        case .spend: return "Spend"
        }
    }

    var systemImage: String {
        switch self {
        case .documents: return "doc.stack"
        case .search: return "magnifyingglass"
        case .spend: return "chart.pie"
        }
    }
}

struct StatementsView: View {
    var initialSection: StatementsSection = .documents

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<CardItem> { !$0.isArchived }, sort: \CardItem.canonicalName)
    private var cards: [CardItem]

    @State private var section: StatementsSection = .documents
    @State private var showingImport = false
    @State private var showingDeleteConfirm: StatementDocument?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $section) {
                    ForEach(StatementsSection.allCases, id: \.self) { s in
                        Label(s.title, systemImage: s.systemImage).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, PPTheme.screenPad)
                .padding(.vertical, 8)

                switch section {
                case .documents: documentsList
                case .search: TransactionSearchView()
                case .spend: SpendBreakdownView()
                }
            }
            .background(PPTheme.pageBackground)
            .navigationTitle("Statements")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingImport = true } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .sheet(isPresented: $showingImport) {
                StatementImportView()
            }
            .confirmationDialog(
                "Delete this statement?",
                isPresented: Binding(
                    get: { showingDeleteConfirm != nil },
                    set: { if !$0 { showingDeleteConfirm = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete statement", role: .destructive) {
                    if let doc = showingDeleteConfirm {
                        TransactionStore.deleteDocument(doc, context: context)
                    }
                    showingDeleteConfirm = nil
                }
                Button("Cancel", role: .cancel) { showingDeleteConfirm = nil }
            } message: {
                Text("Its transactions are deleted too. This can't be undone.")
            }
            .onAppear { section = initialSection }
        }
    }

    // MARK: Documents

    @Query(sort: \StatementDocument.periodKey, order: .reverse)
    private var documents: [StatementDocument]

    private var documentsList: some View {
        Group {
            if documents.isEmpty {
                ContentUnavailableView(
                    "No statements yet",
                    systemImage: "doc.text",
                    description: Text("Import a CSV or PDF statement to see spend by category and check which credits you actually used.")
                )
            } else {
                List {
                    Section {
                        Label(
                            "Statements stay on this iPhone — parsed here, never uploaded.",
                            systemImage: "lock.shield"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    ForEach(documents, id: \.stableId) { doc in
                        DocumentRow(
                            doc: doc,
                            cardName: cards.first { $0.stableId == doc.cardStableId }?.canonicalName ?? "Unknown card",
                            onDelete: { showingDeleteConfirm = doc }
                        )
                    }
                }
            }
        }
    }
}

private struct DocumentRow: View {
    var doc: StatementDocument
    var cardName: String
    var onDelete: () -> Void

    private func monthLabel(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return key }
        var comps = DateComponents(); comps.year = y; comps.month = m; comps.day = 1
        guard let d = Calendar.current.date(from: comps) else { return key }
        return d.formatted(.dateTime.month(.wide).year())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: doc.source == .pdf ? "doc.richtext" : "tablecells")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(cardName).font(.headline).lineLimit(1)
                Text("\(monthLabel(doc.periodKey)) · \(doc.fileName)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 8) {
                    Text("\(doc.transactionCount) transactions")
                        .font(.caption2).foregroundStyle(.tertiary)
                    if doc.lowConfidenceCount > 0 {
                        Label("\(doc.lowConfidenceCount) flagged", systemImage: "exclamationmark.triangle")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(cardName), \(monthLabel(doc.periodKey)), \(doc.transactionCount) transactions")
    }
}

// MARK: - TransactionSearchView

struct TransactionSearchView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<CardItem> { !$0.isArchived }, sort: \CardItem.canonicalName)
    private var cards: [CardItem]

    @State private var query = ""
    @State private var cardStableId: String? = nil
    @State private var category: SpendCategory? = nil
    @State private var flaggedOnly = false

    private var results: [BankTransaction] {
        TransactionStore.search(
            .init(query: query, cardStableId: cardStableId, category: category, flaggedOnly: flaggedOnly),
            context: context
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Card", selection: $cardStableId) {
                    Text("All cards").tag(nil as String?)
                    ForEach(cards, id: \.stableId) { card in
                        Text(card.canonicalName).tag(card.stableId as String?)
                    }
                }
                .pickerStyle(.menu)
                Picker("Category", selection: $category) {
                    Text("All").tag(nil as SpendCategory?)
                    ForEach(SpendCategory.allCases, id: \.self) { c in
                        Text(c.displayName).tag(c as SpendCategory?)
                    }
                }
                .pickerStyle(.menu)
                Toggle("Flagged", isOn: $flaggedOnly)
                    .toggleStyle(.button)
                    .font(.caption)
            }
            .padding(.horizontal, PPTheme.screenPad)
            .padding(.vertical, 6)

            if results.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "Search transactions" : "No matches",
                    systemImage: "magnifyingglass",
                    description: Text(query.isEmpty
                        ? "Search by merchant name or amount across every imported statement."
                        : "Try a different merchant, amount, or filter.")
                )
            } else {
                List(results.prefix(200), id: \.stableId) { tx in
                    NavigationLink(destination: TransactionDetailView(tx: tx)) {
                        TransactionRow(tx: tx, cardName: cards.first { $0.stableId == tx.cardStableId }?.canonicalName)
                    }
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $query, prompt: "Merchant or amount")
    }
}

// MARK: - TransactionRow / TransactionDetailView

struct TransactionRow: View {
    var tx: BankTransaction
    var cardName: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tx.category.systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.merchantRaw).font(.callout).lineLimit(1)
                HStack(spacing: 6) {
                    Text(tx.date, format: .dateTime.month(.abbreviated).day())
                    if let cardName { Text("· \(cardName)").lineLimit(1) }
                    Text("· \(tx.category.displayName)")
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(tx.absAmount, format: .currency(code: "USD"))
                    .font(.callout).monospacedDigit()
                    .foregroundStyle(tx.isCharge ? .primary : .green)
                if tx.isFlaggedForReview {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct TransactionDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var tx: BankTransaction

    var body: some View {
        List {
            Section("Transaction") {
                LabeledContent("Merchant", value: tx.merchantRaw)
                LabeledContent("Date", value: tx.date.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Amount", value: tx.absAmount.formatted(.currency(code: "USD")))
                LabeledContent("Type", value: tx.isCharge ? "Charge" : "Payment / credit")
            }
            Section("Category") {
                Picker("Category", selection: Binding(
                    get: { tx.category },
                    set: { TransactionStore.recategorize(tx, to: $0, context: context) }
                )) {
                    ForEach(SpendCategory.allCases, id: \.self) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                Text(tx.categorySource == .manual
                     ? "You set this category — future imports of this merchant will remember it."
                     : "Auto-categorized by keyword. Change it and PerkPilot learns this merchant.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if tx.isFlaggedForReview {
                Section {
                    Label("Flagged for review — the parser had low confidence in this row. Check the amount and merchant against your statement.", systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - SpendBreakdownView

struct SpendBreakdownView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<CardItem> { !$0.isArchived }, sort: \CardItem.canonicalName)
    private var cards: [CardItem]

    @State private var cardStableId: String? = nil
    @State private var periodKey: String = RecurrenceEngine.periodKey(cadence: .monthly, date: Date()) ?? "2026-10"

    private var breakdown: [(category: SpendCategory, total: Double)] {
        TransactionStore.monthlySpendByCategory(
            cardStableId: cardStableId, periodKey: periodKey, context: context
        )
    }

    private var total: Double { breakdown.reduce(0) { $0 + $1.total } }
    private var maxTotal: Double { breakdown.first?.total ?? 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Card", selection: $cardStableId) {
                    Text("All cards").tag(nil as String?)
                    ForEach(cards, id: \.stableId) { card in
                        Text(card.canonicalName).tag(card.stableId as String?)
                    }
                }
                .pickerStyle(.menu)
                MonthPicker(periodKey: $periodKey)
            }
            .padding(.horizontal, PPTheme.screenPad)
            .padding(.vertical, 6)

            if breakdown.isEmpty {
                ContentUnavailableView(
                    "No spend data",
                    systemImage: "chart.pie",
                    description: Text("Import a statement for this card and month to see the category breakdown.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: PPTheme.gridSpacing) {
                        BentoTile {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Total spend")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Text(total, format: .currency(code: "USD"))
                                    .font(.system(size: 34, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                Text("\(breakdown.count) categories")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, PPTheme.screenPad)

                        ForEach(breakdown, id: \.category) { entry in
                            HStack(spacing: 12) {
                                Image(systemName: entry.category.systemImage)
                                    .foregroundStyle(.secondary).frame(width: 24)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(entry.category.displayName).font(.callout)
                                        Spacer()
                                        Text(entry.total, format: .currency(code: "USD"))
                                            .font(.callout).monospacedDigit()
                                    }
                                    GeometryReader { geo in
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(PPTheme.gold.opacity(0.85))
                                            .frame(width: geo.size.width * CGFloat(entry.total / maxTotal), height: 6)
                                    }
                                    .frame(height: 6)
                                }
                            }
                            .padding(12)
                            .background(PPTheme.tileBackground,
                                        in: RoundedRectangle(cornerRadius: PPTheme.cardRadius, style: .continuous))
                            .padding(.horizontal, PPTheme.screenPad)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
    }
}

#Preview {
    StatementsView()
        .modelContainer(for: [
            CardItem.self, BenefitItem.self, TipItem.self,
            CompletionRecord.self, MutedReward.self,
            StatementDocument.self, BankTransaction.self, MerchantCategoryOverride.self,
        ], inMemory: true)
}
