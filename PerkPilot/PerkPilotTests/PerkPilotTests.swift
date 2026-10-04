import XCTest
@testable import PerkPilot

// MARK: - Calendar math is a release blocker: month/quarter/half/year
// boundaries, leap years, and one-time/per-use exclusion.

final class RecurrenceEngineTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Detroit")!
        return c
    }()

    private func date(_ string: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        return f.date(from: string)!
    }

    func testMonthlyPeriodKey() {
        XCTAssertEqual(
            RecurrenceEngine.periodKey(cadence: .monthly, date: date("2026-10-04"), calendar: calendar),
            "2026-10"
        )
        XCTAssertEqual(
            RecurrenceEngine.periodKey(cadence: .monthly, date: date("2026-01-31"), calendar: calendar),
            "2026-01"
        )
    }

    func testQuarterlyBoundaries() {
        XCTAssertEqual(
            RecurrenceEngine.periodKey(cadence: .quarterly, date: date("2026-03-31"), calendar: calendar),
            "2026-Q1"
        )
        XCTAssertEqual(
            RecurrenceEngine.periodKey(cadence: .quarterly, date: date("2026-04-01"), calendar: calendar),
            "2026-Q2"
        )
        XCTAssertEqual(
            RecurrenceEngine.periodKey(cadence: .quarterly, date: date("2026-12-31"), calendar: calendar),
            "2026-Q4"
        )
    }

    func testSemiannualBoundaries() {
        XCTAssertEqual(
            RecurrenceEngine.periodKey(cadence: .semiannual, date: date("2026-06-30"), calendar: calendar),
            "2026-H1"
        )
        XCTAssertEqual(
            RecurrenceEngine.periodKey(cadence: .semiannual, date: date("2026-07-01"), calendar: calendar),
            "2026-H2"
        )
    }

    func testAnnualPeriodKey() {
        XCTAssertEqual(
            RecurrenceEngine.periodKey(cadence: .annual, date: date("2026-12-31"), calendar: calendar),
            "2026"
        )
    }

    func testLeapDay() {
        XCTAssertEqual(
            RecurrenceEngine.periodKey(cadence: .monthly, date: date("2024-02-29"), calendar: calendar),
            "2024-02"
        )
        XCTAssertEqual(
            RecurrenceEngine.periodKey(cadence: .quarterly, date: date("2024-02-29"), calendar: calendar),
            "2024-Q1"
        )
    }

    func testNonRecurringCadencesProduceNoKey() {
        XCTAssertNil(RecurrenceEngine.periodKey(cadence: .oneTime, date: date("2026-10-04"), calendar: calendar))
        XCTAssertNil(RecurrenceEngine.periodKey(cadence: .perUse, date: date("2026-10-04"), calendar: calendar))
    }

    func testPeriodLabels() {
        XCTAssertEqual(
            RecurrenceEngine.periodLabel(cadence: .monthly, date: date("2026-10-04"), calendar: calendar),
            "October 2026"
        )
        XCTAssertEqual(
            RecurrenceEngine.periodLabel(cadence: .quarterly, date: date("2026-10-04"), calendar: calendar),
            "Q4 2026"
        )
        XCTAssertEqual(
            RecurrenceEngine.periodLabel(cadence: .semiannual, date: date("2026-10-04"), calendar: calendar),
            "H2 2026"
        )
        XCTAssertEqual(
            RecurrenceEngine.periodLabel(cadence: .annual, date: date("2026-10-04"), calendar: calendar),
            "2026"
        )
    }

    func testMonthlyPeriodRange() {
        let range = RecurrenceEngine.periodRange(cadence: .monthly, date: date("2026-10-04"), calendar: calendar)!
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        XCTAssertEqual(f.string(from: range.start), "2026-10-01")
        XCTAssertEqual(f.string(from: range.end), "2026-11-01")
    }
}

// MARK: - Seed contract: the bundled catalog must decode cleanly and match
// the researched counts. SeedData.json is in the test target's resources.

final class SeedContractTests: XCTestCase {
    private func loadManifest() throws -> SeedManifest {
        // Catalog ships as two manifests (see SeedLoader); merge like the app does.
        let bundle = Bundle(for: Self.self)
        var cards: [SeedCard] = []
        var version = "unknown"
        for name in ["SeedData-A", "SeedData-B"] {
            guard let url = bundle.url(forResource: name, withExtension: "json") else {
                throw SeedError.missingBundle
            }
            let data = try Data(contentsOf: url)
            let part = try JSONDecoder().decode(SeedManifest.self, from: data)
            version = part.catalogVersion
            cards += part.cards
        }
        return SeedManifest(
            catalogVersion: version,
            schemaVersion: 1,
            locale: "en-US",
            exportedAt: "",
            cardCount: cards.count,
            benefitCount: cards.flatMap(\.benefits).count,
            checksum: "merged",
            cards: cards
        )
    }

    func testSeedCounts() throws {
        let manifest = try loadManifest()
        XCTAssertEqual(manifest.cards.count, 12)
        XCTAssertEqual(manifest.cards.flatMap(\.benefits).count, 238)
    }

    func testSeedValidationPasses() throws {
        let manifest = try loadManifest()
        XCTAssertNoThrow(try SeedLoader.validate(manifest))
    }

    func testExpectedPerCardCounts() throws {
        let expected: [String: Int] = [
            "amex-platinum": 36, "chase-sapphire-reserve": 23, "chase-sapphire-preferred": 23,
            "chase-ink-business-preferred": 17, "delta-skymiles-reserve": 25, "robinhood-gold": 14,
            "costco-anywhere-visa": 15, "chase-prime-visa": 20, "sams-club-mastercard": 11,
            "southwest-premier": 17, "chase-freedom-unlimited": 19, "chase-ink-business-unlimited": 18,
        ]
        let manifest = try loadManifest()
        for card in manifest.cards {
            XCTAssertEqual(card.benefits.count, expected[card.stableId], "card \(card.stableId)")
        }
    }

    func testEveryBenefitHasASource() throws {
        let manifest = try loadManifest()
        for benefit in manifest.cards.flatMap(\.benefits) {
            XCTAssertFalse(benefit.sources.isEmpty, "benefit \(benefit.stableId) has no source")
        }
    }
}
