import XCTest
@testable import PerkPilot

// MARK: - RewardsAdvisor tests (pure logic, no SwiftData container needed)

final class AdvisorTests: XCTestCase {
    private func tx(_ merchant: String, _ amount: Double, _ category: SpendCategory, card: String = "robinhood-gold") -> BankTransaction {
        BankTransaction(
            cardStableId: card,
            date: Date(),
            merchantRaw: merchant,
            amount: -abs(amount),   // negative = charge
            category: category
        )
    }

    // MARK: bestCard ranking

    func testDiningRankingPutsReserveFirst() {
        let ranked = RewardsAdvisor.bestCard(merchant: "Bistro", amount: 100, category: .dining, ytd: [:])
        XCTAssertEqual(ranked.first?.cardStableId, "chase-sapphire-reserve")
        XCTAssertEqual(ranked.first?.rewardUSD ?? 0, 4.50, accuracy: 0.001)   // 3x UR @ 1.5¢
        XCTAssertEqual(ranked[1].cardStableId, "robinhood-gold")
        XCTAssertEqual(ranked[1].rewardUSD, 3.00, accuracy: 0.001)              // 3% flat
    }

    func testCapHandlingDropsCostcoGasAfterCap() {
        let ytd: [String: [SpendCategory: Double]] = ["costco-anywhere-visa": [.gas: 7_500]]
        let ranked = RewardsAdvisor.bestCard(merchant: "Shell", amount: 100, category: .gas, ytd: ytd)
        let costco = ranked.first { $0.cardStableId == "costco-anywhere-visa" }!
        XCTAssertEqual(costco.effectivePct, 1.0, accuracy: 0.001)   // fell to 1% past $7k
        XCTAssertTrue(costco.capHit)
        XCTAssertEqual(ranked.first?.cardStableId, "robinhood-gold") // 3% wins now
    }

    func testWholeFoodsBoostPicksPrimeVisa() {
        let ranked = RewardsAdvisor.bestCard(
            merchant: "WHOLE FOODS MARKET #1023", amount: 100, category: .groceries, ytd: [:])
        XCTAssertEqual(ranked.first?.cardStableId, "chase-prime-visa")
        XCTAssertEqual(ranked.first?.rewardUSD ?? 0, 5.00, accuracy: 0.001)
    }

    func testFlatCardsBeatNothing() {
        // Unknown merchant, "other" category → highest flat rate wins.
        let ranked = RewardsAdvisor.bestCard(merchant: "XYZ Corp", amount: 200, category: .other, ytd: [:])
        XCTAssertEqual(ranked.first?.cardStableId, "robinhood-gold")  // 3% > 1.5x UR (2.25%)
        XCTAssertEqual(ranked.first?.rewardUSD ?? 0, 6.00, accuracy: 0.001)
    }

    // MARK: PortfolioAnalyzer

    func testWholeFoodsOverlapExcludedFromAmexGold() {
        let txs = [
            tx("WHOLE FOODS MARKET", 20_000, .groceries),
            tx("KROGER", 20_000, .groceries),
        ]
        let verdicts = PortfolioAnalyzer.analyze(
            transactions: txs,
            currentBestPct: [.groceries: 0.01],
            monthsCovered: 12,
            chaseCardsHeld: 7)
        let gold = verdicts.first { $0.candidate.stableId == "cand-amex-gold" }!
        let grocery = gold.lineItems.first { $0.category == .groceries }!
        XCTAssertEqual(grocery.eligibleAnnualSpend, 20_000, accuracy: 0.01)  // WF $20k excluded
        XCTAssertEqual(grocery.incrementalUSD, 20_000 * (0.04 - 0.01), accuracy: 0.01)
        XCTAssertGreaterThan(gold.netAnnualUSD, 0)
    }

    func testNegativeNetNeverRecommended() {
        let txs = [tx("KROGER", 50, .groceries)]
        let verdicts = PortfolioAnalyzer.analyze(
            transactions: txs,
            currentBestPct: [.groceries: 0.01, .dining: 0.045, .travel: 0.045],
            monthsCovered: 12,
            chaseCardsHeld: 7)
        XCTAssertFalse(verdicts.contains { $0.candidate.stableId == "cand-venture-x" }) // $395 fee, no spend
        XCTAssertTrue(verdicts.allSatisfy { $0.netAnnualUSD > 0 })
    }

    func testAnnualizationScalesSpend() {
        let txs = [tx("KROGER", 1_000, .groceries)]
        let verdicts = PortfolioAnalyzer.analyze(
            transactions: txs,
            currentBestPct: [.groceries: 0.01],
            monthsCovered: 6,   // ×2 annualization
            chaseCardsHeld: 7)
        let bce = verdicts.first { $0.candidate.stableId == "cand-bce" }!
        let grocery = bce.lineItems.first { $0.category == .groceries }!
        XCTAssertEqual(grocery.eligibleAnnualSpend, 2_000, accuracy: 0.01)
    }

    func testCustomCashCountsOnlyTopCategory() {
        let txs = [
            tx("Bistro", 3_000, .dining),
            tx("KROGER", 1_000, .groceries),
        ]
        let verdicts = PortfolioAnalyzer.analyze(
            transactions: txs,
            currentBestPct: [.dining: 0.01, .groceries: 0.01],
            monthsCovered: 12,
            chaseCardsHeld: 7)
        let ccc = verdicts.first { $0.candidate.stableId == "cand-custom-cash" }!
        XCTAssertEqual(ccc.lineItems.count, 1)
        XCTAssertEqual(ccc.lineItems.first?.category, .dining)
    }

    func testChaseCautionFlagged() {
        let txs = [tx("Bistro", 10_000, .dining)]
        let verdicts = PortfolioAnalyzer.analyze(
            transactions: txs,
            currentBestPct: [.dining: 0.01],
            monthsCovered: 12,
            chaseCardsHeld: 7)
        let flex = verdicts.first { $0.candidate.stableId == "cand-freedom-flex" }!
        XCTAssertNotNil(flex.chaseCaution)
        XCTAssertTrue(flex.chaseCaution!.contains("5/24"))
        let gold = verdicts.first { $0.candidate.stableId == "cand-amex-gold" }!
        XCTAssertNil(gold.chaseCaution)
    }
}
