import XCTest
@testable import PerkPilot

// MARK: - AskParser tests

final class AskParserTests: XCTestCase {

    func testRestaurantSpend() {
        let q = AskParser.parse("$200 restaurant spend, which card should I use?")
        XCTAssertEqual(q.amount, 200)
        XCTAssertEqual(q.category, .dining)
        XCTAssertTrue(q.isComplete)
        XCTAssertNil(q.clarifyingQuestion)
    }

    func testGymMembershipDollars() {
        let q = AskParser.parse("which card for a 400 dollar gym membership?")
        XCTAssertEqual(q.amount, 400)
        XCTAssertEqual(q.category, .health)
        XCTAssertEqual(q.merchant, "GYM")
    }

    func testAmountAfterVerb() {
        let q = AskParser.parse("I have a 85$ dinner bill, best card?")
        XCTAssertEqual(q.amount, 85)
        XCTAssertEqual(q.category, .dining)
    }

    func testBucks() {
        let q = AskParser.parse("150 bucks on groceries")
        XCTAssertEqual(q.amount, 150)
        XCTAssertEqual(q.category, .groceries)
    }

    func testMissingAmountAsksHowMuch() {
        let q = AskParser.parse("where should I buy gas?")
        XCTAssertNil(q.amount)
        XCTAssertEqual(q.category, .gas)
        XCTAssertEqual(q.clarifyingQuestion, "How much is the spend?")
    }

    func testMissingCategoryAsksKind() {
        let q = AskParser.parse("$100")
        XCTAssertEqual(q.amount, 100)
        XCTAssertNil(q.category)
        XCTAssertTrue(q.clarifyingQuestion?.contains("What kind of spend") == true)
    }

    func testBothMissing() {
        let q = AskParser.parse("which card should I use?")
        XCTAssertNotNil(q.clarifyingQuestion)
    }

    func testMerchantDetection() {
        let q = AskParser.parse("doordash order $35")
        XCTAssertEqual(q.amount, 35)
        XCTAssertEqual(q.category, .dining)
        XCTAssertEqual(q.merchant, "DOORDASH")
    }

    func testMergeFillsGaps() {
        let pending = AskQuery(amount: nil, category: .dining, merchant: nil, merchantDisplay: nil)
        let merged = pending.merged(with: AskParser.parse("200"))
        XCTAssertEqual(merged.amount, 200)
        XCTAssertEqual(merged.category, .dining)
        XCTAssertTrue(merged.isComplete)
    }

    func testMergePrefersNewTopic() {
        let pending = AskQuery(amount: 200, category: .dining, merchant: nil, merchantDisplay: nil)
        let merged = pending.merged(with: AskParser.parse("actually $300 for gas"))
        XCTAssertEqual(merged.amount, 300)
        XCTAssertEqual(merged.category, .gas)
    }
}

// MARK: - AskAnswerer tests

final class AskAnswererTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func cardWithDoorDash() -> CardItem {
        let benefit = BenefitItem(
            stableId: "csr-doordash", name: "DoorDash credit",
            cadenceRaw: "monthly", amountDisplay: "$35 per month",
            howToUse: "Enroll, then use at DoorDash for restaurant delivery",
            enrollmentRequired: true, lesserKnown: false
        )
        return CardItem(
            stableId: "chase-sapphire-reserve", canonicalName: "Chase Sapphire Reserve",
            issuer: "Chase", annualFeeDisplay: "$795", benefits: [benefit]
        )
    }

    private func cardWithEquinox() -> CardItem {
        let benefit = BenefitItem(
            stableId: "plat-equinox", name: "Equinox credit",
            cadenceRaw: "annual", amountDisplay: "Up to $300 per calendar year",
            howToUse: "Enroll, then apply toward an Equinox gym membership",
            enrollmentRequired: true, lesserKnown: false
        )
        return CardItem(
            stableId: "amex-platinum", canonicalName: "American Express Platinum Card",
            issuer: "American Express", annualFeeDisplay: "$895", benefits: [benefit]
        )
    }

    func testExpiringCreditBeatsEarnRate() {
        let card = cardWithDoorDash()
        let query = AskQuery(amount: 200, category: .dining, merchant: nil, merchantDisplay: nil)
        let answer = AskAnswerer.answer(
            query: query, cards: [card], mutedIds: [], completedKeys: Set<String>(),
            ytd: [:], now: date(2026, 10, 4)
        )
        XCTAssertNotNil(answer)
        XCTAssertEqual(answer?.credits.first?.benefit.stableId, "csr-doordash")
        XCTAssertTrue(answer?.headline.contains("Reserve") == true)
        XCTAssertTrue(answer?.headline.contains("beats any earn rate") == true)
    }

    func testUsedCreditIsNotSuggested() {
        let card = cardWithDoorDash()
        let query = AskQuery(amount: 200, category: .dining, merchant: nil, merchantDisplay: nil)
        let answer = AskAnswerer.answer(
            query: query, cards: [card], mutedIds: [],
            completedKeys: ["csr-doordash|2026-10"], ytd: [:], now: date(2026, 10, 4)
        )
        XCTAssertTrue(answer?.credits.isEmpty == true)
        // Falls back to earn ranking.
        XCTAssertEqual(answer?.ranked.first?.cardStableId, "chase-sapphire-reserve")
    }

    func testMutedCreditIsNotSuggested() {
        let card = cardWithDoorDash()
        let query = AskQuery(amount: 50, category: .dining, merchant: "DOORDASH", merchantDisplay: "DoorDash")
        let answer = AskAnswerer.answer(
            query: query, cards: [card], mutedIds: ["csr-doordash"],
            completedKeys: [], ytd: [:], now: date(2026, 10, 4)
        )
        XCTAssertTrue(answer?.credits.isEmpty == true)
    }

    func testGymEquinoxCase() {
        let card = cardWithEquinox()
        let query = AskQuery(amount: 400, category: .health, merchant: "GYM", merchantDisplay: "gym")
        let answer = AskAnswerer.answer(
            query: query, cards: [card], mutedIds: [],
            completedKeys: [], ytd: [:], now: date(2026, 10, 4)
        )
        XCTAssertEqual(answer?.credits.first?.benefit.stableId, "plat-equinox")
        XCTAssertTrue(answer?.headline.contains("Platinum") == true)
        XCTAssertTrue(answer?.headline.contains("enrolled") == true)
    }

    func testOnlyOwnedCardsRanked() {
        let card = cardWithDoorDash()
        let query = AskQuery(amount: 200, category: .dining, merchant: nil, merchantDisplay: nil)
        let answer = AskAnswerer.answer(
            query: query, cards: [card], mutedIds: [],
            completedKeys: [], ytd: [:], now: date(2026, 10, 4)
        )
        let owned = Set([card.stableId])
        XCTAssertTrue(answer?.ranked.allSatisfy { owned.contains($0.cardStableId) } == true)
    }

    func testFirstDollarAmount() {
        XCTAssertEqual(AskAnswerer.firstDollarAmount(in: "Up to $300 per calendar year"), 300)
        XCTAssertEqual(AskAnswerer.firstDollarAmount(in: "$35 per month"), 35)
        XCTAssertEqual(AskAnswerer.firstDollarAmount(in: "3x dining"), 0)
    }

    func testIncompleteQueryReturnsNil() {
        let card = cardWithDoorDash()
        let query = AskQuery(amount: 200, category: nil, merchant: nil, merchantDisplay: nil)
        XCTAssertNil(AskAnswerer.answer(
            query: query, cards: [card], mutedIds: [],
            completedKeys: [], ytd: [:], now: date(2026, 10, 4)
        ))
    }
}
