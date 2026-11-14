import XCTest
@testable import BarabriCore

final class SplitValidationTests: XCTestCase {
    let ali = ParticipantID("Ali")
    let ahmed = ParticipantID("Ahmed")
    let bilal = ParticipantID("Bilal")

    // MARK: Duplicate participants

    func testEqualSplitRejectsDuplicateParticipant() {
        XCTAssertThrowsError(try EqualSplitStrategy().allocate(total: 300, participants: [ali, ali, ahmed])) { error in
            XCTAssertEqual(error as? BarabriError, .duplicateParticipant)
        }
    }

    func testExactSplitRejectsDuplicateParticipant() {
        let strategy = ExactAmountSplitStrategy(requestedAllocations: [ali: 100])
        XCTAssertThrowsError(try strategy.allocate(total: 100, participants: [ali, ali])) { error in
            XCTAssertEqual(error as? BarabriError, .duplicateParticipant)
        }
    }

    func testPercentageSplitRejectsDuplicateParticipant() {
        let strategy = PercentageSplitStrategy(percentages: [ali: 100])
        XCTAssertThrowsError(try strategy.allocate(total: 100, participants: [ali, ali])) { error in
            XCTAssertEqual(error as? BarabriError, .duplicateParticipant)
        }
    }

    // MARK: Keys that do not match participants

    func testExactSplitRejectsAllocationForUnknownParticipant() {
        let strategy = ExactAmountSplitStrategy(requestedAllocations: [ali: 60, ahmed: 40, bilal: 0])
        XCTAssertThrowsError(try strategy.allocate(total: 100, participants: [ali, ahmed])) { error in
            XCTAssertEqual(error as? BarabriError, .participantNotFound)
        }
    }

    func testExactSplitRejectsMissingAllocationForParticipant() {
        let strategy = ExactAmountSplitStrategy(requestedAllocations: [ali: 50, ahmed: 50])
        XCTAssertThrowsError(try strategy.allocate(total: 100, participants: [ali, ahmed, bilal])) { error in
            XCTAssertEqual(error as? BarabriError, .participantNotFound)
        }
    }

    func testPercentageSplitRejectsPercentageKeysThatDoNotMatchParticipants() {
        let strategy = PercentageSplitStrategy(percentages: [ali: 50, ahmed: 50])
        XCTAssertThrowsError(try strategy.allocate(total: 100, participants: [ali, ahmed, bilal])) { error in
            XCTAssertEqual(error as? BarabriError, .participantNotFound)
        }
    }

    // MARK: Negative values

    func testExactSplitRejectsNegativeAllocationAsInvalidAmount() {
        let strategy = ExactAmountSplitStrategy(requestedAllocations: [ali: 150, ahmed: -50])
        XCTAssertThrowsError(try strategy.allocate(total: 100, participants: [ali, ahmed])) { error in
            XCTAssertEqual(error as? BarabriError, .invalidAmount)
        }
    }

    func testPercentageSplitRejectsNegativePercentageAsInvalidAmount() {
        let strategy = PercentageSplitStrategy(percentages: [ali: 150, ahmed: -50])
        XCTAssertThrowsError(try strategy.allocate(total: 100, participants: [ali, ahmed])) { error in
            XCTAssertEqual(error as? BarabriError, .invalidAmount)
        }
    }

    // MARK: Non-positive total

    func testEqualSplitRejectsZeroTotal() {
        XCTAssertThrowsError(try EqualSplitStrategy().allocate(total: 0, participants: [ali, ahmed])) { error in
            XCTAssertEqual(error as? BarabriError, .invalidAmount)
        }
    }

    func testEqualSplitRejectsNegativeTotal() {
        XCTAssertThrowsError(try EqualSplitStrategy().allocate(total: -100, participants: [ali, ahmed])) { error in
            XCTAssertEqual(error as? BarabriError, .invalidAmount)
        }
    }

