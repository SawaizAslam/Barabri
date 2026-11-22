import XCTest
@testable import BarabriCore

final class SettlementServiceTests: XCTestCase {
    private let ali = ParticipantID("ali")
    private let ahmed = ParticipantID("ahmed")
    private let sara = ParticipantID("sara")
    private let outsider = ParticipantID("outsider")
    private let recordedAt = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Helpers

    /// Creates a "Trip" group (Ali, Ahmed, Sara) with one anchor expense: Ali paid 3000, Ahmed owes Ali 2000.
    private func makeFixture(
        store: JSONFileStore = JSONFileStore(fileURL: nil)
    ) async throws -> (SettlementService, JSONSettlementRepository, ExpenseGroup) {
        let settlements = JSONSettlementRepository(store: store)
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

        let expense = try Expense(total: 3000, payer: ali, allocations: [ali: 1000, ahmed: 2000])
        try await expenses.save(
            try SharedExpenseRecord(groupID: group.id, title: "Dinner", expense: expense)
        )

        let service = SettlementService(
            settlements: settlements,
            expenses: expenses,
            groups: groups
        )
        return (service, settlements, group)
    }

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

    // MARK: - Successful settlements

    func testRecordsPartialSettlementAndReducesOutstanding() async throws {
        let (service, settlementsRepo, group) = try await makeFixture()

        let settlement = try await service.recordSettlement(
            groupID: group.id,
            from: ahmed,
            to: ali,
            amount: 500,
            method: .easypaisa,
            recordedAt: recordedAt
        )

        XCTAssertEqual(settlement.groupID, group.id)
        XCTAssertEqual(settlement.from, ahmed)
        XCTAssertEqual(settlement.to, ali)
        XCTAssertEqual(settlement.amount.amount, 500)
        XCTAssertEqual(settlement.method, .easypaisa)
        XCTAssertEqual(settlement.status, .completed)
        XCTAssertEqual(settlement.recordedAt, recordedAt)

        let saved = try await settlementsRepo.settlements(inGroup: group.id)
        XCTAssertEqual(saved, [settlement])

        let remaining = try await service.outstanding(groupID: group.id, from: ahmed, to: ali)
        XCTAssertEqual(remaining, 1500)
    }

    func testEachMethodLabelIsStored() async throws {
        let (service, settlementsRepo, group) = try await makeFixture()

        for method in SettlementMethod.allCases {
            _ = try await service.recordSettlement(
                groupID: group.id,
                from: ahmed,
                to: ali,
                amount: 100,
                method: method,
                recordedAt: recordedAt
            )
        }

        let saved = try await settlementsRepo.settlements(inGroup: group.id)
        XCTAssertEqual(saved.map(\.method), SettlementMethod.allCases)

        let remaining = try await service.outstanding(groupID: group.id, from: ahmed, to: ali)
        XCTAssertEqual(remaining, 1600)
    }

    func testSettlingExactFullAmountClearsDebt() async throws {
        let (service, _, group) = try await makeFixture()

        _ = try await service.recordSettlement(
            groupID: group.id,
            from: ahmed,
            to: ali,
            amount: 2000,
            method: .bankTransfer,
            recordedAt: recordedAt
        )

        let remaining = try await service.outstanding(groupID: group.id, from: ahmed, to: ali)
        XCTAssertEqual(remaining, 0)
    }

    func testSuccessiveSettlementsCannotExceedRemainingDebt() async throws {
        let (service, settlementsRepo, group) = try await makeFixture()

        _ = try await service.recordSettlement(
            groupID: group.id, from: ahmed, to: ali, amount: 1500, method: .cash, recordedAt: recordedAt
        )
        _ = try await service.recordSettlement(
            groupID: group.id, from: ahmed, to: ali, amount: 500, method: .jazzCash, recordedAt: recordedAt
        )

        await assertThrows(.settlementExceedsObligation) {
            _ = try await service.recordSettlement(
                groupID: group.id, from: ahmed, to: ali, amount: 1, method: .cash, recordedAt: recordedAt
            )
        }

        let saved = try await settlementsRepo.settlements(inGroup: group.id)
        XCTAssertEqual(saved.count, 2)
    }

    // MARK: - Rejected settlements

    func testOverSettlementByOneCentIsRejectedAndNotSaved() async throws {
        let (service, settlementsRepo, group) = try await makeFixture()

        await assertThrows(.settlementExceedsObligation) {
            _ = try await service.recordSettlement(
                groupID: group.id,
                from: ahmed,
                to: ali,
                amount: Decimal(string: "2000.01")!,
                method: .cash,
                recordedAt: recordedAt
            )
        }

        let saved = try await settlementsRepo.allSettlements()
        XCTAssertTrue(saved.isEmpty)
    }

