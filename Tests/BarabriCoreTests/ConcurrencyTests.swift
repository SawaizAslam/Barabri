import Foundation
import XCTest
@testable import BarabriCore

/// Concurrency tests for the shared persistence path.
///
/// The shared mutable state is the single `StoreDocument` held inside the `JSONFileStore` actor.
/// Every repository is a stateless adapter over that one store, and every write replaces the whole
/// document through `update`. These tests fire many writes at once through `ExpenseService` and the
/// repositories, then check that none of them were lost, that reads never see a partial record,
/// and that writes to one collection do not overwrite another.
final class ConcurrencyTests: XCTestCase {
    private let ali = ParticipantID("ali")
    private let ahmed = ParticipantID("ahmed")
    private let sara = ParticipantID("sara")

    private let writeCount = 100

    // MARK: - Helpers

    /// Builds one store, the expense and group repositories over that same store, and one saved group: Ali, Ahmed and Sara.
    private func makeFixture(fileURL: URL? = nil) async throws -> (store: JSONFileStore, service: ExpenseService, group: ExpenseGroup) {
        let store = JSONFileStore(fileURL: fileURL)
        let expenses = JSONExpenseRepository(store: store)
        let groups = JSONGroupRepository(store: store)
        let group = ExpenseGroup(
            name: "Trip",
            members: [
                Member(id: ali, name: "Ali"),
                Member(id: ahmed, name: "Ahmed"),
                Member(id: sara, name: "Sara"),
            ]
        )
        try await groups.save(group)
        let service = ExpenseService(expenses: expenses, groups: groups)
        return (store, service, group)
    }

    /// Starts `writeCount` child tasks at once. Task `i` records an equal three-way split of `300 + 3 * i`.
    private func addConcurrently(service: ExpenseService, groupID: UUID) async throws -> [SharedExpenseRecord] {
        let count = writeCount
        let payer = ParticipantID("ali")
        let participants = [ParticipantID("ali"), ParticipantID("ahmed"), ParticipantID("sara")]
        return try await withThrowingTaskGroup(of: SharedExpenseRecord.self) { taskGroup in
            for i in 0..<count {
                taskGroup.addTask {
                    try await addExpenseNumber(i, service: service, groupID: groupID, payer: payer, participants: participants)
                }
            }
            var records: [SharedExpenseRecord] = []
            for try await record in taskGroup {
                records.append(record)
            }
            return records
        }
    }

    // MARK: - Tests

    func testHundredConcurrentAddsAreAllStoredInMemory() async throws {
        let (_, service, group) = try await makeFixture()

        let returned = try await addConcurrently(service: service, groupID: group.id)
        let stored = try await service.expenses(inGroup: group.id)

        XCTAssertEqual(returned.count, 100)
        XCTAssertEqual(stored.count, 100)
        XCTAssertEqual(Set(stored.map(\.id)).count, 100)
        XCTAssertEqual(Set(stored.map(\.id)), Set(returned.map(\.id)))
        XCTAssertEqual(Set(stored.map(\.title)), Set((0..<100).map { "Expense \($0)" }))
        XCTAssertEqual(stored.reduce(Decimal(0)) { $0 + $1.total.amount }, 44_850)

        // Every stored record must still satisfy the expense invariants, and the balances must match the splits.
        let expenseValues = try stored.map { try $0.expense() }
        let obligations = BalanceEngine().obligations(expenses: expenseValues)
        XCTAssertEqual(
            obligations,
            [
                Obligation(debtor: ahmed, creditor: ali, amount: 14_950),
                Obligation(debtor: sara, creditor: ali, amount: 14_950),
            ]
        )
    }

    func testHundredConcurrentAddsAllReachTheFile() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("barabri-concurrency-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let (_, service, group) = try await makeFixture(fileURL: fileURL)
        _ = try await addConcurrently(service: service, groupID: group.id)

        // A second store has an empty cache, so it must load everything from disk.
        let fresh = JSONFileStore(fileURL: fileURL)
        let document = try await fresh.read()

        XCTAssertEqual(document.sharedExpenses.count, 100)
        XCTAssertEqual(Set(document.sharedExpenses.map(\.id)).count, 100)
        XCTAssertEqual(document.sharedExpenses.reduce(Decimal(0)) { $0 + $1.total.amount }, 44_850)
        XCTAssertEqual(document.groups.count, 1)
    }

