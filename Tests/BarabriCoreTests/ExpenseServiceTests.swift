import XCTest
@testable import BarabriCore

final class ExpenseServiceTests: XCTestCase {
    private let ali = ParticipantID("ali")
    private let ahmed = ParticipantID("ahmed")
    private let sara = ParticipantID("sara")
    private let outsider = ParticipantID("outsider")
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Helpers

    /// Builds a service over real in-memory repositories with one saved group: Ali, Ahmed and Sara.
    private func makeFixture() async throws -> (ExpenseService, JSONExpenseRepository, ExpenseGroup) {
        let store = JSONFileStore(fileURL: nil)
        let expenses = JSONExpenseRepository(store: store)
        let groups = JSONGroupRepository(store: store)
        let group = ExpenseGroup(
            name: "Trip",
            members: [
                Member(id: ali, name: "Ali"),
                Member(id: ahmed, name: "Ahmed"),
                Member(id: sara, name: "Sara")
            ]
        )
        try await groups.save(group)
        let service = ExpenseService(expenses: expenses, groups: groups)
        return (service, expenses, group)
    }

    private func shareMap(_ record: SharedExpenseRecord) -> [ParticipantID: Decimal] {
        Dictionary(uniqueKeysWithValues: record.shares.map { ($0.participant, $0.amount.amount) })
    }