    func testSettlingInWrongDirectionIsRejectedAndNotSaved() async throws {
        let (service, settlementsRepo, group) = try await makeFixture()

        await assertThrows(.settlementExceedsObligation) {
            _ = try await service.recordSettlement(
                groupID: group.id,
                from: ali,
                to: ahmed,
                amount: 100,
                method: .cash,
                recordedAt: recordedAt
            )
        }

        let saved = try await settlementsRepo.allSettlements()
        XCTAssertTrue(saved.isEmpty)
    }

    func testSettlingBetweenMembersWithNoDebtIsRejectedAndNotSaved() async throws {
        let (service, settlementsRepo, group) = try await makeFixture()

        await assertThrows(.settlementExceedsObligation) {
            _ = try await service.recordSettlement(
                groupID: group.id,
                from: sara,
                to: ali,
                amount: 100,
                method: .cash,
                recordedAt: recordedAt
            )
        }

        let saved = try await settlementsRepo.allSettlements()
        XCTAssertTrue(saved.isEmpty)
    }

    func testSelfSettlementIsRejectedAndNotSaved() async throws {
        let (service, settlementsRepo, group) = try await makeFixture()

        await assertThrows(.invalidSettlement) {
            _ = try await service.recordSettlement(
                groupID: group.id,
                from: ali,
                to: ali,
                amount: 100,
                method: .cash,
                recordedAt: recordedAt
            )
        }

        let saved = try await settlementsRepo.allSettlements()
        XCTAssertTrue(saved.isEmpty)
    }

    func testNonPositiveAmountIsRejectedAndNotSaved() async throws {
        let (service, settlementsRepo, group) = try await makeFixture()

        await assertThrows(.invalidAmount) {
            _ = try await service.recordSettlement(
                groupID: group.id,
                from: ahmed,
                to: ali,
                amount: 0,
                method: .cash,
                recordedAt: recordedAt
            )
        }
        await assertThrows(.invalidAmount) {
            _ = try await service.recordSettlement(
                groupID: group.id,
                from: ahmed,
                to: ali,
                amount: -10,
                method: .cash,
                recordedAt: recordedAt
            )
        }

        let saved = try await settlementsRepo.allSettlements()
        XCTAssertTrue(saved.isEmpty)
    }

    func testUnknownGroupIsRejectedAndNotSaved() async throws {
        let (service, settlementsRepo, _) = try await makeFixture()

        await assertThrows(.groupNotFound) {
            _ = try await service.recordSettlement(
                groupID: UUID(),
                from: ahmed,
                to: ali,
                amount: 100,
                method: .cash,
                recordedAt: recordedAt
            )
        }

        let saved = try await settlementsRepo.allSettlements()
        XCTAssertTrue(saved.isEmpty)
    }

    func testNonMemberSenderIsRejectedAndNotSaved() async throws {
        let (service, settlementsRepo, group) = try await makeFixture()

        await assertThrows(.memberNotFound) {
            _ = try await service.recordSettlement(
                groupID: group.id,
                from: outsider,
                to: ali,
                amount: 100,
                method: .cash,
                recordedAt: recordedAt
            )
        }

        let saved = try await settlementsRepo.allSettlements()
        XCTAssertTrue(saved.isEmpty)
    }

    func testNonMemberRecipientIsRejectedAndNotSaved() async throws {
        let (service, settlementsRepo, group) = try await makeFixture()

        await assertThrows(.memberNotFound) {
            _ = try await service.recordSettlement(
                groupID: group.id,
                from: ahmed,
                to: outsider,
                amount: 100,
                method: .cash,
                recordedAt: recordedAt
            )
        }

        let saved = try await settlementsRepo.allSettlements()
        XCTAssertTrue(saved.isEmpty)
    }

    func testDebtInAnotherGroupDoesNotCount() async throws {
        let store = JSONFileStore(fileURL: nil)
        let (service, settlementsRepo, _) = try await makeFixture(store: store)

        // "Flat" has the same people as "Trip" but no expenses, so Ahmed owes Ali nothing there.
        let flat = ExpenseGroup(
            name: "Flat",
            members: [Member(id: ali, name: "Ali"), Member(id: ahmed, name: "Ahmed")]
        )
        try await JSONGroupRepository(store: store).save(flat)

        await assertThrows(.settlementExceedsObligation) {
            _ = try await service.recordSettlement(
                groupID: flat.id,
                from: ahmed,
                to: ali,
                amount: 100,
                method: .cash,
                recordedAt: recordedAt
            )
        }

        let saved = try await settlementsRepo.allSettlements()
        XCTAssertTrue(saved.isEmpty)
    }

    // MARK: - Outstanding

    func testOutstandingForUnknownGroupThrowsGroupNotFound() async throws {
        let (service, _, _) = try await makeFixture()

        await assertThrows(.groupNotFound) {
            _ = try await service.outstanding(groupID: UUID(), from: ahmed, to: ali)
        }
    }

    func testOutstandingInReverseDirectionIsZero() async throws {
        let (service, _, group) = try await makeFixture()

        let owed = try await service.outstanding(groupID: group.id, from: ali, to: ahmed)
        XCTAssertEqual(owed, 0)
    }
}
