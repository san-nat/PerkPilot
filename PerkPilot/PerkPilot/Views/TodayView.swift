import SwiftUI
import SwiftData

/// The default launch view: every recurring credit for the current period,
/// grouped by cadence, with one-tap checkmarks.
struct TodayView: View {
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<CardItem> { !$0.isArchived }, sort: \CardItem.canonicalName)
    private var cards: [CardItem]
    @Query private var completions: [CompletionRecord]
    @Query private var mutes: [MutedReward]

    private let now = Date()
    private let cadences: [Cadence] = [.monthly, .quarterly, .semiannual, .annual]

    private var completedKeys: Set<String> {
        Set(completions.map(\.lookupKey))
    }

    private var mutedIds: Set<String> {
        Set(mutes.map(\.benefitStableId))
    }

    /// (card, benefit) pairs due for a cadence this period, excluding muted.
    private struct TaskRow: Identifiable {
        var card: CardItem
        var benefit: BenefitItem
        var id: String { benefit.stableId }
    }

    private func tasks(for cadence: Cadence) -> [TaskRow] {
        cards.flatMap { card in
            card.benefits
                .filter { $0.cadence == cadence && !mutedIds.contains($0.stableId) }
                .sorted { $0.name < $1.name }
                .map { TaskRow(card: card, benefit: $0) }
        }
    }

    private var allTasks: [(task: TaskRow, periodKey: String)] {
        cadences.flatMap { cadence in
            guard let key = RecurrenceEngine.periodKey(cadence: cadence, date: now) else { return [] }
            return tasks(for: cadence).map { (task: $0, periodKey: key) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                progressSection
                ForEach(cadences, id: \.self) { cadence in
                    periodSection(cadence)
                }
            }
            .navigationTitle("Today")
        }
    }

    private var progressSection: some View {
        let total = allTasks.count
        let done = allTasks.filter { completedKeys.contains("\($0.task.benefit.stableId)|\($0.periodKey)") }.count
        return Section {
            HStack {
                VStack(alignment: .leading) {
                    Text("\(done) of \(total) credits used")
                        .font(.headline)
                    Text("Resets next period — use it or lose it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ProgressView(value: total > 0 ? Double(done) / Double(total) : 0)
                    .progressViewStyle(.circular)
            }
        }
    }

    @ViewBuilder
    private func periodSection(_ cadence: Cadence) -> some View {
        if let key = RecurrenceEngine.periodKey(cadence: cadence, date: now),
           let label = RecurrenceEngine.periodLabel(cadence: cadence, date: now)
        {
            let rows = tasks(for: cadence)
            let done = rows.filter { completedKeys.contains("\($0.benefit.stableId)|\(key)") }.count
            Section("\(cadence.displayName) — \(label) (\(done)/\(rows.count))") {
                ForEach(rows) { row in
                    ChecklistRow(
                        cardName: row.card.canonicalName,
                        benefit: row.benefit,
                        isDone: completedKeys.contains("\(row.benefit.stableId)|\(key)"),
                        onToggle: { toggle(row.benefit, periodKey: key) }
                    )
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

struct ChecklistRow: View {
    var cardName: String
    var benefit: BenefitItem
    var isDone: Bool
    var onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(benefit.name)
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? .secondary : .primary)
                Text(benefit.amountDisplay)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(cardName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                if benefit.enrollmentRequired {
                    Text("Enrollment required")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(benefit.name), \(benefit.amountDisplay)")
        .accessibilityHint(isDone ? "Marked used. Activate to unmark." : "Activate to mark used.")
    }
}

#Preview {
    TodayView()
        .modelContainer(for: [
            CardItem.self,
            BenefitItem.self,
            TipItem.self,
            CompletionRecord.self,
            MutedReward.self,
        ], inMemory: true)
}
