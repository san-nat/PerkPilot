import SwiftUI
import SwiftData

// MARK: - AdvisorView
//
// "Smart Rewards Advisor": two tools in one tab.
//  • "Which card?" — best card for one purchase, ranked with the math shown.
//  • "New card ideas" — portfolio gap analyzer: YTD category spend vs ~12
//    popular cards he doesn't hold, ranked by incremental net annual value.
// All numbers are estimates; the UI says so everywhere it matters.

struct AdvisorView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case whichCard = "Which card?"
        case newIdeas = "New card ideas"
        var id: String { rawValue }
    }

    var initialMode: Mode = .whichCard
    @State private var mode: Mode

    init(initialMode: Mode = .whichCard) {
        self.initialMode = initialMode
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Advisor", selection: $mode) {
                    ForEach(Mode.allCases) { m in Text(m.rawValue).tag(m) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, PPTheme.screenPad)
                .padding(.vertical, 8)

                if mode == .whichCard {
                    WhichCardView()
                } else {
                    NewCardIdeasView()
                }
            }
            .background(PPTheme.pageBackground)
            .navigationTitle("Advisor")
        }
        .onAppear { mode = initialMode }
    }
}

// MARK: - Which card?

private struct WhichCardView: View {
    @Environment(\.modelContext) private var context
    @State private var merchant = ""
    @State private var amountText = ""
    @State private var category: SpendCategory = .dining
    @State private var ranked: [RewardsAdvisor.RankedCard]? = nil

