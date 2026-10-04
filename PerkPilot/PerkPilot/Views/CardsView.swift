import SwiftUI
import SwiftData

/// Wallet: active cards, archived cards, and the add-back flow.
struct CardsView: View {
    @Query(filter: #Predicate<CardItem> { !$0.isArchived }, sort: \CardItem.canonicalName)
    private var activeCards: [CardItem]
    @Query(filter: #Predicate<CardItem> { $0.isArchived }, sort: \CardItem.canonicalName)
    private var archivedCards: [CardItem]

    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                Section("Wallet (\(activeCards.count))") {
                    ForEach(activeCards) { card in
                        NavigationLink(destination: CardDetailView(card: card)) {
                            CardRow(card: card)
                        }
                    }
                }
                if !archivedCards.isEmpty {
                    Section("Archived") {
                        ForEach(archivedCards) { card in
                            NavigationLink(destination: CardDetailView(card: card)) {
                                CardRow(card: card)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Cards")
            .toolbar {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add card")
            }
            .sheet(isPresented: $showingAdd) {
                AddCardView()
            }
        }
    }
}

struct CardRow: View {
    var card: CardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.canonicalName)
                .font(.headline)
            HStack {
                Text(card.issuer)
                Text("•")
                Text(card.annualFeeDisplay)
                Text("•")
                Text("\(card.benefits.count) benefits")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    CardsView()
        .modelContainer(for: [
            CardItem.self,
            BenefitItem.self,
            TipItem.self,
            CompletionRecord.self,
            MutedReward.self,
        ], inMemory: true)
}
