import SwiftUI
import SwiftData

/// Missed Rewards Audit — the flagship screen. Replays every imported charge
/// chronologically against the optimal card (caps simulated in date order),
/// tallies expired unused credits, and shows the YTD dollar total of what
/// was left on the table. Cupertino bento styling throughout.
struct AuditView: View {
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<CardItem> { !$0.isArchived }, sort: \CardItem.canonicalName)
    private var cards: [CardItem]
    @Query private var completions: [CompletionRecord]
    @Query private var mutes: [MutedReward]
    @Query(sort: \BankTransaction.date) private var transactions: [BankTransaction]
    @Query private var documents: [StatementDocument]

    @State private var hideSmallMisses = true

    private var report: AuditReport {
        SpendAuditService.audit(
            transactions: transactions, cards: cards,
            completions: completions, mutes: mutes, documents: documents
        )
    }

    private var txById: [String: BankTransaction] {
        Dictionary(uniqueKeysWithValues: transactions.map { ($0.stableId, $0) })
    }

    private var visibleMisses: [MissedOpportunity] {
        hideSmallMisses
            ? report.opportunities.filter { $0.missedUSD >= 1 }
            : report.opportunities
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PPTheme.gridSpacing) {
                    if report.analyzedCount == 0 {
                        emptyState
                    } else {
                        heroTile
                        if report.totalMissedUSD < 1 {
                            celebrationTile
                        } else {
                            categorySection
                            cardSection
                            expiredSection
                            missesSection
                        }
                        advisorLink
                        methodologyFootnote
                    }
                }
                .padding(.horizontal, PPTheme.screenPad)
                .padding(.vertical, 12)
            }
            .background(PPTheme.pageBackground)
            .navigationTitle("Missed Rewards")
        }
    }

    // MARK: - Hero

    private var heroTile: some View {
        BentoTile(minHeight: 168) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Missed this year", systemImage: "chart.line.downtrend.xaxis")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Text(report.totalMissedUSD.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(PPTheme.gold)
                    .monospacedDigit()
                HStack(spacing: 16) {
                    splitStat(value: report.missedEarnUSD, label: "Wrong-card spend")
                    splitStat(value: report.expiredCreditsUSD, label: "Expired credits")
                }
                if let p = report.annualizedProjectionUSD {
                    Text("On pace for \(p.formatted(.currency(code: "USD").precision(.fractionLength(0)))) by Dec 31 — projected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Across \(report.analyzedCount) transactions · \(report.analyzedSpendUSD.formatted(.currency(code: "USD").precision(.fractionLength(0)))) analyzed")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func splitStat(value: Double, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                .font(.headline)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty / celebration

    private var emptyState: some View {
        BentoTile(minHeight: 220) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.largeTitle)
                    .foregroundStyle(PPTheme.gold)
                    .accessibilityHidden(true)
                Text("No statements yet")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Import statements for your cards and I'll replay every dollar against the optimal card — then show you exactly what the wrong card cost you this year.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                NavigationLink(destination: StatementsView()) {
                    Label("Import statements", systemImage: "square.and.arrow.down")
                        .font(.headline)
                        .foregroundStyle(PPTheme.gold)
                }
                .padding(.top, 4)
            }
        }
    }

    private var celebrationTile: some View {
        BentoTile {
            BentoStat(
                title: "Clean sheet",
                value: "Nothing left",
                subtitle: "Every dollar went to its optimal card",
                systemImage: "checkmark.seal.fill",
                tint: PPTheme.success
            )
        }
    }

    // MARK: - Breakdowns

    private var categorySection: some View {
        section(title: "Where it's leaking") {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: PPTheme.gridSpacing),
                          GridItem(.flexible(), spacing: PPTheme.gridSpacing)],
                spacing: PPTheme.gridSpacing
            ) {
                ForEach(Array(report.missedByCategory.enumerated()), id: \.offset) { _, entry in
                    let (cat, missed, spend) = entry
                    BentoTile {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: cat.systemImage)
                                    .foregroundStyle(PPTheme.gold)
                                    .accessibilityHidden(true)
                                Spacer()
                                Text(missed.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                                    .font(.headline)
                                    .monospacedDigit()
                            }
                            ProgressView(value: spend > 0 ? missed / max(spend, 1) : 0)
                                .tint(PPTheme.gold)
                            Text(cat.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("missed on \(spend.formatted(.currency(code: "USD").precision(.fractionLength(0)))) spend")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var cardSection: some View {
        section(title: "Misallocated by card") {
            VStack(spacing: 8) {
                ForEach(report.missedByUsedCard, id: \.0) { entry in
                    let (_, name, missed, spend) = entry
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("missed on \(spend.formatted(.currency(code: "USD").precision(.fractionLength(0)))) spend")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(missed.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                            .font(.headline)
                            .foregroundStyle(PPTheme.gold)
                            .monospacedDigit()
                    }
                    .padding(12)
                    .background(PPTheme.tileBackground,
                                in: RoundedRectangle(cornerRadius: PPTheme.cardRadius, style: .continuous))
                }
            }
        }
    }

    // MARK: - Expired credits

    @ViewBuilder
    private var expiredSection: some View {
        if !report.expiredCredits.isEmpty {
            section(title: "Credits you let expire") {
                VStack(spacing: 8) {
                    ForEach(Array(report.expiredCredits.enumerated()), id: \.offset) { _, credit in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(credit.benefitName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("\(credit.cardShortName) · \(credit.periodLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(credit.faceValue.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                                .font(.headline)
                                .foregroundStyle(.red.opacity(0.85))
                                .monospacedDigit()
                        }
                        .padding(12)
                        .background(PPTheme.tileBackground,
                                    in: RoundedRectangle(cornerRadius: PPTheme.cardRadius, style: .continuous))
                    }
                    Text("Tracked expirations only — periods since you started importing statements.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    // MARK: - Transaction misses

    private var missesSection: some View {
        section(title: "Every miss") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Hide misses under $1", isOn: $hideSmallMisses)
                    .font(.subheadline)
                    .tint(PPTheme.gold)
                    .padding(.horizontal, 4)
                if visibleMisses.isEmpty {
                    Text("No misses above the filter — nice.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                ForEach(visibleMisses, id: \.transactionId) { miss in
                    if let tx = txById[miss.transactionId] {
                        NavigationLink(destination: TransactionDetailView(tx: tx)) {
                            missRow(miss)
                        }
                        .buttonStyle(.plain)
                    } else {
                        missRow(miss)
                    }
                }
            }
        }
    }

    private func missRow(_ miss: MissedOpportunity) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(miss.merchant)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(miss.date.formatted(date: .abbreviated, time: .omitted)) · \(miss.amount.formatted(.currency(code: "USD")))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Used \(miss.usedShortName) (\(miss.usedRateLabel)) → should've used \(miss.optimalShortName) (\(miss.optimalRateLabel))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("−\(miss.missedUSD.formatted(.currency(code: "USD")))")
                    .font(.headline)
                    .foregroundStyle(PPTheme.gold)
                    .monospacedDigit()
                Text("missed")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(PPTheme.tileBackground,
                    in: RoundedRectangle(cornerRadius: PPTheme.cardRadius, style: .continuous))
    }

    // MARK: - Advisor link + methodology

    private var advisorLink: some View {
        NavigationLink(destination: AdvisorView(initialMode: .newIdeas)) {
            BentoTile {
                HStack {
                    BentoStat(
                        title: "Fix it going forward",
                        value: "New card ideas",
                        subtitle: "Cards that would earn more on your spend",
                        systemImage: "wand.and.stars",
                        tint: PPTheme.gold
                    )
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var methodologyFootnote: some View {
        Text("""
        How this is calculated: every imported charge is replayed in date order against all 12 of your cards. Annual caps (like Costco's $7k gas limit) are simulated as they would have filled up, so the "optimal" card always had room — no fantasy math. Point values are conservative estimates (UR 1.5¢, MR 1.0¢, etc.). Differences under $0.25 don't count. Expired credits are counted at face value, only for periods since you started tracking, and only when your statements show spend where the credit could plausibly have been used. Low-confidence transactions (\(report.excludedLowConfidence)) are excluded. Statement data never leaves this device.
        """)
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal, 4)
            content()
        }
        .padding(.top, 8)
    }
}

#Preview {
    AuditView()
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
