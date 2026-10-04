import SwiftUI
import SwiftData

/// Searchable, filterable catalog of every benefit across all cards.
struct BenefitsLibraryView: View {
    @Query(sort: \BenefitItem.name) private var benefits: [BenefitItem]
    @Query(sort: \CardItem.canonicalName) private var cards: [CardItem]
    @Query private var mutes: [MutedReward]
    @Environment(\.modelContext) private var context

    @State private var searchText = ""
    @State private var selectedCardId: String? = nil
    @State private var selectedCadence: Cadence? = nil
    @State private var lesserKnownOnly = false
    @State private var mutedOnly = false
    @State private var expandedBenefits = Set<String>()

    /// Lets bento tiles / other views deep-link with filters pre-applied.
    init(searchText: String = "", lesserKnownOnly: Bool = false, mutedOnly: Bool = false) {
        _searchText = State(initialValue: searchText)
        _lesserKnownOnly = State(initialValue: lesserKnownOnly)
        _mutedOnly = State(initialValue: mutedOnly)
    }

    private var mutedIds: Set<String> { Set(mutes.map(\.benefitStableId)) }

    private var filtered: [BenefitItem] {
        benefits.filter { b in
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                guard b.name.lowercased().contains(q) || b.howToUse.lowercased().contains(q) else { return false }
            }
            if let id = selectedCardId, b.card?.stableId != id { return false }
            if let cadence = selectedCadence, b.cadence != cadence { return false }
            if lesserKnownOnly && !b.lesserKnown { return false }
            if mutedOnly && !mutedIds.contains(b.stableId) { return false }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Card", selection: $selectedCardId) {
                        Text("All cards").tag(String?(nil))
                        ForEach(cards, id: \.stableId) { card in
                            Text(card.canonicalName).tag(String?(card.stableId))
                        }
                    }
                    Picker("Cadence", selection: $selectedCadence) {
                        Text("Any cadence").tag(Cadence?(nil))
                        ForEach(Cadence.allCases, id: \.self) { c in
                            Text(c.displayName).tag(Cadence?(c))
                        }
                    }
                    Toggle("Lesser-known only", isOn: $lesserKnownOnly)
                    Toggle("Muted only", isOn: $mutedOnly)
                }

                Section("\(filtered.count) benefits") {
                    ForEach(filtered, id: \.stableId) { benefit in
                        BenefitRow(
                            benefit: benefit,
                            cardName: benefit.card?.canonicalName,
                            isExpanded: expandedBenefits.contains(benefit.stableId),
                            isMuted: mutedIds.contains(benefit.stableId),
                            muteReason: mutes.first { $0.benefitStableId == benefit.stableId }?.reason,
                            onToggleExpanded: {
                                if expandedBenefits.contains(benefit.stableId) {
                                    expandedBenefits.remove(benefit.stableId)
                                } else {
                                    expandedBenefits.insert(benefit.stableId)
                                }
                            },
                            onMute: { reason in
                                context.insert(MutedReward(benefitStableId: benefit.stableId, reason: reason))
                            },
                            onUnmute: {
                                if let m = mutes.first(where: { $0.benefitStableId == benefit.stableId }) {
                                    context.delete(m)
                                }
                            }
                        )
                    }
                }
            }
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Search benefits")
        }
    }
}

#Preview {
    BenefitsLibraryView()
        .modelContainer(for: [
            CardItem.self,
            BenefitItem.self,
            TipItem.self,
            CompletionRecord.self,
            MutedReward.self,
        ], inMemory: true)
}
