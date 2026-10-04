import SwiftUI
import SwiftData

// MARK: - RewardsCheckView
//
// "Did I actually get my credits?" For each recurring benefit, match the
// card's imported statement transactions with the RewardMatcher heuristic
// and show likely-received / not-detected / no-statements. Manual confirm
// writes a normal CompletionRecord — the matcher never checks anything
// off by itself. UI copy is explicit: heuristic, not bank-verified.

struct RewardsCheckView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<CardItem> { !$0.isArchived }, sort: \CardItem.canonicalName)
    private var cards: [CardItem]
    @Query private var completions: [CompletionRecord]
    @Query private var mutes: [MutedReward]

    @State private var periodKey: String = RecurrenceEngine.periodKey(cadence: .monthly, date: Date()) ?? "2026-10"
    @State private var cardStableId: String? = nil

    private var completedKeys: Set<String> { Set(completions.map(\.lookupKey)) }
    private var mutedIds: Set<String> { Set(mutes.map(\.benefitStableId)) }

    struct CheckRow: Identifiable {
        var card: CardItem
        var benefit: BenefitItem
        var status: RewardMatchStatus
        var id: String { benefit.stableId }
    }

    private var rows: [CheckRow] {
        let scope = cardStableId.flatMap { id in cards.first { $0.stableId == id } }
            .map { [$0] } ?? cards
        var out: [CheckRow] = []
        for card in scope {
            let txs = TransactionStore.transactions(
                cardStableId: card.stableId, periodKey: periodKey, context: context
            )
            for benefit in card.benefits
                .filter({ $0.cadence == .monthly && !mutedIds.contains($0.stableId) })
                .sorted(by: { $0.name < $1.name })
            {
                let key = "\(benefit.stableId)|\(periodKey)"
                let status = RewardMatcher.evaluate(
                    benefit: benefit,
                    transactions: txs,
                    periodKey: periodKey,
                    alreadyCompleted: completedKeys.contains(key)
                )
                out.append(CheckRow(card: card, benefit: benefit, status: status))
            }
        }
        return out
    }

    private var monthLabel: String {
        let parts = periodKey.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return periodKey }
        var comps = DateComponents(); comps.year = y; comps.month = m; comps.day = 1
        guard let d = Calendar.current.date(from: comps) else { return periodKey }
        return d.formatted(.dateTime.month(.wide).year())
    }

    var body: some View {
        NavigationStack {
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

                heuristicBanner

                if rows.isEmpty {
                    ContentUnavailableView(
                        "No monthly credits",
                        systemImage: "checkmark.shield",
                        description: Text("No monthly recurring credits on these cards to check.")
                    )
                } else {
                    List(rows) { row in
                        RewardCheckRow(
                            row: row,
                            monthLabel: monthLabel,
                            onConfirm: { confirm(row) },
                            onUnmark: { unmark(row) }
                        )
                    }
                    .listStyle(.plain)
                }
            }
            .background(PPTheme.pageBackground)
            .navigationTitle("Rewards check")
        }
    }

    private var heuristicBanner: some View {
        Label(
            "Heuristic matching — not bank-verified. Confirm manually before trusting it.",
            systemImage: "info.circle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, PPTheme.screenPad)
        .padding(.vertical, 6)
    }

    private func confirm(_ row: CheckRow) {
        let key = "\(row.benefit.stableId)|\(periodKey)"
        guard !completedKeys.contains(key) else { return }
        context.insert(CompletionRecord(benefitStableId: row.benefit.stableId, periodKey: periodKey))
        try? context.save()
    }

    private func unmark(_ row: CheckRow) {
        let key = "\(row.benefit.stableId)|\(periodKey)"
        if let existing = completions.first(where: { $0.lookupKey == key }) {
            context.delete(existing)
            try? context.save()
        }
    }
}

private struct RewardCheckRow: View {
    var row: RewardsCheckView.CheckRow
    var monthLabel: String
    var onConfirm: () -> Void
    var onUnmark: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                statusIcon
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.benefit.name).font(.headline).lineLimit(2)
                    Text("\(row.benefit.amountDisplay) · \(row.card.canonicalName)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    statusNote
                }
                Spacer()
            }
            actionButtons
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch row.status {
        case .likelyReceived(let conf, _, _):
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(conf == .high ? PPTheme.success : PPTheme.gold)
                .font(.title3)
        case .notDetected:
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.orange).font(.title3)
        case .noStatements:
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.secondary).font(.title3)
        case .manuallyConfirmed:
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(PPTheme.success).font(.title3)
        }
    }

    @ViewBuilder
    private var statusNote: some View {
        switch row.status {
        case .likelyReceived(let conf, let tx, let note):
            Text("Likely received · \(conf.displayName)")
                .font(.caption).fontWeight(.semibold).foregroundStyle(PPTheme.success)
            Text(note).font(.caption).foregroundStyle(.secondary)
            Text("\(tx.merchantRaw) · \(tx.date.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
        case .notDetected(let note):
            Text("Not detected").font(.caption).fontWeight(.semibold).foregroundStyle(.orange)
            Text(note).font(.caption).foregroundStyle(.secondary)
        case .noStatements:
            Text("No statement imported for \(monthLabel) on this card.")
                .font(.caption).foregroundStyle(.secondary)
        case .manuallyConfirmed:
            Text("Confirmed by you").font(.caption).fontWeight(.semibold).foregroundStyle(PPTheme.success)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch row.status {
        case .manuallyConfirmed:
            Button("Mark not used", role: .destructive, action: onUnmark)
                .font(.callout)
        case .noStatements:
            EmptyView()
        default:
            Button("Confirm as used") { onConfirm() }
                .font(.callout).fontWeight(.semibold)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(PPTheme.gold.opacity(0.16))
                .foregroundStyle(PPTheme.gold)
                .clipShape(Capsule())
        }
    }
}

#Preview {
    RewardsCheckView()
        .modelContainer(for: [
            CardItem.self, BenefitItem.self, TipItem.self,
            CompletionRecord.self, MutedReward.self,
            StatementDocument.self, BankTransaction.self, MerchantCategoryOverride.self,
        ], inMemory: true)
}