    private var amount: Double? {
        let t = amountText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
        guard let v = Double(t), v > 0 else { return nil }
        return v
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PPTheme.gridSpacing) {
                BentoTile {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Where are you spending?")
                            .font(.headline)
                        TextField("Merchant (e.g. Shell, Delta)", text: $merchant)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            TextField("Amount", text: $amountText)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.decimalPad)
                            Picker("Category", selection: $category) {
                                ForEach(SpendCategory.allCases.filter(\.isSpend), id: \.self) { c in
                                    Text(c.displayName).tag(c)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        Button("Rank my cards") {
                            guard let amount else { return }
                            let txs = TransactionStore.transactions(context: context)
                            let ytd = RewardsAdvisor.ytdSpendByCardCategory(txs)
                            ranked = RewardsAdvisor.bestCard(
                                merchant: merchant.isEmpty ? category.displayName : merchant,
                                amount: amount, category: category, ytd: ytd)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(amount == nil)
                        .frame(maxWidth: .infinity, alignment: .center)
                        Text("Estimates only — caps use your imported statements; point values are conservative.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let ranked {
                    ForEach(Array(ranked.enumerated()), id: \.element.cardStableId) { i, card in
                        BentoTile {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    if i == 0 {
                                        Text("BEST")
                                            .font(.caption2).fontWeight(.bold)
                                            .padding(.horizontal, 8).padding(.vertical, 3)
                                            .background(PPTheme.gold, in: Capsule())
                                            .foregroundStyle(.white)
                                    } else {
                                        Text("\(i + 1).")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Text(card.displayName).font(.headline)
                                    Spacer()
                                    Text(card.rewardUSD, format: .currency(code: "USD"))
                                        .font(.title3).fontWeight(.bold).monospacedDigit()
                                        .foregroundStyle(i == 0 ? PPTheme.gold : .primary)
                                }
                                Text("\(card.rateLabel)  ·  \(card.effectivePct, specifier: "%.1f")% back")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Text(card.why)
                                    .font(.caption).foregroundStyle(.secondary)
                                if card.capHit {
                                    Label("Annual bonus cap already reached on this card", systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption).foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
                Spacer(minLength: 24)
            }
            .padding(.horizontal, PPTheme.screenPad)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - New card ideas

private struct NewCardIdeasView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<CardItem> { !$0.isArchived }) private var cards: [CardItem]

    private var charges: [BankTransaction] {
        TransactionStore.transactions(context: context).filter { $0.isCharge && $0.category.isSpend }
    }
    private var monthsCovered: Int {
        max(1, Set(TransactionStore.documents(context: context).map(\.periodKey)).count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PPTheme.gridSpacing) {
                if charges.isEmpty {
                    BentoTile {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Import statements to unlock", systemImage: "doc.text.fill")
                                .font(.headline)
                            Text("Card ideas are scored against your actual category spend. Import at least one statement from the Statements tab first.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    spendChart
                    ForEach(analysis, id: \.candidate.stableId) { verdict in
                        verdictCard(verdict)
                    }
                    assumptionsFootnote
                }
                Spacer(minLength: 24)
            }
            .padding(.horizontal, PPTheme.screenPad)
            .padding(.vertical, 8)
        }
    }

    private var analysis: [CandidateVerdict] {
        let ytd = RewardsAdvisor.ytdSpendByCardCategory(charges)
        let currentBest = RewardsAdvisor.currentBestPctByCategory(ytd: ytd)
        let chaseCount = cards.filter { $0.issuer == "Chase" }.count
        return PortfolioAnalyzer.analyze(
            transactions: charges, currentBestPct: currentBest,
            monthsCovered: monthsCovered, chaseCardsHeld: chaseCount)
    }

    private var spendChart: some View {
        let rows = PortfolioAnalyzer.annualizedSpendByCategory(charges, monthsCovered: monthsCovered)
        let maxV = rows.map(\.1).max() ?? 1
        return BentoTile {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your spend by category (annualized)")
                    .font(.headline)
                ForEach(rows.prefix(8), id: \.0) { cat, total in
                    HStack {
                        Text(cat.displayName).font(.subheadline).frame(width: 110, alignment: .leading)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(PPTheme.gold.opacity(0.85))
                                .frame(width: max(4, geo.size.width * CGFloat(total / maxV)))
                        }
                        .frame(height: 8)
                        Text(total, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Text("From \(monthsCovered) month\(monthsCovered == 1 ? "" : "s") of statements · estimates")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func verdictCard(_ verdict: CandidateVerdict) -> some View {
        let c = verdict.candidate
        return BentoTile {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name).font(.headline)
                        Text("\(c.issuer) · $\(Int(c.annualFee))/yr fee")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("+\(verdict.netAnnualUSD, format: .currency(code: "USD").precision(.fractionLength(0)))")
                            .font(.title2).fontWeight(.bold).monospacedDigit()
                            .foregroundStyle(PPTheme.gold)
                        Text("/yr net").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                mathRow("Extra rewards", verdict.incrementalRewardsUSD)
                mathRow("Usable credits", verdict.usableCreditsUSD)
                mathRow("Minus annual fee", -verdict.annualFeeUSD)
                if !c.creditsNote.isEmpty, verdict.usableCreditsUSD > 0 {
                    Text(c.creditsNote).font(.caption).foregroundStyle(.secondary)
                }
                if !verdict.lineItems.isEmpty {
                    DisclosureGroup("How the math works") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(verdict.lineItems, id: \.category) { item in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.category.displayName).font(.subheadline).fontWeight(.medium)
                                    Text("\(item.eligibleAnnualSpend, format: .currency(code: "USD").precision(.fractionLength(0))) × (\(String(format: "%.1f", item.candidatePct))% − \(String(format: "%.1f", item.currentBestPct))%) = \(item.incrementalUSD, format: .currency(code: "USD").precision(.fractionLength(0)))")
                                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.subheadline)
                }
                if let caution = verdict.chaseCaution {
                    Label(caution, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                ForEach(c.notes, id: \.self) { note in
                    Text("• \(note)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func mathRow(_ label: String, _ value: Double) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text("\(value >= 0 ? "+" : "−")\(abs(value), format: .currency(code: "USD").precision(.fractionLength(0)))")
                .font(.subheadline).monospacedDigit()
        }
    }

    private var assumptionsFootnote: some View {
        Text("Estimates, not guarantees. Point values are conservative and shown per card; spend is annualized from your statements; only cards with positive net value are shown.")
            .font(.caption).foregroundStyle(.secondary)
    }
}

#Preview {
    AdvisorView()
        .modelContainer(for: [
            CardItem.self, BenefitItem.self, TipItem.self, CompletionRecord.self,
            MutedReward.self, StatementDocument.self, BankTransaction.self,
            MerchantCategoryOverride.self,
        ], inMemory: true)
}
