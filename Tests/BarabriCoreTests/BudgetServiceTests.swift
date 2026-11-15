import XCTest
@testable import BarabriCore

private actor FakeBudgetRepository: BudgetRepository {
    private var storedBudgets: [UUID: Budget] = [:]
    private var storedExpenses: [UUID: PersonalExpense] = [:]

    func save(_ budget: Budget) async throws {
        storedBudgets[budget.id] = budget
    }

    func budget(id: UUID) async throws -> Budget? {
        storedBudgets[id]
    }

    func budgets() async throws -> [Budget] {
        Array(storedBudgets.values)
    }

    func save(_ expense: PersonalExpense) async throws {
        storedExpenses[expense.id] = expense
    }

    func personalExpenses(inBudget budgetID: UUID) async throws -> [PersonalExpense] {
        storedExpenses.values.filter { $0.budgetID == budgetID }
    }

    func allPersonalExpenses() async throws -> [PersonalExpense] {
        Array(storedExpenses.values)
    }
}

final class BudgetServiceTests: XCTestCase {
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

    // MARK: - createBudget

    func testCreateBudgetReturnsBudgetWithNameAndLimitAndStoresIt() async throws {
        let (service, repository) = makeService()

        let budget = try await service.createBudget(name: "Monthly", limit: 50000)

        XCTAssertEqual(budget.name, "Monthly")
        XCTAssertEqual(budget.limit.amount, Decimal(50000))
        let stored = try await repository.budget(id: budget.id)
        XCTAssertEqual(stored, budget)
    }

    func testCreateBudgetTrimsSurroundingWhitespaceFromName() async throws {
        let (service, _) = makeService()

        let budget = try await service.createBudget(name: "  Groceries \n", limit: 15000)

        XCTAssertEqual(budget.name, "Groceries")
    }

    func testCreateBudgetWithBlankNameThrowsEmptyNameAndStoresNothing() async throws {
        let (service, repository) = makeService()

        do {
            _ = try await service.createBudget(name: "   ", limit: 100)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BarabriError, .emptyName)
        }

