import XCTest
@testable import BarabriCore

final class DashboardFacadeTests: XCTestCase {
    private let ali = ParticipantID("ali")
    private let ahmed = ParticipantID("ahmed")

    /// Real in-memory repositories backed by a store with no file URL, plus a budget.
    private struct Fixture {
        let budgetService: BudgetService
        let expenseRepo: JSONExpenseRepository
        let settlementRepo: JSONSettlementRepository
        let budget: Budget

        func saveExpense(
            groupID: UUID,
            payer: ParticipantID,
            allocations: Allocations,
            total: Decimal
        ) async throws {
            let expense = try Expense(total: total, payer: payer, allocations: allocations)
            let record = try SharedExpenseRecord(
                groupID: groupID,
                title: "Shared expense",
                expense: expense
            )
            try await expenseRepo.save(record)
        }

        func saveSettlement(
            groupID: UUID,
            from: ParticipantID,
            to: ParticipantID,
            amount: Decimal,
            status: SettlementStatus
        ) async throws {
            let settlement = Settlement(
                groupID: groupID,
                from: from,
                to: to,
                amount: try Money(amount),
                method: .cash,
                status: status
            )
            try await settlementRepo.save(settlement)
        }
    }

    private func makeFixture() async throws -> Fixture {
        let store = JSONFileStore(fileURL: nil)
        let budgetRepo = JSONBudgetRepository(store: store)
        let expenseRepo = JSONExpenseRepository(store: store)
        let settlementRepo = JSONSettlementRepository(store: store)
        let budgetService = BudgetService(repository: budgetRepo)
        let budget = try await budgetService.createBudget(name: "November", limit: 10000)
        return Fixture(
            budgetService: budgetService,
            expenseRepo: expenseRepo,
            settlementRepo: settlementRepo,
            budget: budget
        )
    }

    private func makeFacade(
        user: ParticipantID,
        fixture: Fixture,
        budgetID: UUID? = nil
    ) -> DashboardFacade {
        DashboardFacade(
            user: user,
            budgetID: budgetID ?? fixture.budget.id,
            budgetService: fixture.budgetService,
            expenses: fixture.expenseRepo,
            settlements: fixture.settlementRepo
        )
    }

    /// Ali pays 3000 in a group: ali's share is 1000, ahmed's is 2000. Ali records only their own share.
    private func seedAnchorCase(_ fixture: Fixture, groupID: UUID) async throws {
        try await fixture.saveExpense(
            groupID: groupID,
            payer: ali,
            allocations: [ali: 1000, ahmed: 2000],
            total: 3000
        )
        _ = try await fixture.budgetService.recordExpense(
            budgetID: fixture.budget.id,
            title: "Dinner (my share)",
            amount: 1000,
            recordedAt: Date()
        )
    }

    // MARK: - Tests

    func testEmptyStateSummaryIsZeroExceptBudgetRemainingEqualsLimit() async throws {
        let fixture = try await makeFixture()
        let facade = makeFacade(user: ali, fixture: fixture)

        let summary = try await facade.loadSummary()

        XCTAssertEqual(
            summary,
            DashboardSummary(
                budgetRemaining: 10000,
                cashChange: 0,
                personalSpending: 0,
                receivables: 0,
                payables: 0
            )
        )
    }

    func testAnchorCaseForPayerShowsCashOutAndReceivable() async throws {
        let fixture = try await makeFixture()
        try await seedAnchorCase(fixture, groupID: UUID())
        let facade = makeFacade(user: ali, fixture: fixture)

        let summary = try await facade.loadSummary()

        XCTAssertEqual(summary.budgetRemaining, 9000)
        XCTAssertEqual(summary.cashChange, -3000)
        XCTAssertEqual(summary.personalSpending, 1000)
        XCTAssertEqual(summary.receivables, 2000)
        XCTAssertEqual(summary.payables, 0)
    }