    func testExactSplitRejectsZeroTotal() {
        let strategy = ExactAmountSplitStrategy(requestedAllocations: [ali: 0])
        XCTAssertThrowsError(try strategy.allocate(total: 0, participants: [ali])) { error in
            XCTAssertEqual(error as? BarabriError, .invalidAmount)
        }
    }

    func testExactSplitRejectsNegativeTotal() {
        let strategy = ExactAmountSplitStrategy(requestedAllocations: [ali: -100])
        XCTAssertThrowsError(try strategy.allocate(total: -100, participants: [ali])) { error in
            XCTAssertEqual(error as? BarabriError, .invalidAmount)
        }
    }

    func testPercentageSplitRejectsZeroTotal() {
        let strategy = PercentageSplitStrategy(percentages: [ali: 100])
        XCTAssertThrowsError(try strategy.allocate(total: 0, participants: [ali])) { error in
            XCTAssertEqual(error as? BarabriError, .invalidAmount)
        }
    }

    func testPercentageSplitRejectsNegativeTotal() {
        let strategy = PercentageSplitStrategy(percentages: [ali: 100])
        XCTAssertThrowsError(try strategy.allocate(total: -100, participants: [ali])) { error in
            XCTAssertEqual(error as? BarabriError, .invalidAmount)
        }
    }

    // MARK: Empty participants

    func testEqualSplitRejectsEmptyParticipants() {
        XCTAssertThrowsError(try EqualSplitStrategy().allocate(total: 100, participants: [])) { error in
            XCTAssertEqual(error as? BarabriError, .noParticipants)
        }
    }

    func testExactSplitRejectsEmptyParticipants() {
        let strategy = ExactAmountSplitStrategy(requestedAllocations: [:])
        XCTAssertThrowsError(try strategy.allocate(total: 100, participants: [])) { error in
            XCTAssertEqual(error as? BarabriError, .noParticipants)
        }
    }

    func testPercentageSplitRejectsEmptyParticipants() {
        let strategy = PercentageSplitStrategy(percentages: [:])
        XCTAssertThrowsError(try strategy.allocate(total: 100, participants: [])) { error in
            XCTAssertEqual(error as? BarabriError, .noParticipants)
        }
    }

    // MARK: Totals that do not add up

    func testPercentageSplitRejectsPercentagesNotSummingToHundred() {
        let strategy = PercentageSplitStrategy(percentages: [
            ali: Decimal(string: "50")!,
            ahmed: Decimal(string: "30")!,
            bilal: Decimal(string: "19")!
        ])
        XCTAssertThrowsError(try strategy.allocate(total: 1000, participants: [ali, ahmed, bilal])) { error in
            XCTAssertEqual(error as? BarabriError, .invalidPercentageTotal)
        }
    }

    func testExactSplitRejectsAllocationsLessThanTotal() {
        let strategy = ExactAmountSplitStrategy(requestedAllocations: [ali: 30, ahmed: 30])
        XCTAssertThrowsError(try strategy.allocate(total: 100, participants: [ali, ahmed])) { error in
            XCTAssertEqual(error as? BarabriError, .invalidAllocationTotal)
        }
    }

    // MARK: Rounding

    func testPercentageSplitRoundedSharesSumExactlyToTotal() throws {
        let strategy = PercentageSplitStrategy(percentages: [
            ali: Decimal(string: "33.33")!,
            ahmed: Decimal(string: "33.33")!,
            bilal: Decimal(string: "33.34")!
        ])
        let result = try strategy.allocate(total: 100, participants: [ali, ahmed, bilal])

        XCTAssertEqual(result.values.reduce(0, +), 100)
    }

    func testEqualSplitOfHundredAmongThreeUsesTwoDecimalShares() throws {
        let result = try EqualSplitStrategy().allocate(total: 100, participants: [ali, ahmed, bilal])
        let validShares = [Decimal(string: "33.33")!, Decimal(string: "33.34")!]

        for value in result.values {
            XCTAssertTrue(validShares.contains(value), "Unexpected share \(value)")
        }
        XCTAssertEqual(result.values.reduce(0, +), 100)
    }
}
