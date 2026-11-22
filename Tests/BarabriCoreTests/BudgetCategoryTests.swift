import XCTest
@testable import BarabriCore

final class BudgetCategoryTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeService() -> (service: BudgetService, repository: FakeBudgetRepository) {
        let repository = FakeBudgetRepository()
        return (BudgetService(repository: repository), repository)
    }

    /// Stores a budget directly in the repository, bypassing the service.
    private func seedBudget(_ repository: FakeBudgetRepository, limit: Decimal) async throws -> Budget {
        let budget = Budget(name: "Monthly", limit: try Money(limit))
        try await repository.save(budget)
        return budget
    }

    /// Stores a personal expense directly in the repository, bypassing the service.
    private func seedExpense(
        _ repository: FakeBudgetRepository,
        budgetID: UUID,
        amount: Decimal
    ) async throws {
        let expense = PersonalExpense(
            budgetID: budgetID,
            title: "Seeded",
            amount: try Money(amount),
            recordedAt: fixedDate
        )
        try await repository.save(expense)
    }

    // MARK: - Categories

    func testAddCategoryReturnsCategoryAndStoresItInBudget() async throws {
        let (service, repository) = makeService()
        let budget = try await service.createBudget(name: "Monthly", limit: 10000)

        let category = try await service.addCategory(toBudget: budget.id, name: "  Food ", limit: 6000)

        XCTAssertEqual(category.name, "Food")
        XCTAssertEqual(category.limit.amount, Decimal(6000))
        let stored = try await repository.budget(id: budget.id)
        XCTAssertEqual(stored?.categories, [category])
    }

    func testAddCategoryForUnknownBudgetThrowsBudgetNotFound() async throws {
        let (service, _) = makeService()

        do {
            _ = try await service.addCategory(toBudget: UUID(), name: "Food", limit: 6000)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BarabriError, .budgetNotFound)
        }
    }

    func testAddCategoryWithBlankNameThrowsEmptyName() async throws {
        let (service, _) = makeService()
        let budget = try await service.createBudget(name: "Monthly", limit: 10000)

        do {
            _ = try await service.addCategory(toBudget: budget.id, name: " ", limit: 6000)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BarabriError, .emptyName)
        }
    }

    func testAddCategoryWithZeroLimitThrowsInvalidAmount() async throws {
        let (service, _) = makeService()
        let budget = try await service.createBudget(name: "Monthly", limit: 10000)

        do {
            _ = try await service.addCategory(toBudget: budget.id, name: "Food", limit: 0)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BarabriError, .invalidAmount)
        }
    }

    func testAddCategoryThatExceedsBudgetLimitThrowsInvalidAllocationTotal() async throws {
        let (service, repository) = makeService()
        let budget = try await service.createBudget(name: "Monthly", limit: 10000)
        _ = try await service.addCategory(toBudget: budget.id, name: "Food", limit: 6000)

        do {
            _ = try await service.addCategory(toBudget: budget.id, name: "Transport", limit: 5000)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BarabriError, .invalidAllocationTotal)
        }

        let stored = try await repository.budget(id: budget.id)
        XCTAssertEqual(stored?.categories.count, 1)
    }

    func testCategoryLimitsEqualToBudgetLimitAreAccepted() async throws {
        let (service, repository) = makeService()
        let budget = try await service.createBudget(name: "Monthly", limit: 10000)
        _ = try await service.addCategory(toBudget: budget.id, name: "Food", limit: 6000)

        _ = try await service.addCategory(toBudget: budget.id, name: "Transport", limit: 4000)

        let stored = try await repository.budget(id: budget.id)
        XCTAssertEqual(stored?.categories.count, 2)
    }

    func testRecordExpenseWithCategoryStoresCategoryID() async throws {
        let (service, repository) = makeService()
        let budget = try await service.createBudget(name: "Monthly", limit: 10000)
        let category = try await service.addCategory(toBudget: budget.id, name: "Food", limit: 6000)

        let expense = try await service.recordExpense(
            budgetID: budget.id,
            categoryID: category.id,
            title: "Groceries",
            amount: 800,
            recordedAt: fixedDate
        )

        XCTAssertEqual(expense.categoryID, category.id)
        let stored = try await repository.allPersonalExpenses()
        XCTAssertEqual(stored.first?.categoryID, category.id)
    }

    func testRecordExpenseWithCategoryFromAnotherBudgetThrowsCategoryNotFound() async throws {
        let (service, repository) = makeService()
        let budgetA = try await service.createBudget(name: "A", limit: 10000)
        let budgetB = try await service.createBudget(name: "B", limit: 10000)
        let categoryOfA = try await service.addCategory(toBudget: budgetA.id, name: "Food", limit: 6000)

        do {
            _ = try await service.recordExpense(
                budgetID: budgetB.id,
                categoryID: categoryOfA.id,
                title: "Groceries",
                amount: 800,
                recordedAt: fixedDate
            )
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BarabriError, .categoryNotFound)
        }

        let stored = try await repository.allPersonalExpenses()
        XCTAssertTrue(stored.isEmpty)
    }

    func testRecordExpenseWithUnknownCategoryThrowsCategoryNotFound() async throws {
        let (service, repository) = makeService()
        let budget = try await service.createBudget(name: "Monthly", limit: 10000)

        do {
            _ = try await service.recordExpense(
                budgetID: budget.id,
                categoryID: UUID(),
                title: "Groceries",
                amount: 800,
                recordedAt: fixedDate
            )
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BarabriError, .categoryNotFound)
        }

        let stored = try await repository.allPersonalExpenses()
        XCTAssertTrue(stored.isEmpty)
    }

    func testSummarySpentByCategorySumsPerCategoryAndIgnoresUncategorised() async throws {
        let (service, _) = makeService()
        let budget = try await service.createBudget(name: "Monthly", limit: 10000)
        let food = try await service.addCategory(toBudget: budget.id, name: "Food", limit: 6000)
        let transport = try await service.addCategory(toBudget: budget.id, name: "Transport", limit: 3000)

        _ = try await service.recordExpense(budgetID: budget.id, categoryID: food.id, title: "Lunch", amount: 1000, recordedAt: fixedDate)
        _ = try await service.recordExpense(budgetID: budget.id, categoryID: food.id, title: "Dinner", amount: 500, recordedAt: fixedDate)
        _ = try await service.recordExpense(budgetID: budget.id, categoryID: transport.id, title: "Bus", amount: 300, recordedAt: fixedDate)
        _ = try await service.recordExpense(budgetID: budget.id, title: "Gift", amount: 800, recordedAt: fixedDate)

        let summary = try await service.summary(budgetID: budget.id)

        XCTAssertEqual(summary.spentByCategory, [food.id: 1500, transport.id: 300])
        XCTAssertEqual(summary.spent, Decimal(2600))
    }

    // MARK: - Personal share of shared expenses

    func testRecordPersonalShareStoresOnlyPayersShareAsSpending() async throws {
        let (service, _) = makeService()
        let budget = try await service.createBudget(name: "Monthly", limit: 10000)
        let ali = ParticipantID("Ali")
        let ahmed = ParticipantID("Ahmed")
        let expense = try Expense(total: 3000, payer: ali, allocations: [ali: 1000, ahmed: 2000])
        let result = BalanceEngine().calculate(for: expense)

        let recorded = try await service.recordPersonalShare(
            of: result,
            budgetID: budget.id,
            title: "Dinner",
            recordedAt: fixedDate
        )

        XCTAssertEqual(recorded?.amount.amount, Decimal(1000))
        let summary = try await service.summary(budgetID: budget.id)
        XCTAssertEqual(summary.spent, Decimal(1000))
    }

    func testRecordPersonalShareWithZeroShareReturnsNilAndSavesNothing() async throws {
        let (service, repository) = makeService()
        let budget = try await service.createBudget(name: "Monthly", limit: 10000)
        let ali = ParticipantID("Ali")
        let ahmed = ParticipantID("Ahmed")
        let expense = try Expense(total: 500, payer: ali, allocations: [ali: 0, ahmed: 500])
        let result = BalanceEngine().calculate(for: expense)

        let recorded = try await service.recordPersonalShare(
            of: result,
            budgetID: budget.id,
            title: "Dinner",
            recordedAt: fixedDate
        )

        XCTAssertNil(recorded)
        let stored = try await repository.allPersonalExpenses()
        XCTAssertTrue(stored.isEmpty)
    }

    func testRecordPersonalShareForUnknownBudgetThrowsBudgetNotFound() async throws {
        let (service, _) = makeService()
        let ali = ParticipantID("Ali")
        let ahmed = ParticipantID("Ahmed")
        let expense = try Expense(total: 3000, payer: ali, allocations: [ali: 1000, ahmed: 2000])
        let result = BalanceEngine().calculate(for: expense)

        do {
            _ = try await service.recordPersonalShare(
                of: result,
                budgetID: UUID(),
                title: "Dinner",
                recordedAt: fixedDate
            )
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BarabriError, .budgetNotFound)
        }
    }
}
