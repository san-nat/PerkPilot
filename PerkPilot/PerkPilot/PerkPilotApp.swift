import SwiftUI
import SwiftData

@main
struct PerkPilotApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            CardItem.self,
            BenefitItem.self,
            TipItem.self,
            CompletionRecord.self,
            MutedReward.self,
            StatementDocument.self,
            BankTransaction.self,
            MerchantCategoryOverride.self,
        ])
    }
}