    /// Asserts that `work` throws the given `BarabriError`. `XCTAssertThrowsError` does not support async code.
    private func assertThrows(
        _ expected: BarabriError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ work: () async throws -> Void
    ) async {
        do {
            try await work()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? BarabriError, expected, file: file, line: line)
        }
    }

    // MARK: - Successful adds

    func testEqualSplitIsValidatedSplitAndSaved() async throws {
        let (service, expenses, group) = try await makeFixture()
        let recordedAt = fixedDate

        let record = try await service.addExpense(
            groupID: group.id,
            title: "  Dinner  ",
            total: 3000,
            payer: ali,
            participants: [ali, ahmed, sara],
            split: .equal,
            recordedAt: recordedAt
        )

        let expectedTotal = try Money(3000)
        XCTAssertEqual(record.payer, ali)
        XCTAssertEqual(record.total, expectedTotal)
        XCTAssertEqual(record.title, "Dinner")
        XCTAssertEqual(record.groupID, group.id)
        XCTAssertEqual(record.recordedAt, recordedAt)
        XCTAssertEqual(record.shares.count, 3)
        XCTAssertEqual(shareMap(record), [ali: 1000, ahmed: 1000, sara: 1000])

        let saved = try await expenses.sharedExpenses(inGroup: group.id)
        XCTAssertEqual(saved, [record])
    }

    func testExactSplitIsSavedWithRequestedAmounts() async throws {
        let (service, expenses, group) = try await makeFixture()

        let record = try await service.addExpense(
            groupID: group.id,
            title: "Hotel",
            total: 3000,
            payer: ali,
            participants: [ali, ahmed],
            split: .exact([ali: 1000, ahmed: 2000]),
            recordedAt: fixedDate
        )

        XCTAssertEqual(shareMap(record), [ali: 1000, ahmed: 2000])
        let saved = try await expenses.sharedExpenses(inGroup: group.id)
        XCTAssertEqual(saved, [record])
    }

    func testPercentageSplitIsSavedWithPercentageAmounts() async throws {
        let (service, expenses, group) = try await makeFixture()

        let record = try await service.addExpense(
            groupID: group.id,
            title: "Groceries",
            total: 1000,
            payer: ali,
            participants: [ali, ahmed],
            split: .percentage([ali: 25, ahmed: 75]),
            recordedAt: fixedDate
        )

        XCTAssertEqual(shareMap(record), [ali: 250, ahmed: 750])
        let saved = try await expenses.sharedExpenses(inGroup: group.id)
        XCTAssertEqual(saved, [record])
    }

    func testListingReturnsOnlyExpensesOfTheRequestedGroup() async throws {
        let store = JSONFileStore(fileURL: nil)
        let expenses = JSONExpenseRepository(store: store)
        let groups = JSONGroupRepository(store: store)
        let trip = ExpenseGroup(name: "Trip", members: [Member(id: ali, name: "Ali")])
        let flat = ExpenseGroup(name: "Flat", members: [Member(id: ahmed, name: "Ahmed")])
        try await groups.save(trip)
        try await groups.save(flat)
        let service = ExpenseService(expenses: expenses, groups: groups)

        let tripDinner = try await service.addExpense(
            groupID: trip.id,
            title: "Dinner",
            total: 500,
            payer: ali,
            participants: [ali],
            split: .equal,
            recordedAt: fixedDate
        )
        _ = try await service.addExpense(
            groupID: flat.id,
            title: "Rent",
            total: 900,
            payer: ahmed,
            participants: [ahmed],
            split: .equal,
            recordedAt: fixedDate
        )

        let inTrip = try await service.expenses(inGroup: trip.id)

        XCTAssertEqual(inTrip, [tripDinner])
    }

    // MARK: - Validation errors (nothing is saved for any of these)

    func testEmptyTitleIsRejectedAndNothingIsSaved() async throws {
        let (service, expenses, group) = try await makeFixture()

        await assertThrows(.emptyName) {
            _ = try await service.addExpense(
                groupID: group.id,
                title: "   ",
                total: 3000,
                payer: ali,
                participants: [ali, ahmed],
                split: .equal
            )
        }

        let all = try await expenses.allSharedExpenses()
        XCTAssertTrue(all.isEmpty)
    }

    func testZeroAmountIsRejectedAndNothingIsSaved() async throws {
        let (service, expenses, group) = try await makeFixture()

        await assertThrows(.invalidAmount) {
            _ = try await service.addExpense(
                groupID: group.id,
                title: "Dinner",
                total: 0,
                payer: ali,
                participants: [ali, ahmed],
                split: .equal
            )
        }

        let all = try await expenses.allSharedExpenses()
        XCTAssertTrue(all.isEmpty)
    }

    func testNegativeAmountIsRejectedAndNothingIsSaved() async throws {
        let (service, expenses, group) = try await makeFixture()

        await assertThrows(.invalidAmount) {
            _ = try await service.addExpense(
                groupID: group.id,
                title: "Dinner",
                total: -5,
                payer: ali,
                participants: [ali, ahmed],
                split: .equal
            )
        }

        let all = try await expenses.allSharedExpenses()
        XCTAssertTrue(all.isEmpty)
    }

    func testEmptyParticipantListIsRejectedAndNothingIsSaved() async throws {
        let (service, expenses, group) = try await makeFixture()

        await assertThrows(.noParticipants) {
            _ = try await service.addExpense(
                groupID: group.id,
                title: "Dinner",
                total: 3000,
                payer: ali,
                participants: [],
                split: .equal
            )
        }

        let all = try await expenses.allSharedExpenses()
        XCTAssertTrue(all.isEmpty)
    }

    func testDuplicateParticipantIsRejectedAndNothingIsSaved() async throws {
        let (service, expenses, group) = try await makeFixture()

        await assertThrows(.duplicateParticipant) {
            _ = try await service.addExpense(
                groupID: group.id,
                title: "Dinner",
                total: 3000,
                payer: ali,
                participants: [ali, ali],
                split: .equal
            )
        }

        let all = try await expenses.allSharedExpenses()
        XCTAssertTrue(all.isEmpty)
    }

    func testUnknownGroupIsRejectedAndNothingIsSaved() async throws {
        let (service, expenses, _) = try await makeFixture()

        await assertThrows(.groupNotFound) {
            _ = try await service.addExpense(
                groupID: UUID(),
                title: "Dinner",
                total: 3000,
                payer: ali,
                participants: [ali, ahmed],
                split: .equal
            )
        }

        let all = try await expenses.allSharedExpenses()
        XCTAssertTrue(all.isEmpty)
    }

    func testParticipantOutsideGroupIsRejectedAndNothingIsSaved() async throws {
        let (service, expenses, group) = try await makeFixture()

        await assertThrows(.memberNotFound) {
            _ = try await service.addExpense(
                groupID: group.id,
                title: "Dinner",
                total: 3000,
                payer: ali,
                participants: [ali, outsider],
                split: .equal
            )
        }

        let all = try await expenses.allSharedExpenses()
        XCTAssertTrue(all.isEmpty)
    }

    func testPayerOutsideGroupIsRejectedAndNothingIsSaved() async throws {
        let (service, expenses, group) = try await makeFixture()

        await assertThrows(.memberNotFound) {
            _ = try await service.addExpense(
                groupID: group.id,
                title: "Dinner",
                total: 3000,
                payer: outsider,
                participants: [outsider, ali],
                split: .equal
            )
        }

        let all = try await expenses.allSharedExpenses()
        XCTAssertTrue(all.isEmpty)
    }

    func testPayerNotAmongParticipantsIsRejectedAndNothingIsSaved() async throws {
        let (service, expenses, group) = try await makeFixture()

        await assertThrows(.payerNotFound) {
            _ = try await service.addExpense(
                groupID: group.id,
                title: "Dinner",
                total: 2000,
                payer: sara,
                participants: [ali, ahmed],
                split: .equal
            )
        }

        let all = try await expenses.allSharedExpenses()
        XCTAssertTrue(all.isEmpty)
    }

    func testExactAmountsThatDoNotSumToTotalAreRejectedAndNothingIsSaved() async throws {
        let (service, expenses, group) = try await makeFixture()

        await assertThrows(.invalidAllocationTotal) {
            _ = try await service.addExpense(
                groupID: group.id,
                title: "Hotel",
                total: 3000,
                payer: ali,
                participants: [ali, ahmed],
                split: .exact([ali: 1000, ahmed: 1000])
            )
        }

        let all = try await expenses.allSharedExpenses()
        XCTAssertTrue(all.isEmpty)
    }
}
