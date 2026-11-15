import XCTest
@testable import BarabriCore

final class SplitStrategyCreatorTests: XCTestCase {
    let ali = ParticipantID("Ali")
    let ahmed = ParticipantID("Ahmed")
    let bilal = ParticipantID("Bilal")

    // MARK: Factory method products

    func testEqualSplitCreatorMakesEqualSplitStrategy() {
        let strategy = EqualSplitCreator().makeStrategy()
        XCTAssertTrue(strategy is EqualSplitStrategy)
    }

    func testExactAmountSplitCreatorMakesStrategyWithSameAllocations() {
        let allocations: Allocations = [ali: 60, ahmed: 40]
        let strategy = ExactAmountSplitCreator(allocations: allocations).makeStrategy()

        let exact = strategy as? ExactAmountSplitStrategy
        XCTAssertNotNil(exact)
        XCTAssertEqual(exact?.requestedAllocations, allocations)
    }

    func testPercentageSplitCreatorMakesStrategyWithSamePercentages() {
        let percentages: [ParticipantID: Decimal] = [
            ali: Decimal(string: "50")!,
            ahmed: Decimal(string: "30")!,
            bilal: Decimal(string: "20")!
        ]
        let strategy = PercentageSplitCreator(percentages: percentages).makeStrategy()

        let percentage = strategy as? PercentageSplitStrategy
        XCTAssertNotNil(percentage)
        XCTAssertEqual(percentage?.percentages, percentages)
    }

    // MARK: SplitType to creator mapping

    func testEqualSplitTypeHasEqualSplitCreator() {
        XCTAssertTrue(SplitType.equal.creator is EqualSplitCreator)
    }

    func testExactSplitTypeHasExactAmountSplitCreator() {
        let allocations: Allocations = [ali: 100]
        XCTAssertTrue(SplitType.exact(allocations).creator is ExactAmountSplitCreator)
    }

    func testPercentageSplitTypeHasPercentageSplitCreator() {
        let percentages: [ParticipantID: Decimal] = [ali: 100]
        XCTAssertTrue(SplitType.percentage(percentages).creator is PercentageSplitCreator)
    }

    // MARK: Operation that uses the factory method

    func testEqualSplitCreatorAllocatesEvenly() throws {
        let result = try EqualSplitCreator().allocate(total: 3000, participants: [ali, ahmed, bilal])

        XCTAssertEqual(result[ali], 1000)
        XCTAssertEqual(result[ahmed], 1000)
        XCTAssertEqual(result[bilal], 1000)
    }

    func testPercentageSplitTypeCreatorAllocatesByPercentage() throws {
        let percentages: [ParticipantID: Decimal] = [ali: 50, ahmed: 30, bilal: 20]
        let result = try SplitType.percentage(percentages).creator.allocate(
            total: 1000,
            participants: [ali, ahmed, bilal]
        )

        XCTAssertEqual(result[ali], 500)
        XCTAssertEqual(result[ahmed], 300)
        XCTAssertEqual(result[bilal], 200)
    }

    func testCreatorPropagatesStrategyErrors() {
        let creator = ExactAmountSplitCreator(allocations: [ali: 100, ahmed: 100])
        XCTAssertThrowsError(try creator.allocate(total: 300, participants: [ali, ahmed])) { error in
            XCTAssertEqual(error as? BarabriError, .invalidAllocationTotal)
        }
    }

    // MARK: Open/closed check

    func testNewSplitRuleCanBeAddedWithoutChangingLibraryCode() throws {
        let result = try PayerPaysAllCreator().allocate(total: 900, participants: [ali, ahmed])

        XCTAssertEqual(result, [ali: 900, ahmed: 0])
    }
}

/// A split rule defined outside the library: the first participant pays the whole total.
private struct PayerPaysAllStrategy: SplitStrategy {
    func allocate(total: Decimal, participants: [ParticipantID]) throws -> Allocations {
        guard let payer = participants.first else { throw BarabriError.noParticipants }
        return participants.reduce(into: Allocations()) { result, participant in
            result[participant] = participant == payer ? total : 0
        }
    }
}

/// Creator for the outside rule above; it only supplies the factory method.
private struct PayerPaysAllCreator: SplitStrategyCreator {
    func makeStrategy() -> any SplitStrategy {
        PayerPaysAllStrategy()
    }
}
