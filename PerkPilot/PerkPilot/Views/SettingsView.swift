import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var cards: [CardItem]

    @StateObject private var notifications = NotificationService.shared
    @State private var showingResetConfirm = false
    @State private var statusMessage: String?

    @Query private var documents: [StatementDocument]
    @Query private var transactions: [BankTransaction]

    private var statementCount: Int { documents.count }
    private var transactionCount: Int { transactions.count }

    var body: some View {
        NavigationStack {
            List {
                Section("Reminders") {
                    Toggle("Monthly closeout reminder", isOn: $notifications.remindersEnabled)
                    Text("A quiet reminder on the 28th of each month to use expiring credits before they reset.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Catalog data") {
                    LabeledContent("Cards", value: "\(cards.count)")
                    LabeledContent(
                        "Benefits",
                        value: "\(cards.flatMap(\.benefits).count)"
                    )
                    LabeledContent(
                        "Catalog version",
                        value: SeedLoader.lastImportedVersion ?? "—"
                    )
                    Button("Re-import seed catalog") {
                        do {
                            try SeedLoader.importIfNeeded(context, force: true)
                            statusMessage = "Catalog re-imported."
                        } catch {
                            statusMessage = error.localizedDescription
                        }
                    }
                }

                Section("Statements & privacy") {
                    LabeledContent("Imported statements", value: "\(statementCount)")
                    LabeledContent("Transactions", value: "\(transactionCount)")
                    Label(
                        "Statement data stays on this iPhone. It's parsed on-device, never uploaded, and excluded from any future sync.",
                        systemImage: "lock.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Button("Delete all statements", role: .destructive) {
                        TransactionStore.deleteAllStatements(context: context)
                        statusMessage = "All statements and transactions deleted."
                    }
                }

                Section {
                    Button("Reset all data", role: .destructive) {
                        showingResetConfirm = true
                    }
                } footer: {
                    Text("Deletes every card, benefit, checkmark, mute, archive, and imported statement. The seed catalog re-imports on next launch.")
                }

                Section("About") {
                    Text("PerkPilot tracks expiring credit-card benefits so you use them before they reset. Benefits ship with sources; nothing here is financial advice.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Statement Intelligence is heuristic: reward matching suggests, never verifies, whether a credit was used. Imported statements never leave this device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LabeledContent("Version", value: "1.0")
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .task { await notifications.refreshAuthorization() }
            .confirmationDialog(
                "Reset all data?",
                isPresented: $showingResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete everything", role: .destructive) { resetAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes cards, benefits, checkmarks, mutes, and archives.")
            }
        }
    }

    private func resetAll() {
        do {
            try context.delete(model: CardItem.self)
            try context.delete(model: CompletionRecord.self)
            try context.delete(model: MutedReward.self)
            try context.delete(model: StatementDocument.self)
            try context.delete(model: BankTransaction.self)
            try context.delete(model: MerchantCategoryOverride.self)
            try context.save()
            UserDefaults.standard.removeObject(forKey: "perkPilot.seedCatalogVersion")
            statusMessage = "All data deleted. Relaunch to re-import the catalog."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

#Preview {
    SettingsView()
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
