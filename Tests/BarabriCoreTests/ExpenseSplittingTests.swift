import XCTest
@testable import BarabriCore

final class ExpenseSplittingTests: XCTestCase {
    let ali = ParticipantID("Ali")
    let ahmed = ParticipantID("Ahmed")
    let bilal = ParticipantID("Bilal")

    func testEqualSplitDividesTotalAmongParticipants() throws {
        let result = try EqualSplitStrategy().allocate(
            total: 3000,
            participants: [ali, ahmed, bilal]
        )

        XCTAssertEqual(result[ali], 1000)
        XCTAssertEqual(result[ahmed], 1000)
        XCTAssertEqual(result[bilal], 1000)
    }

    func testEqualSplitHandlesRoundingWithoutLosingMoney() throws {
        let result = try EqualSplitStrategy().allocate(
            total: 100,
            participants: [ali, ahmed, bilal]
        )

        XCTAssertEqual(result.values.reduce(0, +), 100)
    }

    func testExactSplitRejectsIncorrectTotal() {
        let strategy = ExactAmountSplitStrategy(requestedAllocations: [ali: 100, ahmed: 100])
        XCTAssertThrowsError(try strategy.allocate(total: 300, participants: [ali, ahmed])) { error in
            XCTAssertEqual(error as? BarabriError, .invalidAllocationTotal)
        }
    }

    func testPercentageSplitAllocatesAndPreservesTotal() throws {
        let strategy = PercentageSplitStrategy(percentages: [ali: 50, ahmed: 30, bilal: 20])
        let result = try strategy.allocate(total: 1000, participants: [ali, ahmed, bilal])

        XCTAssertEqual(result[ali], 500)
        XCTAssertEqual(result.values.reduce(0, +), 1000)
    }
}
