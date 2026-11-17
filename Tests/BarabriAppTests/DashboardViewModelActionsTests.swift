import XCTest
import BarabriCore
@testable import BarabriApp

@MainActor
final class DashboardViewModelActionsTests: XCTestCase {
    private let ali = ParticipantID("ali")
    private let ahmed = ParticipantID("ahmed")
    private let sara = ParticipantID("sara")

    private func makeViewModel() async throws -> (AppEnvironment, DashboardViewModel) {
        let env = try await AppEnvironment.make(fileURL: nil)
        return (env, DashboardViewModel(environment: env))
    }

    // MARK: - Personal expenses

    func testAddPersonalExpenseUpdatesSpendingAndRemainingBudget() async throws {
        let (_, viewModel) = try await makeViewModel()

        let saved = await viewModel.addPersonalExpense(title: "Lunch", amountText: "500")

        XCTAssertTrue(saved)
        XCTAssertEqual(viewModel.personalSpendingText, "Rs. 500")
        XCTAssertEqual(viewModel.budgetRemainingText, "Rs. 49,500")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testAddPersonalExpenseWithInvalidAmountSavesNothing() async throws {
        let (env, viewModel) = try await makeViewModel()

        let saved = await viewModel.addPersonalExpense(title: "Lunch", amountText: "abc")

        XCTAssertFalse(saved)
        XCTAssertEqual(viewModel.errorMessage, BarabriError.invalidAmount.localizedDescription)
        let summary = try await env.budgetService.summary(budgetID: env.budgetID)
        XCTAssertEqual(summary.spent, 0)
    }

    func testAddPersonalExpenseWithBlankTitleIsRejected() async throws {
        let (env, viewModel) = try await makeViewModel()

        let saved = await viewModel.addPersonalExpense(title: "   ", amountText: "500")

        XCTAssertFalse(saved)
        XCTAssertEqual(viewModel.errorMessage, BarabriError.emptyName.localizedDescription)
        let summary = try await env.budgetService.summary(budgetID: env.budgetID)
        XCTAssertEqual(summary.spent, 0)
    }

    // MARK: - Group expenses

    func testAliPaysGroupExpenseShowsCashOutOwnShareAndReceivable() async throws {
        let (_, viewModel) = try await makeViewModel()

        let saved = await viewModel.addGroupExpense(
            title: "Dinner",
            amountText: "3000",
            payer: ali,
            participants: [ali, ahmed, sara]
        )

        XCTAssertTrue(saved)
        XCTAssertEqual(viewModel.cashChangeText, "-Rs. 3,000")
        XCTAssertEqual(viewModel.personalSpendingText, "Rs. 1,000")
        XCTAssertEqual(viewModel.receivablesText, "Rs. 2,000")
        XCTAssertEqual(viewModel.payablesText, "Rs. 0")
        XCTAssertEqual(viewModel.budgetRemainingText, "Rs. 49,000")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testGroupExpensePaidBySomeoneElseShowsPayableAndOwnShare() async throws {
        let (_, viewModel) = try await makeViewModel()

        let saved = await viewModel.addGroupExpense(
            title: "Dinner",
            amountText: "3000",
            payer: ahmed,
            participants: [ali, ahmed, sara]
        )

        XCTAssertTrue(saved)
        XCTAssertEqual(viewModel.payablesText, "Rs. 1,000")
        XCTAssertEqual(viewModel.personalSpendingText, "Rs. 1,000")
        XCTAssertEqual(viewModel.cashChangeText, "Rs. 0")
        XCTAssertEqual(viewModel.receivablesText, "Rs. 0")
    }

    func testGroupExpenseWithoutTheUserAddsNoPersonalSpending() async throws {
        let (env, viewModel) = try await makeViewModel()

        let saved = await viewModel.addGroupExpense(
            title: "Groceries",
            amountText: "2000",
            payer: ahmed,
            participants: [ahmed, sara]
        )

        XCTAssertTrue(saved)
        XCTAssertEqual(viewModel.personalSpendingText, "Rs. 0")
        XCTAssertEqual(viewModel.payablesText, "Rs. 0")
        let expenses = try await env.expenseService.expenses(inGroup: env.group.id)
        XCTAssertEqual(expenses.count, 1)
    }

    func testGroupExpenseWithNoParticipantsSavesNothing() async throws {
        let (env, viewModel) = try await makeViewModel()

        let saved = await viewModel.addGroupExpense(
            title: "Dinner",
            amountText: "3000",
            payer: ali,
            participants: []
        )

        XCTAssertFalse(saved)
        XCTAssertEqual(viewModel.errorMessage, BarabriError.noParticipants.localizedDescription)
        let expenses = try await env.expenseService.expenses(inGroup: env.group.id)
        XCTAssertEqual(expenses.count, 0)
        let summary = try await env.budgetService.summary(budgetID: env.budgetID)
        XCTAssertEqual(summary.spent, 0)
    }

    // MARK: - Settlements

    func testRecordSettlementReducesWhatTheUserOwes() async throws {
        let (_, viewModel) = try await makeViewModel()
        let dinnerSaved = await viewModel.addGroupExpense(
            title: "Dinner",
            amountText: "3000",
            payer: ahmed,
            participants: [ali, ahmed, sara]
        )
        XCTAssertTrue(dinnerSaved)

        let saved = await viewModel.recordSettlement(from: ali, to: ahmed, amountText: "400", method: .cash)

        XCTAssertTrue(saved)
        XCTAssertEqual(viewModel.payablesText, "Rs. 600")
        XCTAssertEqual(viewModel.cashChangeText, "-Rs. 400")
    }

    func testSettlementLargerThanTheDebtIsRejected() async throws {
        let (_, viewModel) = try await makeViewModel()
        let dinnerSaved = await viewModel.addGroupExpense(
            title: "Dinner",
            amountText: "3000",
            payer: ahmed,
            participants: [ali, ahmed, sara]
        )
        XCTAssertTrue(dinnerSaved)

        let saved = await viewModel.recordSettlement(from: ali, to: ahmed, amountText: "5000", method: .jazzCash)

        XCTAssertFalse(saved)
        XCTAssertEqual(viewModel.errorMessage, BarabriError.settlementExceedsObligation.localizedDescription)
        XCTAssertEqual(viewModel.payablesText, "Rs. 1,000")
    }

    // MARK: - Error handling

    func testSuccessfulActionClearsAnEarlierError() async throws {
        let (_, viewModel) = try await makeViewModel()
        let failed = await viewModel.addPersonalExpense(title: "Lunch", amountText: "abc")
        XCTAssertFalse(failed)
        XCTAssertNotNil(viewModel.errorMessage)

        let saved = await viewModel.addPersonalExpense(title: "Lunch", amountText: "500")

        XCTAssertTrue(saved)
        XCTAssertNil(viewModel.errorMessage)
    }
}