    func testSameDataForNonPayerShowsPayableAndNoCashChange() async throws {
        let fixture = try await makeFixture()
        try await seedAnchorCase(fixture, groupID: UUID())
        let facade = makeFacade(user: ahmed, fixture: fixture)

        let summary = try await facade.loadSummary()

        XCTAssertEqual(summary.cashChange, 0)
        XCTAssertEqual(summary.receivables, 0)
        XCTAssertEqual(summary.payables, 2000)
    }

    func testCompletedSettlementReducesReceivableAndCashChange() async throws {
        let fixture = try await makeFixture()
        let groupID = UUID()
        try await seedAnchorCase(fixture, groupID: groupID)
        try await fixture.saveSettlement(
            groupID: groupID,
            from: ahmed,
            to: ali,
            amount: 500,
            status: .completed
        )
        let facade = makeFacade(user: ali, fixture: fixture)

        let summary = try await facade.loadSummary()

        XCTAssertEqual(summary.receivables, 1500)
        XCTAssertEqual(summary.cashChange, -2500)
    }

    func testPendingSettlementDoesNotChangeBalances() async throws {
        let fixture = try await makeFixture()
        let groupID = UUID()
        try await seedAnchorCase(fixture, groupID: groupID)
        try await fixture.saveSettlement(
            groupID: groupID,
            from: ahmed,
            to: ali,
            amount: 500,
            status: .pending
        )
        let facade = makeFacade(user: ali, fixture: fixture)

        let summary = try await facade.loadSummary()

        XCTAssertEqual(summary.receivables, 2000)
        XCTAssertEqual(summary.cashChange, -3000)
    }

    func testBalancesOfDifferentGroupsAreNotNettedAgainstEachOther() async throws {
        let fixture = try await makeFixture()
        let groupA = UUID()
        let groupB = UUID()
        try await seedAnchorCase(fixture, groupID: groupA)
        // Group B: ahmed pays 1000, so ali owes ahmed 500 there.
        try await fixture.saveExpense(
            groupID: groupB,
            payer: ahmed,
            allocations: [ali: 500, ahmed: 500],
            total: 1000
        )
        let facade = makeFacade(user: ali, fixture: fixture)

        let summary = try await facade.loadSummary()

        XCTAssertEqual(summary.receivables, 2000)
        XCTAssertEqual(summary.payables, 500)
        XCTAssertEqual(summary.cashChange, -3000)
    }

    func testPersonalSpendingOnlyReducesBudgetRemaining() async throws {
        let fixture = try await makeFixture()
        _ = try await fixture.budgetService.recordExpense(
            budgetID: fixture.budget.id,
            title: "Groceries",
            amount: 2500,
            recordedAt: Date()
        )
        _ = try await fixture.budgetService.recordExpense(
            budgetID: fixture.budget.id,
            title: "Taxi",
            amount: 1500,
            recordedAt: Date()
        )
        let facade = makeFacade(user: ali, fixture: fixture)

        let summary = try await facade.loadSummary()

        XCTAssertEqual(summary.budgetRemaining, 6000)
        XCTAssertEqual(summary.personalSpending, 4000)
        XCTAssertEqual(summary.cashChange, 0)
    }

    func testOverBudgetGivesNegativeBudgetRemaining() async throws {
        let fixture = try await makeFixture()
        _ = try await fixture.budgetService.recordExpense(
            budgetID: fixture.budget.id,
            title: "Rent deposit",
            amount: 12000,
            recordedAt: Date()
        )
        let facade = makeFacade(user: ali, fixture: fixture)

        let summary = try await facade.loadSummary()

        XCTAssertEqual(summary.budgetRemaining, -2000)
        XCTAssertEqual(summary.personalSpending, 12000)
    }

    func testUnknownBudgetThrowsBudgetNotFound() async throws {
        let fixture = try await makeFixture()
        let facade = makeFacade(user: ali, fixture: fixture, budgetID: UUID())

        do {
            _ = try await facade.loadSummary()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BarabriError, .budgetNotFound)
        }
    }
}
