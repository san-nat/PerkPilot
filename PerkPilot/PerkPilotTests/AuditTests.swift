import XCTest
@testable import PerkPilot

// MARK: - SpendAuditService tests (pure logic, synthetic ledgers)

final class AuditTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    private func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: day))!
    }

    private func tx(_ id: String, _ date: Date, _ card: String, _ merchant: String,
                    _ amount: Double, _ cat: SpendCategory,
                    confidence: Double = 1.0, flagged: Bool = false) -> AuditTransaction {
        AuditTransaction(stableId: id, date: date, cardStableId: card, merchant: merchant,
                         amount: amount, category: cat, confidence: confidence, flagged: flagged)
    }

    private var cards: [(stableId: String, shortName: String)] {
        [("chase-freedom-unlimited", "Freedom"),
         ("chase-sapphire-reserve", "Reserve"),
         ("robinhood-gold", "Robinhood"),
         ("costco-anywhere-visa", "Costco"),
         ("sams-club-mastercard", "Sam's"),
         ("chase-prime-visa", "Prime")]
    }

    // MARK: - Missed math

    func testMissedMath() {
        // $100 dining on Freedom (1.5x UR = $2.25) vs optimal Reserve (3x = $4.50).
        let txs = [tx("t1", d(2026, 3, 10), "chase-freedom-unlimited", "SOME RESTAURANT", -100, .dining)]
        let r = SpendAuditService.audit(transactions: txs, activeCards: cards,
                                        now: d(2026, 10, 5), calendar: utc)
        XCTAssertEqual(r.opportunities.count, 1)
        let o = r.opportunities[0]
        XCTAssertEqual(o.usedCardId, "chase-freedom-unlimited")
        XCTAssertEqual(o.optimalCardId, "chase-sapphire-reserve")
        XCTAssertEqual(o.usedValueUSD, 2.25, accuracy: 0.001)
        XCTAssertEqual(o.optimalValueUSD, 4.50, accuracy: 0.001)
        XCTAssertEqual(o.missedUSD, 2.25, accuracy: 0.001)
        XCTAssertEqual(r.missedEarnUSD, 2.25, accuracy: 0.001)
        XCTAssertEqual(r.totalMissedUSD, 2.25, accuracy: 0.001)
    }

    func testOptimalAlreadyNoMiss() {
        let txs = [tx("t1", d(2026, 3, 10), "chase-sapphire-reserve", "SOME RESTAURANT", -100, .dining)]
        let r = SpendAuditService.audit(transactions: txs, activeCards: cards,
                                        now: d(2026, 10, 5), calendar: utc)
        XCTAssertTrue(r.opportunities.isEmpty)
        XCTAssertEqual(r.analyzedCount, 1)
    }

    func testDeMinimisFiltersNoise() {
        // $1 "other" on Freedom ($0.015) vs Robinhood 3% ($0.03): missed $0.015 < $0.25.
        let txs = [tx("t1", d(2026, 3, 10), "chase-freedom-unlimited", "RANDOM SHOP", -1, .other)]
        let r = SpendAuditService.audit(transactions: txs, activeCards: cards,
                                        now: d(2026, 10, 5), calendar: utc)
        XCTAssertTrue(r.opportunities.isEmpty)
    }

    func testMerchantBoost() {
        // $100 at Whole Foods on Freedom ($1.50) vs Prime Visa 5% boost ($5).
        let txs = [tx("t1", d(2026, 4, 2), "chase-freedom-unlimited", "WHOLE FOODS MARKET #1023", -100, .groceries)]
        let r = SpendAuditService.audit(transactions: txs, activeCards: cards,
                                        now: d(2026, 10, 5), calendar: utc)
        XCTAssertEqual(r.opportunities.count, 1)
        XCTAssertEqual(r.opportunities[0].optimalCardId, "chase-prime-visa")
        XCTAssertEqual(r.opportunities[0].missedUSD, 3.50, accuracy: 0.001)
    }

    // MARK: - Chronological cap simulation

    func testCapSimulationIsChronological() {
        // $7,000 gas on Costco (5%, cap exactly reached — no miss either way),
        // then $100 gas on Costco: actual drops to 1% ($1), optimal is the
        // next-best card with headroom ($5) → $4 missed.
        let txs = [
            tx("t1", d(2026, 2, 1), "costco-anywhere-visa", "COSTCO GAS", -7000, .gas),
            tx("t2", d(2026, 3, 1), "costco-anywhere-visa", "COSTCO GAS", -100, .gas),
        ]
        let r = SpendAuditService.audit(transactions: txs, activeCards: cards,
                                        now: d(2026, 10, 5), calendar: utc)
        XCTAssertEqual(r.opportunities.count, 1, "only the post-cap transaction should miss")
        XCTAssertEqual(r.opportunities[0].missedUSD, 4.0, accuracy: 0.001)
        XCTAssertEqual(r.opportunities[0].usedValueUSD, 1.0, accuracy: 0.001)
        XCTAssertEqual(r.opportunities[0].optimalValueUSD, 5.0, accuracy: 0.001)
    }

    func testCapOrderMatters() {
        // Same two transactions reversed: the $100 comes first (5% both),
        // the $7,000 second (5% on Costco — cap not yet hit at its date).
        // No misses at all: order must matter.
        let txs = [
            tx("t1", d(2026, 2, 1), "costco-anywhere-visa", "COSTCO GAS", -100, .gas),
            tx("t2", d(2026, 3, 1), "costco-anywhere-visa", "COSTCO GAS", -7000, .gas),
        ]
        let r = SpendAuditService.audit(transactions: txs, activeCards: cards,
                                        now: d(2026, 10, 5), calendar: utc)
        XCTAssertTrue(r.opportunities.isEmpty)
    }

    // MARK: - Exclusions

    func testExclusions() {
        let txs = [
            tx("pay", d(2026, 3, 1), "chase-freedom-unlimited", "PAYMENT THANK YOU", 250, .payment),
            tx("inc", d(2026, 3, 2), "chase-freedom-unlimited", "REFUND", 20, .income),
            tx("flag", d(2026, 3, 3), "chase-freedom-unlimited", "???", -50, .dining, flagged: true),
            tx("low", d(2026, 3, 4), "chase-freedom-unlimited", "???", -50, .dining, confidence: 0.3),
            tx("ok", d(2026, 3, 5), "chase-freedom-unlimited", "DINNER", -100, .dining),
        ]
        let r = SpendAuditService.audit(transactions: txs, activeCards: cards,
                                        now: d(2026, 10, 5), calendar: utc)
        XCTAssertEqual(r.analyzedCount, 1)
        XCTAssertEqual(r.excludedLowConfidence, 2)
        XCTAssertEqual(r.analyzedSpendUSD, 100, accuracy: 0.001)
    }

    // MARK: - Expired credits

    private func doordashBenefit() -> AuditBenefit {
        AuditBenefit(stableId: "dd-reserve", cardStableId: "chase-sapphire-reserve",
                     name: "DoorDash credit", howToUse: "$10 monthly DoorDash promo",
                     cadence: .monthly, amountDisplay: "$10/mo", enrollmentRequired: false)
    }

    /// One dining charge per month Jan–May 2026 (plausible spend for the credit).
    private func monthlyDining() -> [AuditTransaction] {
        (1...5).map { m in
            tx("d\(m)", d(2026, m, 12), "chase-sapphire-reserve", "RESTAURANT", -40, .dining)
        }
    }

    func testExpiredCreditsTallied() {
        // Tracking since Jan 15; now Jun 15 → Jan..May elapsed, none completed.
        let r = SpendAuditService.audit(
            transactions: monthlyDining(), activeCards: cards,
            benefits: [doordashBenefit()],
            trackingStart: d(2026, 1, 15), now: d(2026, 6, 15), calendar: utc)
        XCTAssertEqual(r.expiredCredits.count, 5)
        XCTAssertEqual(r.expiredCreditsUSD, 50, accuracy: 0.001)
        XCTAssertEqual(r.totalMissedUSD, r.missedEarnUSD + 50, accuracy: 0.001)
    }

    func testExpiredCreditsRespectCompletionsAndMutes() {
        let base = SpendAuditService.audit(
            transactions: monthlyDining(), activeCards: cards,
            benefits: [doordashBenefit()],
            completedKeys: ["dd-reserve|2026-03"],
            trackingStart: d(2026, 1, 15), now: d(2026, 6, 15), calendar: utc)
        XCTAssertEqual(base.expiredCredits.count, 4, "completed March is excluded")

        let muted = SpendAuditService.audit(
            transactions: monthlyDining(), activeCards: cards,
            benefits: [doordashBenefit()],
            mutedBenefitIds: ["dd-reserve"],
            trackingStart: d(2026, 1, 15), now: d(2026, 6, 15), calendar: utc)
        XCTAssertTrue(muted.expiredCredits.isEmpty, "muted benefits are excluded")
    }

    func testExpiredCreditSkippedWithoutPlausibleSpend() {
        // Statements exist in March but nothing in dining → can't have used it.
        let txs = [tx("g1", d(2026, 3, 10), "chase-freedom-unlimited", "SHELL", -50, .gas)]
        let r = SpendAuditService.audit(
            transactions: txs, activeCards: cards,
            benefits: [doordashBenefit()],
            trackingStart: d(2026, 3, 1), now: d(2026, 4, 15), calendar: utc)
        XCTAssertTrue(r.expiredCredits.isEmpty, "no plausible dining spend in March")
    }

    func testNoTrackingStartNoExpiredCredits() {
        let r = SpendAuditService.audit(
            transactions: monthlyDining(), activeCards: cards,
            benefits: [doordashBenefit()],
            trackingStart: nil, now: d(2026, 6, 15), calendar: utc)
        XCTAssertTrue(r.expiredCredits.isEmpty, "can't call it expired without tracking")
    }

    // MARK: - Annualization & breakdowns

    func testAnnualization() {
        let txs = [tx("t1", d(2026, 3, 10), "chase-freedom-unlimited", "SOME RESTAURANT", -100, .dining)]
        // Jul 2 = day 183 of 365.
        let r = SpendAuditService.audit(transactions: txs, activeCards: cards,
                                        now: d(2026, 7, 2), calendar: utc)
        XCTAssertEqual(r.totalMissedUSD, 2.25, accuracy: 0.001)
        XCTAssertEqual(r.annualizedProjectionUSD ?? 0, 2.25 * 365.0 / 183.0, accuracy: 0.01)

        let done = SpendAuditService.audit(transactions: txs, activeCards: cards,
                                           now: d(2026, 12, 31), calendar: utc)
        XCTAssertNil(done.annualizedProjectionUSD, "no projection on Dec 31")
    }

    func testBreakdowns() {
        let txs = [
            tx("t1", d(2026, 3, 10), "chase-freedom-unlimited", "SOME RESTAURANT", -100, .dining),
            tx("t2", d(2026, 3, 11), "chase-freedom-unlimited", "WHOLE FOODS", -100, .groceries),
        ]
        let r = SpendAuditService.audit(transactions: txs, activeCards: cards,
                                        now: d(2026, 10, 5), calendar: utc)
        XCTAssertEqual(r.missedByCategory.count, 2)
        XCTAssertEqual(r.missedByUsedCard.count, 1)
        XCTAssertEqual(r.missedByUsedCard[0].0, "chase-freedom-unlimited")
        XCTAssertEqual(r.missedByUsedCard[0].2, 2.25 + 3.50, accuracy: 0.001)
    }

    func testEmptyLedger() {
        let r = SpendAuditService.audit(transactions: [], activeCards: cards,
                                        now: d(2026, 10, 5), calendar: utc)
        XCTAssertEqual(r.totalMissedUSD, 0)
        XCTAssertEqual(r.analyzedCount, 0)
        XCTAssertTrue(r.opportunities.isEmpty)
    }
}
