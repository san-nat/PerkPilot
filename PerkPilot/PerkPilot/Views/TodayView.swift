import SwiftUI
import SwiftData

/// Bento-grid dashboard: an asymmetrical grid of summary tiles up top
/// (each tappable into its detail), with the full checklist below.
/// "Frictionless wealth management" — the state of every credit at a glance.
struct TodayView: View {
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<CardItem> { !$0.isArchived }, sort: \CardItem.canonicalName)
    private var cards: [CardItem]
    @Query private var completions: [CompletionRecord]
    @Query private var mutes: [MutedReward]

    private let now = Date()
    private let cadences: [Cadence] = [.monthly, .quarterly, .semiannual, .annual]

    private var completedKeys: Set<String> { Set(completions.map(\.lookupKey)) }
    private var mutedIds: Set<String> { Set(mutes.map(\.benefitStableId)) }

    private var activeBenefits: [BenefitItem] {
        cards.flatMap(\.benefits).filter { !mutedIds.contains($0.stableId) }
    }

    private func rows(for cadence: Cadence) -> [TaskRow] {
        ChecklistEngine.tasks(cards: cards, mutedIds: mutedIds, cadence: cadence)
    }

    private func key(for cadence: Cadence) -> String? {
        RecurrenceEngine.periodKey(cadence: cadence, date: now)
    }

    private func doneCount(for cadence: Cadence) -> Int {
        guard let key = key(for: cadence) else { return 0 }
        return ChecklistEngine.doneCount(rows: rows(for: cadence), periodKey: key, completedKeys: completedKeys)
    }

    private var totalRows: Int { cadences.reduce(0) { $0 + rows(for: $1).count } }
    private var totalDone: Int { cadences.reduce(0) { $0 + doneCount(for: $1) } }

    private var loungeCount: Int {
        activeBenefits.filter { $0.name.localizedCaseInsensitiveContains("lounge") }.count
    }

    private var gemCount: Int {
        activeBenefits.filter(\.lesserKnown).count
    }

    private var currentMonthKey: String {
        RecurrenceEngine.periodKey(cadence: .monthly, date: now) ?? ""
    }

    private var monthSpend: Double {
        TransactionStore.monthlySpendTotal(periodKey: currentMonthKey, context: context)
    }

    private var topSpendCategory: String {
        TransactionStore.monthlySpendByCategory(periodKey: currentMonthKey, context: context)
            .first?.category.displayName ?? "No data"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PPTheme.gridSpacing) {
                    bentoGrid
                    checklistSections
                }
                .padding(.horizontal, PPTheme.screenPad)
                .padding(.vertical, 12)
            }
            .background(PPTheme.pageBackground)
            .navigationTitle("Today")
        }
    }

    // MARK: - Bento grid

    private var bentoGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: PPTheme.gridSpacing),
                      GridItem(.flexible(), spacing: PPTheme.gridSpacing)],
            spacing: PPTheme.gridSpacing
        ) {
            expiringTile
                .gridCellColumns(2)
            quarterTile
            creditsTile
            spendTile
            loungeTile
            gemsTile
            walletTile
            mutedTile
            advisorTile
        }
    }

    /// "You're leaving ~$X/yr on the table" — top new-card idea, if any.
    private var topNewCardNet: Double? {
        let charges = TransactionStore.transactions(context: context).filter { $0.isCharge && $0.category.isSpend }
        guard !charges.isEmpty else { return nil }
        let docs = TransactionStore.documents(context: context)
        let months = max(1, Set(docs.map(\.periodKey)).count)
        let ytd = RewardsAdvisor.ytdSpendByCardCategory(charges)
        let currentBest = RewardsAdvisor.currentBestPctByCategory(ytd: ytd)
        let chaseCount = cards.filter { $0.issuer == "Chase" }.count
        let verdicts = PortfolioAnalyzer.analyze(
            transactions: charges, currentBestPct: currentBest,
            monthsCovered: months, chaseCardsHeld: chaseCount)
        guard let top = verdicts.first, top.netAnnualUSD >= 25 else { return nil }
        return top.netAnnualUSD
    }

    /// Missed Rewards Audit hero: "You're leaving $X on the table" from
    /// actuals (missed earn + expired credits). Falls back to the new-card
    /// ideas tile when there are no statements to audit yet.
    private var auditReport: AuditReport? {
        let charges = TransactionStore.transactions(context: context)
        guard !charges.isEmpty else { return nil }
        let r = SpendAuditService.audit(
            transactions: charges, cards: cards,
            completions: completions, mutes: mutes,
            documents: TransactionStore.documents(context: context)
        )
        return r.analyzedCount > 0 ? r : nil
    }

    private var advisorTile: some View {
        NavigationLink(destination: auditDestination) {
            BentoTile {
                if let r = auditReport, r.totalMissedUSD >= 1 {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "chart.line.downtrend.xaxis")
                            .font(.title3)
                            .foregroundStyle(PPTheme.gold)
                            .accessibilityHidden(true)
                        Spacer(minLength: 2)
                        Text(r.totalMissedUSD.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(PPTheme.gold)
                            .monospacedDigit()
                        Text("Left on the table")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Missed rewards this year — tap for the audit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } else if let r = auditReport {
                    BentoStat(
                        title: "Audit",
                        value: "Nothing left",
                        subtitle: "Every dollar went to its optimal card",
                        systemImage: "checkmark.seal.fill",
                        tint: PPTheme.success
                    )
                } else if let net = topNewCardNet {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "wand.and.stars")
                            .font(.title3)
                            .foregroundStyle(PPTheme.gold)
                            .accessibilityHidden(true)
                        Spacer(minLength: 2)
                        Text("~\(Int(net))")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                        Text("Left on the table")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("A new card could earn this/yr")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } else {
                    BentoStat(
                        title: "Advisor",
                        value: "Which card?",
                        subtitle: "Best card per purchase + new card ideas",
                        systemImage: "wand.and.stars",
                        tint: PPTheme.gold
                    )
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var auditDestination: some View {
        if auditReport != nil {
            AuditView()
        } else {
            AdvisorView(initialMode: .newIdeas)
        }
    }

    private var expiringTile: some View {
        let total = rows(for: .monthly).count
        let done = doneCount(for: .monthly)
        let remaining = total - done
        let label = RecurrenceEngine.periodLabel(cadence: .monthly, date: now) ?? ""
        return NavigationLink(destination: ChecklistDetailView(cadence: .monthly)) {
            BentoTile(minHeight: 148) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Expiring this month", systemImage: "alarm.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text("\(remaining) left")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    ProgressView(value: total > 0 ? Double(done) / Double(total) : 0)
                        .tint(PPTheme.gold)
                    Text("\(done) of \(total) used · resets after \(label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var quarterTile: some View {
        let total = rows(for: .quarterly).count
        let done = doneCount(for: .quarterly)
        return NavigationLink(destination: ChecklistDetailView(cadence: .quarterly)) {
            BentoTile {
                BentoStat(
                    title: "This quarter",
                    value: "\(done)/\(total)",
                    subtitle: "Quarterly credits used",
                    systemImage: "calendar",
                    tint: .blue
                )
            }
        }
        .buttonStyle(.plain)
    }

    private var creditsTile: some View {
        NavigationLink(destination: ChecklistDetailView(cadence: nil)) {
            BentoTile {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(PPTheme.gold)
                        .accessibilityHidden(true)
                    Spacer(minLength: 2)
                    HStack(alignment: .bottom, spacing: 10) {
                        Text("\(totalDone)/\(totalRows)")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                        ProgressView(value: totalRows > 0 ? Double(totalDone) / Double(totalRows) : 0)
                            .progressViewStyle(.circular)
                            .tint(PPTheme.gold)
                            .scaleEffect(0.8)
                    }
                    Text("Credits used")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("All recurring credits")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var spendTile: some View {
        NavigationLink(destination: StatementsView(initialSection: .spend)) {
            BentoTile {
                BentoStat(
                    title: monthSpend > 0 ? "Spent this month" : "Month spend",
                    value: monthSpend > 0 ? monthSpend.formatted(.currency(code: "USD")) : "—",
                    subtitle: monthSpend > 0 ? "Top: \(topSpendCategory)" : "Import a statement",
                    systemImage: "chart.pie.fill",
                    tint: .teal
                )
            }
        }
        .buttonStyle(.plain)
    }

    private var loungeTile: some View {
        NavigationLink(destination: BenefitsLibraryView(searchText: "lounge")) {
            BentoTile {
                BentoStat(
                    title: "Lounge access",
                    value: "\(loungeCount)",
                    subtitle: "Lounge perks in your wallet",
                    systemImage: "airplane",
                    tint: .indigo
                )
            }
        }
        .buttonStyle(.plain)
    }

    private var gemsTile: some View {
        NavigationLink(destination: BenefitsLibraryView(lesserKnownOnly: true)) {
            BentoTile {
                BentoStat(
                    title: "Hidden gems",
                    value: "\(gemCount)",
                    subtitle: "Lesser-known tricks & perks",
                    systemImage: "lightbulb.fill",
                    tint: .yellow
                )
            }
        }
        .buttonStyle(.plain)
    }

    private var walletTile: some View {
        NavigationLink(destination: CardsView()) {
            BentoTile {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: -14) {
                        ForEach(cards.prefix(3), id: \.stableId) { card in
                            MetalCardView(card: card, compact: true)
                                .frame(width: 64)
                        }
                    }
                    .accessibilityHidden(true)
                    Spacer(minLength: 2)
                    Text("\(cards.count)")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    Text("Cards in wallet")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Tap to manage")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var mutedTile: some View {
        NavigationLink(destination: BenefitsLibraryView(mutedOnly: true)) {
            BentoTile {
                BentoStat(
                    title: "Muted",
                    value: "\(mutes.count)",
                    subtitle: "Rewards you've hidden",
                    systemImage: "eye.slash",
                    tint: .gray
                )
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Checklist (one-tap checkmarks, unchanged behavior)

    private var checklistSections: some View {
        VStack(alignment: .leading, spacing: PPTheme.gridSpacing) {
            Text("Checklist")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal, 4)
                .padding(.top, 8)
            ForEach(cadences, id: \.self) { cadence in
                periodSection(cadence)
            }
        }
    }

    @ViewBuilder
    private func periodSection(_ cadence: Cadence) -> some View {
        if let key = key(for: cadence),
           let label = RecurrenceEngine.periodLabel(cadence: cadence, date: now)
        {
            let rows = rows(for: cadence)
            if !rows.isEmpty {
                let done = ChecklistEngine.doneCount(rows: rows, periodKey: key, completedKeys: completedKeys)
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
                    .foregroundStyle(isDone ? PPTheme.success : .secondary)
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
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(PPTheme.gold.opacity(0.15))
                        .foregroundStyle(PPTheme.gold)
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
            StatementDocument.self,
            BankTransaction.self,
            MerchantCategoryOverride.self,
        ], inMemory: true)
}
