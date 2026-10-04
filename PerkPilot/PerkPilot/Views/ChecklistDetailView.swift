import SwiftUI
import SwiftData

// MARK: - Shared checklist math
//
// One implementation used by both the Today bento dashboard and the
// drill-in detail views, so counts and checkmarks can never disagree.

/// A (card, benefit) pair due this period.
struct TaskRow: Identifiable {
    var card: CardItem
    var benefit: BenefitItem
    var id: String { benefit.stableId }
}

enum ChecklistEngine {
    /// Recurring benefits for a cadence across active cards, excluding muted.
    static func tasks(cards: [CardItem], mutedIds: Set<String>, cadence: Cadence) -> [TaskRow] {
        cards.flatMap { card in
            card.benefits
                .filter { $0.cadence == cadence && !mutedIds.contains($0.stableId) }
                .sorted { $0.name < $1.name }
                .map { TaskRow(card: card, benefit: $0) }
        }
    }

    static func lookupKey(_ row: TaskRow, periodKey: String) -> String {
        "\(row.benefit.stableId)|\(periodKey)"
    }

    static func doneCount(rows: [TaskRow], periodKey: String, completedKeys: Set<String>) -> Int {
        rows.filter { completedKeys.contains(lookupKey($0, periodKey: periodKey)) }.count
    }
}

// MARK: - ChecklistDetailView

/// Drill-in checklist for a single cadence (or all of them), reached by
/// tapping a bento tile on the Today dashboard.
struct ChecklistDetailView: View {
    /// nil = every recurring cadence.
    var cadence: Cadence?

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<CardItem> { !$0.isArchived }, sort: \CardItem.canonicalName)
    private var cards: [CardItem]
    @Query private var completions: [CompletionRecord]
    @Query private var mutes: [MutedReward]

    private let now = Date()

    private var cadences: [Cadence] {
        cadence.map { [$0] } ?? [.monthly, .quarterly, .semiannual, .annual]
    }

    private var completedKeys: Set<String> { Set(completions.map(\.lookupKey)) }
    private var mutedIds: Set<String> { Set(mutes.map(\.benefitStableId)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PPTheme.gridSpacing) {
                ForEach(cadences, id: \.self) { cadence in
                    periodSection(cadence)
                }
            }
            .padding(.horizontal, PPTheme.screenPad)
            .padding(.vertical, 12)
        }
        .background(PPTheme.pageBackground)
        .navigationTitle(cadence?.displayName ?? "All credits")
        .navigationBarTitleDisplayMode(.large)
    }

    @ViewBuilder
    private func periodSection(_ cadence: Cadence) -> some View {
        if let key = RecurrenceEngine.periodKey(cadence: cadence, date: now),
           let label = RecurrenceEngine.periodLabel(cadence: cadence, date: now)
        {
            let rows = ChecklistEngine.tasks(cards: cards, mutedIds: mutedIds, cadence: cadence)
            let done = ChecklistEngine.doneCount(rows: rows, periodKey: key, completedKeys: completedKeys)
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(cadence.displayName)
                            .font(.headline)
                        Text("· \(label)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(done)/\(rows.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 4)

                    VStack(spacing: 8) {
                        ForEach(rows) { row in
                            ChecklistRow(
                                cardName: row.card.canonicalName,
                                benefit: row.benefit,
                                isDone: completedKeys.contains(ChecklistEngine.lookupKey(row, periodKey: key)),
                                onToggle: { toggle(row.benefit, periodKey: key) }
                            )
                            .padding(12)
                            .background(
                                PPTheme.tileBackground,
                                in: RoundedRectangle(cornerRadius: PPTheme.cardRadius, style: .continuous)
                            )
                        }
                    }
                }
            }
        }
    }

    private func toggle(_ benefit: BenefitItem, periodKey: String) {
        let key = "\(benefit.stableId)|\(periodKey)"
        if let existing = completions.first(where: { $0.lookupKey == key }) {
            context.delete(existing)
        } else {
            context.insert(CompletionRecord(benefitStableId: benefit.stableId, periodKey: periodKey))
        }
    }
}

#Preview {
    ChecklistDetailView(cadence: .monthly)
        .modelContainer(for: [
            CardItem.self,
            BenefitItem.self,
            TipItem.self,
            CompletionRecord.self,
            MutedReward.self,
        ], inMemory: true)
}
