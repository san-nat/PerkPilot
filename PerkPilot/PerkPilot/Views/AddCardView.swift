import SwiftUI
import SwiftData

/// Re-adds archived cards. Brand-new card products arrive via catalog
/// updates (Phase 2 discovery pipeline), not manual entry — this keeps
/// benefits sourced and verified instead of hand-typed.
struct AddCardView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<CardItem> { $0.isArchived }, sort: \CardItem.canonicalName)
    private var archivedCards: [CardItem]

    var body: some View {
        NavigationStack {
            List {
                if archivedCards.isEmpty {
                    ContentUnavailableView(
                        "No cards to add",
                        systemImage: "creditcard",
                        description: Text("All catalog cards are already in your wallet.")
                    )
                } else {
                    Section("Archived cards") {
                        ForEach(archivedCards) { card in
                            HStack {
                                CardRow(card: card)
                                Spacer()
                                Button("Add back") {
                                    card.isArchived = false
                                    card.archivedAt = nil
                                    dismiss()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                Section {
                    Text("Don't see a card? New products are added through verified catalog updates so every benefit ships with sources. Catalog updates arrive with the Phase 2 discovery feed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    AddCardView()
        .modelContainer(for: [
            CardItem.self,
            BenefitItem.self,
            TipItem.self,
            CompletionRecord.self,
            MutedReward.self,
        ], inMemory: true)
}
