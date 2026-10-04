import XCTest
@testable import PerkPilot

// MARK: - StatementParser tests (pure functions, no SwiftData)

final class StatementParserTests: XCTestCase {
    func testChaseCSV() {
        let csv = """
        Transaction Date,Post Date,Description,Category,Type,Amount,Memo
        10/01/2026,10/02/2026,UBER TRIP,Travel,Sale,-15.00,
        10/03/2026,10/04/2026,WHOLE FOODS #1042,Groceries,Sale,-86.42,
        10/05/2026,10/05/2026,PAYMENT THANK YOU,Payments,Payment,250.00,
        """
        let r = StatementParser.parseCSV(csv)
        XCTAssertFalse(r.needsManualMapping)
        XCTAssertEqual(r.detectedProfile, "Chase")
        XCTAssertEqual(r.transactions.count, 3)
        XCTAssertEqual(r.transactions[0].description, "UBER TRIP")
        XCTAssertEqual(r.transactions[0].amount, -15.00, accuracy: 0.001)  // negative = charge
        XCTAssertEqual(r.transactions[2].amount, 250.00, accuracy: 0.001)   // payment = money in
        XCTAssertTrue(r.warnings.isEmpty)
    }

    func testAmexCSVPositiveIsCharge() {
        let csv = """
        Date,Description,Card Member,Account #,Amount
        10/01/2026,RESY RESTAURANT,JOHN DOE,12345,42.50
        10/02/2026,PAYMENT RECEIVED,JOHN DOE,12345,-42.50
        """
        let r = StatementParser.parseCSV(csv)
        XCTAssertFalse(r.needsManualMapping)
        XCTAssertEqual(r.transactions.count, 2)
        // Amex shows charges positive → normalized to negative (money out).
        XCTAssertEqual(r.transactions[0].amount, -42.50, accuracy: 0.001)
        XCTAssertEqual(r.transactions[1].amount, 42.50, accuracy: 0.001)
    }

    func testCitiDebitCreditColumns() {
        let csv = """
        Status,Date,Description,Debit,Credit,Member Name
        Posted,10/01/2026,SHELL OIL,55.10,,JOHN
        Posted,10/02/2026,REFUND,,12.00,JOHN
        """
        let r = StatementParser.parseCSV(csv)
        XCTAssertFalse(r.needsManualMapping)
        XCTAssertEqual(r.transactions.count, 2)
        XCTAssertEqual(r.transactions[0].amount, -55.10, accuracy: 0.001)
        XCTAssertEqual(r.transactions[1].amount, 12.00, accuracy: 0.001)
    }

    func testUnknownLayoutRequestsManualMapping() {
        let csv = """
        Day,Note,Value
        10/01/2026,Coffee,5.00
        """
        let r = StatementParser.parseCSV(csv)
        XCTAssertTrue(r.needsManualMapping)
        XCTAssertTrue(r.transactions.isEmpty)
        XCTAssertEqual(r.headers, ["Day", "Note", "Value"])
    }

    func testManualMappingFallback() {
        let csv = """
        Day,Note,Value
        10/01/2026,Coffee,-5.00
        not-a-date,Broken,abc
        """
        let mapping = ColumnMapping(date: 0, description: 1, amount: 2, negativeIsCharge: true)
        let r = StatementParser.parseCSV(csv, mapping: mapping)
        XCTAssertFalse(r.needsManualMapping)
        XCTAssertEqual(r.transactions.count, 1)
        XCTAssertEqual(r.warnings.count, 1)  // bad row reported, never invented
        XCTAssertTrue(r.warnings[0].contains("Line 3"))
    }

    func testSkipsBlankAndZeroRows() {
        let csv = """
        Transaction Date,Post Date,Description,Category,Type,Amount,Memo
        10/01/2026,10/02/2026,UBER TRIP,Travel,Sale,-15.00,

        10/03/2026,10/04/2026,BALANCE MARKER,Other,Sale,0.00,
        """
        let r = StatementParser.parseCSV(csv)
        XCTAssertEqual(r.transactions.count, 1)
    }

    func testQuotedCommas() {
        let csv = """
        Date,Description,Amount
        10/01/2026,"WHOLE FOODS, INC #1042",-86.42
        """
        // Matches the Amex-shaped profile (Date/Description/Amount).
        let r = StatementParser.parseCSV(csv)
        XCTAssertFalse(r.needsManualMapping)
        XCTAssertEqual(r.transactions.count, 1)
        XCTAssertEqual(r.transactions[0].description, "WHOLE FOODS, INC #1042")
    }

    func testParseAmountVariants() {
        XCTAssertEqual(StatementParser.parseAmount("$1,234.56"), 1234.56)
        XCTAssertEqual(StatementParser.parseAmount("(123.45)"), -123.45)
        XCTAssertEqual(StatementParser.parseAmount("-15.00"), -15.00)
        XCTAssertNil(StatementParser.parseAmount(""))
        XCTAssertNil(StatementParser.parseAmount("N/A"))
    }

    func testParseDateVariants() {
        XCTAssertNotNil(StatementParser.parseDate("10/01/2026"))
        XCTAssertNotNil(StatementParser.parseDate("2026-10-01"))
        XCTAssertNotNil(StatementParser.parseDate("Oct 1, 2026"))
        XCTAssertNil(StatementParser.parseDate("not a date"))
        XCTAssertNil(StatementParser.parseDate(""))
    }
}

// MARK: - CategoryEngine tests

