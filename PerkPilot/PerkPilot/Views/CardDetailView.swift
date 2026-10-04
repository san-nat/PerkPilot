import SwiftUI
import SwiftData

/// Card detail: benefits grouped by cadence, with tips, sources,
/// mute controls, and archive / restore.
struct CardDetailView: View {
    @Bindable var card: CardItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var mutes: [MutedReward]

    @State private var expandedBenefits = Set<String>()
    @State private var showingArchiveConfirm = false
    @State private var showingStatementImport = false

    private var mutedIds: Set<String> { Set(mutes.map(\.benefitStableId)) }

    private var cardDocuments: [StatementDocument] {
        TransactionStore.documents(cardStableId: card.stableId, context: context)
    }

    private var mutedCount: Int {
        Set(card.benefits.map(\.stableId)).intersection(mutedIds).count
    }

    private func cardStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private struct CadenceGroup: Identifiable {
        var cadence: Cadence
        var benefits: [BenefitItem]
        var id: String { cadence.rawValue }
    }

    private var grouped: [CadenceGroup] {
        let order: [Cadence] = [.monthly, .quarterly, .semiannual, .annual, .oneTime, .perUse]
        return order.compactMap { cadence in
            let items = card.benefits.filter { $0.cadence == cadence }.sorted { $0.name < $1.name }
            return items.isEmpty ? nil : CadenceGroup(cadence: cadence, benefits: items)
        }
    }

    var body: some View {
        List {
            Section {
                MetalCardView(card: card)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                HStack(spacing: 0) {
                    cardStat(value: "\(card.benefits.count)", label: "Benefits")
                    Divider().frame(height: 32)
                    cardStat(value: "\(card.recurringBenefits.count)", label: "Recurring")
                    Divider().frame(height: 32)
                    cardStat(value: "\(mutedCount)", label: "Muted")
                }
                .padding(.vertical, 4)
                .listRowBackground(PPTheme.tileBackground)

                if card.isArchived {
                    Label("Archived — no checklist tasks generated", systemImage: "archivebox")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Statements") {
                if cardDocuments.isEmpty {
                    Text("No statements imported for this card yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(cardDocuments, id: \.stableId) { doc in
                        HStack {
                            Image(systemName: doc.source == .pdf ? "doc.richtext" : "tablecells")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(doc.periodKey)
                                    .font(.callout)
                                Text("\(doc.transactionCount) transactions · \(doc.fileName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if doc.lowConfidenceCount > 0 {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                    .accessibilityLabel("\(doc.lowConfidenceCount) low-confidence rows")
                            }
                        }
                    }
                }
                Button {
                    showingStatementImport = true
                } label: {
                    Label("Import statement…", systemImage: "square.and.arrow.down")
                }
                NavigationLink(destination: RewardsCheckView()) {
                    Label("Check rewards received", systemImage: "checkmark.shield")
                }
            } footer: {
                Text("Statements stay on this iPhone — parsed here, never uploaded.")
            }

            ForEach(grouped) { group in in
                Section(group.cadence.displayName) {
                    ForEach(group.benefits, id: \.stableId) { benefit in
                        BenefitRow(
                            benefit: benefit,
                            cardName: card.canonicalName,
                            isExpanded: expandedBenefits.contains(benefit.stableId),
                            isMuted: mutedIds.contains(benefit.stableId),
                            muteReason: mutes.first { $0.benefitStableId == benefit.stableId }?.reason,
                            onToggleExpanded: { toggleExpanded(benefit) },
                            onMute: { reason in mute(benefit, reason: reason) },
                            onUnmute: { unmute(benefit) }
                        )
                    }
                }
            }

            Section {
                if card.isArchived {
                    Button("Restore to wallet") { restore() }
                } else {
                    Button("Archive from wallet", role: .destructive) {
                        showingArchiveConfirm = true
                    }
                }
            } footer: {
                Text("Archiving stops future checklist tasks but keeps your past checkmarks. Permanent deletion lives in Settings.")
            }
        }
        .navigationTitle(card.canonicalName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingStatementImport) {
            StatementImportView(preselectedCardStableId: card.stableId)
        }
        .confirmationDialog(
            "Archive \(card.canonicalName)?",
            isPresented: $showingArchiveConfirm,
            titleVisibility: .visible
        ) {
            Button("Archive from wallet", role: .destructive) { archive() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Checklist tasks stop. Past checkmarks are kept, and you can restore anytime.")
        }
    }

    private func toggleExpanded(_ benefit: BenefitItem) {
        if expandedBenefits.contains(benefit.stableId) {
            expandedBenefits.remove(benefit.stableId)
        } else {
            expandedBenefits.insert(benefit.stableId)
        }
    }

    private func mute(_ benefit: BenefitItem, reason: MuteReason) {
        guard !mutedIds.contains(benefit.stableId) else { return }
        context.insert(MutedReward(benefitStableId: benefit.stableId, reason: reason))
    }

    private func unmute(_ benefit: BenefitItem) {
        if let existing = mutes.first(where: { $0.benefitStableId == benefit.stableId }) {
            context.delete(existing)
        }
    }

    private func archive() {
        card.isArchived = true
        card.archivedAt = Date()
    }

    private func restore() {
        card.isArchived = false
        card.archivedAt = nil
    }
}

/// Shared benefit row used by the card detail and the library.
struct BenefitRow: View {
    var benefit: BenefitItem
    var cardName: String? = nil
    var isExpanded: Bool
    var isMuted: Bool
    var muteReason: MuteReason?
    var onToggleExpanded: () -> Void
    var onMute: (MuteReason) -> Void
    var onUnmute: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onToggleExpanded) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(benefit.name)
                                .font(.headline)
                                .multilineTextAlignment(.leading)
                            if benefit.lesserKnown {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundStyle(.yellow)
                                    .accessibilityLabel("Lesser-known benefit")
                            }
                        }
                        Text(benefit.amountDisplay)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let cardName {
                            Text(cardName)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        if isMuted {
                            Text("Muted — \(muteReason?.displayName ?? "muted")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(benefit.howToUse)
                        .font(.body)
                    if benefit.enrollmentRequired {
                        Label("Enrollment required", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    ForEach(benefit.tips, id: \.stableId) { tip in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "lightbulb")
                                .foregroundStyle(.yellow)
                            Text(tip.text)
                                .font(.callout)
                        }
                        .padding(8)
                        .background(Color.yellow.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    if !benefit.sources.isEmpty {
                        Text("Sources")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(benefit.sources, id: \.self) { urlString in
                            if let url = URL(string: urlString) {
                                Link(url.host ?? urlString, destination: url)
                                    .font(.caption)
                            }
                        }
                    }
                    muteControl
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var muteControl: some View {
        if isMuted {
            Button("Unmute reward") { onUnmute() }
                .font(.callout)
        } else {
            Menu("Mute reward") {
                ForEach(MuteReason.allCases, id: \.self) { reason in
                    Button(reason.displayName) { onMute(reason) }
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}