        let budgets = try await repository.budgets()
        XCTAssertTrue(budgets.isEmpty)
    }

    func testCreateBudgetWithZeroLimitThrowsInvalidAmount() async throws {
        let (service, repository) = makeService()

        do {
            _ = try await service.createBudget(name: "Monthly", limit: 0)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BarabriError, .invalidAmount)
        }

        let budgets = try await repository.budgets()
        XCTAssertTrue(budgets.isEmpty)
    }

    func testCreateBudgetWithNegativeLimitThrowsInvalidAmount() async throws {
        let (service, repository) = makeService()

        do {
            _ = try await service.createBudget(name: "Monthly", limit: -1)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BarabriError, .invalidAmount)
        }

        let budgets = try await repository.budgets()
        XCTAssertTrue(budgets.isEmpty)
    }

    // MARK: - recordExpense

    func testRecordExpenseStoresExpenseWithBudgetIDTitleAndAmount() async throws {
        let (service, repository) = makeService()
        let budget = try await service.createBudget(name: "Monthly", limit: 50000)

        let expense = try await service.recordExpense(
            budgetID: budget.id,
            title: "Electricity bill",
            amount: Decimal(string: "1200.75")!,
            recordedAt: fixedDate
        )

        XCTAssertEqual(expense.budgetID, budget.id)
        XCTAssertEqual(expense.title, "Electricity bill")
        XCTAssertEqual(expense.amount.amount, Decimal(string: "1200.75")!)
        let stored = try await repository.allPersonalExpenses()
        XCTAssertEqual(stored, [expense])
    }

    func testRecordExpenseForUnknownBudgetThrowsBudgetNotFound() async throws {
        let (service, repository) = makeService()

        do {
            _ = try await service.recordExpense(
                budgetID: UUID(),
                title: "Lunch",
                amount: 500,
                recordedAt: fixedDate
            )
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BarabriError, .budgetNotFound)
        }

        let stored = try await repository.allPersonalExpenses()
        XCTAssertTrue(stored.isEmpty)
    }

    func testRecordExpenseWithZeroOrNegativeAmountThrowsInvalidAmountAndStoresNothing() async throws {
        let (service, repository) = makeService()
        let budget = try await service.createBudget(name: "Monthly", limit: 50000)

        do {
            _ = try await service.recordExpense(
                budgetID: budget.id,
                title: "Lunch",
                amount: 0,
                recordedAt: fixedDate
            )
            XCTFail("expected an error for zero amount")
        } catch {
            XCTAssertEqual(error as? BarabriError, .invalidAmount)
        }

        do {
            _ = try await service.recordExpense(
                budgetID: budget.id,
                title: "Lunch",
                amount: -250,
                recordedAt: fixedDate
            )
            XCTFail("expected an error for negative amount")
        } catch {
            XCTAssertEqual(error as? BarabriError, .invalidAmount)
        }

        let stored = try await repository.allPersonalExpenses()
        XCTAssertTrue(stored.isEmpty)
    }

    func testRecordExpenseWithBlankTitleThrowsEmptyName() async throws {
        let (service, repository) = makeService()
        let budget = try await service.createBudget(name: "Monthly", limit: 50000)

        do {
            _ = try await service.recordExpense(
                budgetID: budget.id,
                title: "   ",
                amount: 500,
                recordedAt: fixedDate
            )
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BarabriError, .emptyName)
        }

        let stored = try await repository.allPersonalExpenses()
        XCTAssertTrue(stored.isEmpty)
    }

    // MARK: - summary

    func testSummaryTotalsExpensesAndRemaining() async throws {
        let (service, repository) = makeService()
        let budget = try await seedBudget(repository, limit: 50000)
        try await seedExpense(repository, budgetID: budget.id, amount: 12000)
        try await seedExpense(repository, budgetID: budget.id, amount: Decimal(string: "8000.50")!)

        let summary = try await service.summary(budgetID: budget.id)

        XCTAssertEqual(summary.budget, budget)
        XCTAssertEqual(summary.spent, Decimal(string: "20000.50")!)
        XCTAssertEqual(summary.remaining, Decimal(string: "29999.50")!)
        XCTAssertFalse(summary.isOverBudget)
    }

    func testSummaryWithNoExpensesHasZeroSpentAndRemainingEqualToLimit() async throws {
        let (service, repository) = makeService()
        let budget = try await seedBudget(repository, limit: 50000)

        let summary = try await service.summary(budgetID: budget.id)

        XCTAssertEqual(summary.spent, 0)
        XCTAssertEqual(summary.remaining, Decimal(50000))
        XCTAssertFalse(summary.isOverBudget)
    }

    func testSummaryWhenExpensesExceedLimitHasNegativeRemainingAndIsOverBudget() async throws {
        let (service, repository) = makeService()
        let budget = try await seedBudget(repository, limit: 1000)
        try await seedExpense(repository, budgetID: budget.id, amount: 600)
        try await seedExpense(repository, budgetID: budget.id, amount: 900)

        let summary = try await service.summary(budgetID: budget.id)

        XCTAssertEqual(summary.spent, Decimal(1500))
        XCTAssertEqual(summary.remaining, Decimal(-500))
        XCTAssertTrue(summary.isOverBudget)
    }

    func testSummaryOnlyCountsExpensesOfThatBudget() async throws {
        let (service, repository) = makeService()
        let budget = try await seedBudget(repository, limit: 50000)
        let otherBudget = try await seedBudget(repository, limit: 20000)
        try await seedExpense(repository, budgetID: budget.id, amount: 3000)
        try await seedExpense(repository, budgetID: otherBudget.id, amount: 7000)

        let summary = try await service.summary(budgetID: budget.id)

        XCTAssertEqual(summary.spent, Decimal(3000))
        XCTAssertEqual(summary.remaining, Decimal(47000))
        XCTAssertFalse(summary.isOverBudget)
    }

    func testSummaryForUnknownBudgetThrowsBudgetNotFound() async throws {
        let (service, _) = makeService()

        do {
            _ = try await service.summary(budgetID: UUID())
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BarabriError, .budgetNotFound)
        }
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