final class CategoryEngineTests: XCTestCase {
    func testNormalizeMerchant() {
        XCTAssertEqual(CategoryEngine.normalizeMerchant("UBER TRIP #1234"), "UBER TRIP")
        XCTAssertEqual(CategoryEngine.normalizeMerchant("Whole Foods, Inc."), "WHOLE FOODS INC")
        XCTAssertEqual(CategoryEngine.normalizeMerchant("  chipotle  "), "CHIPOTLE")
    }

    func testKeywordCategories() {
        XCTAssertEqual(CategoryEngine.categorize(rawMerchant: "DOORDASH").category, .dining)
        XCTAssertEqual(CategoryEngine.categorize(rawMerchant: "TRADER JOE'S").category, .groceries)
        XCTAssertEqual(CategoryEngine.categorize(rawMerchant: "SHELL OIL 5744").category, .gas)
        XCTAssertEqual(CategoryEngine.categorize(rawMerchant: "DELTA AIR LINES").category, .travel)
        XCTAssertEqual(CategoryEngine.categorize(rawMerchant: "AMAZON MKTPLACE").category, .shopping)
        XCTAssertEqual(CategoryEngine.categorize(rawMerchant: "COMCAST").category, .bills)
        XCTAssertEqual(CategoryEngine.categorize(rawMerchant: "CVS PHARMACY").category, .health)
        XCTAssertEqual(CategoryEngine.categorize(rawMerchant: "NETFLIX.COM").category, .entertainment)
    }

    func testPaymentsAreNotSpend() {
        let (cat, _) = CategoryEngine.categorize(rawMerchant: "AUTOPAY PAYMENT THANK YOU")
        XCTAssertEqual(cat, .payment)
        XCTAssertFalse(cat.isSpend)
    }

    func testUberEatsIsDiningNotTravel() {
        // "UBER EATS" must not be shadowed by the "UBER" → travel rule.
        XCTAssertEqual(CategoryEngine.categorize(rawMerchant: "UBER EATS").category, .dining)
        XCTAssertEqual(CategoryEngine.categorize(rawMerchant: "UBER TRIP").category, .travel)
    }

    func testAppleBillIsBillsNotShopping() {
        XCTAssertEqual(CategoryEngine.categorize(rawMerchant: "APPLE.COM/BILL").category, .bills)
        XCTAssertEqual(CategoryEngine.categorize(rawMerchant: "APPLE STORE").category, .shopping)
    }

    func testOverrideWins() {
        let (cat, conf) = CategoryEngine.categorize(
            normalizedMerchant: CategoryEngine.normalizeMerchant("COSTCO GAS"),
            override: .groceries
        )
        XCTAssertEqual(cat, .groceries)
        XCTAssertEqual(conf, 1.0)
    }

    func testUnknownMerchantIsOther() {
        let (cat, conf) = CategoryEngine.categorize(rawMerchant: "ZZZ RANDOM LLC")
        XCTAssertEqual(cat, .other)
        XCTAssertLessThan(conf, 0.5)
    }
}

// MARK: - RewardMatcher tests

final class RewardMatcherTests: XCTestCase {
    private func benefit(stableId: String, name: String, amount: String, cadence: String = "monthly") -> BenefitItem {
        BenefitItem(stableId: stableId, name: name, cadenceRaw: cadence,
                    amountDisplay: amount, howToUse: "", enrollmentRequired: false, lesserKnown: false)
    }

    private func tx(merchant: String, amount: Double, date: Date = Date()) -> BankTransaction {
        BankTransaction(cardStableId: "c", date: date, merchantRaw: merchant,
                        amount: amount, category: .dining)
    }

    func testExpectedAmountParsing() {
        XCTAssertEqual(RewardMatcher.expectedAmount(for: benefit(stableId: "x", name: "X", amount: "$15/mo")), 15)
        // Annual figure divided to monthly cadence.
        XCTAssertEqual(RewardMatcher.expectedAmount(for: benefit(stableId: "x", name: "X", amount: "$120/yr")) ?? -1, 10, accuracy: 0.001)
        XCTAssertNil(RewardMatcher.expectedAmount(for: benefit(stableId: "x", name: "X", amount: "Included")))
    }

    func testHighConfidenceMatch() {
        let b = benefit(stableId: "amex-uber-cash", name: "Uber Cash", amount: "$15/mo")
        let t = tx(merchant: "UBER TRIP HELP.UBER.COM", amount: -15.00)
        let s = RewardMatcher.evaluate(benefit: b, transactions: [t], periodKey: "2026-10", alreadyCompleted: false)
        if case .likelyReceived(let conf, _, _) = s {
            XCTAssertEqual(conf, .high)
        } else {
            XCTFail("expected likelyReceived, got \(s)")
        }
    }

    func testNotDetectedWhenNothingMatches() {
        let b = benefit(stableId: "amex-uber-cash", name: "Uber Cash", amount: "$15/mo")
        let t = tx(merchant: "STARBUCKS", amount: -6.50)
        let s = RewardMatcher.evaluate(benefit: b, transactions: [t], periodKey: "2026-10", alreadyCompleted: false)
        if case .notDetected = s { } else { XCTFail("expected notDetected") }
    }

    func testNoStatements() {
        let b = benefit(stableId: "x", name: "X", amount: "$10/mo")
        let s = RewardMatcher.evaluate(benefit: b, transactions: [], periodKey: "2026-10", alreadyCompleted: false)
        if case .noStatements = s { } else { XCTFail("expected noStatements") }
    }

    func testManualConfirmationShortCircuits() {
        let b = benefit(stableId: "x", name: "X", amount: "$10/mo")
        let s = RewardMatcher.evaluate(benefit: b, transactions: [], periodKey: "2026-10", alreadyCompleted: true)
        if case .manuallyConfirmed = s { } else { XCTFail("expected manuallyConfirmed") }
    }
}
