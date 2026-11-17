import XCTest
import BarabriCore
@testable import BarabriApp

@MainActor
final class DashboardViewModelTests: XCTestCase {
    func testStateBeforeLoadIsEmptyWithDashPlaceholders() async throws {
        let env = try await AppEnvironment.make(fileURL: nil)
        let viewModel = DashboardViewModel(environment: env)

        XCTAssertNil(viewModel.summary)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.budgetRemainingText, "—")
        XCTAssertEqual(viewModel.cashChangeText, "—")
        XCTAssertEqual(viewModel.personalSpendingText, "—")
        XCTAssertEqual(viewModel.receivablesText, "—")
        XCTAssertEqual(viewModel.payablesText, "—")
    }

    func testLoadOnFreshEnvironmentShowsBudgetLimitAndZeros() async throws {
        let env = try await AppEnvironment.make(fileURL: nil)
        let viewModel = DashboardViewModel(environment: env)

        await viewModel.load()

        XCTAssertEqual(viewModel.budgetRemainingText, "Rs. 50,000")
        XCTAssertEqual(viewModel.cashChangeText, "Rs. 0")
        XCTAssertEqual(viewModel.personalSpendingText, "Rs. 0")
        XCTAssertEqual(viewModel.receivablesText, "Rs. 0")
        XCTAssertEqual(viewModel.payablesText, "Rs. 0")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testAliPaysDinnerShowsCashOutAndReceivable() async throws {
        let env = try await AppEnvironment.make(fileURL: nil)
        _ = try await env.expenseService.addExpense(
            groupID: env.group.id,
            title: "Dinner",
            total: 3000,
            payer: env.user,
            participants: env.group.members.map(\.id),
            split: .equal
        )
        let viewModel = DashboardViewModel(environment: env)

        await viewModel.load()

        XCTAssertEqual(viewModel.cashChangeText, "-Rs. 3,000")
        XCTAssertEqual(viewModel.receivablesText, "Rs. 2,000")
        XCTAssertEqual(viewModel.payablesText, "Rs. 0")
    }

    func testFailedLoadLeavesSummaryNilAndSetsErrorMessage() async throws {
        // The facade points at a budget that does not exist, so loadSummary() throws budgetNotFound.
        let store = JSONFileStore(fileURL: nil)
        let budgetRepository = JSONBudgetRepository(store: store)
        let expenseRepository = JSONExpenseRepository(store: store)
        let settlementRepository = JSONSettlementRepository(store: store)
        let groupRepository = JSONGroupRepository(store: store)
        let budgetService = BudgetService(repository: budgetRepository)
        let missingBudgetID = UUID()
        let broken = AppEnvironment(
            user: ParticipantID("ali"),
            budgetID: missingBudgetID,
            group: ExpenseGroup(name: "Flatmates"),
            budgetService: budgetService,
            expenseService: ExpenseService(expenses: expenseRepository, groups: groupRepository),
            settlementService: SettlementService(
                settlements: settlementRepository,
                expenses: expenseRepository,
                groups: groupRepository
            ),
            facade: DashboardFacade(
                user: ParticipantID("ali"),
                budgetID: missingBudgetID,
                budgetService: budgetService,
                expenses: expenseRepository,
                settlements: settlementRepository
            )
        )

        let viewModel = DashboardViewModel(environment: broken)
        await viewModel.load()

        XCTAssertNil(viewModel.summary)
        XCTAssertEqual(viewModel.errorMessage, BarabriError.budgetNotFound.localizedDescription)
        XCTAssertFalse(viewModel.isLoading)
    }
}
