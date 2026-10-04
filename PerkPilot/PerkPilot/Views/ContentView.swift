import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @State private var seedError: String?

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "checklist") }
            CardsView()
                .tabItem { Label("Cards", systemImage: "creditcard") }
            StatementsView()
                .tabItem { Label("Statements", systemImage: "doc.text") }
            AdvisorView()
                .tabItem { Label("Advisor", systemImage: "wand.and.stars") }
            BenefitsLibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
            NewsView()
                .tabItem { Label("News", systemImage: "newspaper") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .task {
            do {
                try SeedLoader.importIfNeeded(context)
            } catch {
                seedError = error.localizedDescription
            }
        }
        .alert("Catalog failed to load", isPresented: Binding(
            get: { seedError != nil },
            set: { if !$0 { seedError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(seedError ?? "Unknown error")
        }
    }
}

#Preview {
    ContentView()
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