    func testReadsDuringWritesSeeOnlyCompleteRecords() async throws {
        let (_, service, group) = try await makeFixture()
        let groupID = group.id
        let count = writeCount
        let payer = ParticipantID("ali")
        let participants = [ParticipantID("ali"), ParticipantID("ahmed"), ParticipantID("sara")]

        // Writers return nil. Readers return the number of records in the snapshot they saw.
        let results: [Int?] = try await withThrowingTaskGroup(of: Int?.self) { taskGroup in
            for i in 0..<count {
                taskGroup.addTask { () async throws -> Int? in
                    _ = try await addExpenseNumber(i, service: service, groupID: groupID, payer: payer, participants: participants)
                    return nil
                }
            }
            for _ in 0..<count {
                taskGroup.addTask { () async throws -> Int? in
                    let snapshot = try await service.expenses(inGroup: groupID)
                    try validateSnapshot(snapshot)
                    return snapshot.count
                }
            }
            var collected: [Int?] = []
            for try await result in taskGroup {
                collected.append(result)
            }
            return collected
        }

        let readerCounts = results.compactMap { $0 }
        XCTAssertEqual(readerCounts.count, 100)
        for snapshotCount in readerCounts {
            XCTAssertTrue((0...100).contains(snapshotCount), "Snapshot count \(snapshotCount) is out of range")
        }

        let finalCount = try await service.expenses(inGroup: groupID).count
        XCTAssertEqual(finalCount, 100)
    }

    func testConcurrentWritesToDifferentCollectionsDoNotOverwriteEachOther() async throws {
        let store = JSONFileStore(fileURL: nil)
        let expenseRepository = JSONExpenseRepository(store: store)
        let groupRepository = JSONGroupRepository(store: store)
        let budgetRepository = JSONBudgetRepository(store: store)
        let service = ExpenseService(expenses: expenseRepository, groups: groupRepository)

        let trip = ExpenseGroup(
            name: "Trip",
            members: [
                Member(id: ali, name: "Ali"),
                Member(id: ahmed, name: "Ahmed"),
                Member(id: sara, name: "Sara"),
            ]
        )
        try await groupRepository.save(trip)
        let budget = Budget(name: "November", limit: try Money(100_000))
        try await budgetRepository.save(budget)

        let groupID = trip.id
        let budgetID = budget.id
        let payer = ParticipantID("ali")
        let participants = [ParticipantID("ali"), ParticipantID("ahmed"), ParticipantID("sara")]

        try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            for i in 0..<50 {
                taskGroup.addTask {
                    _ = try await addExpenseNumber(i, service: service, groupID: groupID, payer: payer, participants: participants)
                }
                taskGroup.addTask {
                    try await budgetRepository.save(
                        PersonalExpense(budgetID: budgetID, title: "Personal \(i)", amount: Money(Decimal(10 + i)))
                    )
                }
                taskGroup.addTask {
                    try await groupRepository.save(ExpenseGroup(name: "Group \(i)"))
                }
            }
            try await taskGroup.waitForAll()
        }

        let document = try await store.read()

        XCTAssertEqual(document.sharedExpenses.count, 50)
        XCTAssertEqual(document.personalExpenses.count, 50)
        XCTAssertEqual(document.groups.count, 51)
        XCTAssertEqual(document.budgets.count, 1)
        XCTAssertEqual(document.personalExpenses.reduce(Decimal(0)) { $0 + $1.amount.amount }, 1_725)
    }
}

// MARK: - File-scope helpers

/// Adds expense number `i`: total `300 + 3 * i`, equal split across three participants, paid by the first one.
/// Free functions keep the child-task closures from capturing the test case.
private func addExpenseNumber(
    _ i: Int,
    service: ExpenseService,
    groupID: UUID,
    payer: ParticipantID,
    participants: [ParticipantID]
) async throws -> SharedExpenseRecord {
    try await service.addExpense(
        groupID: groupID,
        title: "Expense \(i)",
        total: Decimal(300 + 3 * i),
        payer: payer,
        participants: participants,
        split: .equal
    )
}

/// Thrown from a reader task when a snapshot contains a record that violates the expense invariants.
private struct InconsistentSnapshot: Error {}

/// Throws if any record in a snapshot is internally inconsistent or has the wrong number of shares.
private func validateSnapshot(_ snapshot: [SharedExpenseRecord]) throws {
    guard Set(snapshot.map(\.id)).count == snapshot.count else { throw InconsistentSnapshot() }
    for record in snapshot {
        guard record.shares.count == 3 else { throw InconsistentSnapshot() }
        _ = try record.expense()
    }
}
