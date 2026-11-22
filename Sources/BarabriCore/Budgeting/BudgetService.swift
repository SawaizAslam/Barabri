import Foundation

public struct BudgetSummary: Equatable, Sendable {
    public let budget: Budget
    /// Sum of personal expenses recorded in this budget.
    public let spent: Decimal
    /// `budget.limit.amount - spent`; negative when over budget.
    public let remaining: Decimal
    /// True when `spent` is greater than the budget limit.
    public let isOverBudget: Bool
    /// Spending per category id. Uncategorised expenses are not included.
    public let spentByCategory: [UUID: Decimal]

    public init(
        budget: Budget,
        spent: Decimal,
        remaining: Decimal,
        isOverBudget: Bool,
        spentByCategory: [UUID: Decimal]
    ) {
        self.budget = budget
        self.spent = spent
        self.remaining = remaining
        self.isOverBudget = isOverBudget
        self.spentByCategory = spentByCategory
    }
}

public struct BudgetService: Sendable {
    private let repository: any BudgetRepository

    public init(repository: any BudgetRepository) {
        self.repository = repository
    }

    /// Trims the name. Throws `.emptyName` for a blank name, `.invalidAmount` when `limit <= 0`.
    public func createBudget(name: String, limit: Decimal) async throws -> Budget {
        let trimmedName = try Self.validatedName(name)
        let limitMoney = try Self.positiveMoney(limit)
        let budget = Budget(name: trimmedName, limit: limitMoney)
        try await repository.save(budget)
        return budget
    }

    /// Adds a category to a budget. Throws `.budgetNotFound`, `.emptyName`, `.invalidAmount` (limit <= 0),
    /// and `.invalidAllocationTotal` when the category limits would exceed the budget limit.
    /// Nothing is saved when it throws.
    public func addCategory(toBudget budgetID: UUID, name: String, limit: Decimal) async throws -> BudgetCategory {
        let trimmedName = try Self.validatedName(name)
        let limitMoney = try Self.positiveMoney(limit)
        guard var budget = try await repository.budget(id: budgetID) else {
            throw BarabriError.budgetNotFound
        }
        let allocated = budget.categories.reduce(Decimal(0)) { $0 + $1.limit.amount }
        guard allocated + limitMoney.amount <= budget.limit.amount else {
            throw BarabriError.invalidAllocationTotal
        }
        let category = BudgetCategory(name: trimmedName, limit: limitMoney)
        budget.categories.append(category)
        try await repository.save(budget)
        return category
    }

    /// Throws `.budgetNotFound`, `.categoryNotFound` (when `categoryID` is not a category of this budget),
    /// `.emptyName` (blank title), `.invalidAmount` (amount <= 0). Nothing is saved when it throws.
    public func recordExpense(
        budgetID: UUID,
        categoryID: UUID? = nil,
        title: String,
        amount: Decimal,
        recordedAt: Date
    ) async throws -> PersonalExpense {
        let trimmedTitle = try Self.validatedName(title)
        let amountMoney = try Self.positiveMoney(amount)
        guard let budget = try await repository.budget(id: budgetID) else {
            throw BarabriError.budgetNotFound
        }
        if let categoryID, !budget.categories.contains(where: { $0.id == categoryID }) {
            throw BarabriError.categoryNotFound
        }
        let expense = PersonalExpense(
            budgetID: budgetID,
            categoryID: categoryID,
            title: trimmedTitle,
            amount: amountMoney,
            recordedAt: recordedAt
        )
        try await repository.save(expense)
        return expense
    }

    /// Records only the payer's own share of a shared expense as personal spending.
    ///
    /// Uses `result.personalExpense` and never `result.cashChange`: the full amount paid out of pocket
    /// is not personal spending, because the other participants owe their parts back.
    /// Throws `.budgetNotFound`. Returns nil and saves nothing when the personal share is 0.
    public func recordPersonalShare(
        of result: BalanceResult,
        budgetID: UUID,
        categoryID: UUID? = nil,
        title: String,
        recordedAt: Date
    ) async throws -> PersonalExpense? {
        guard try await repository.budget(id: budgetID) != nil else {
            throw BarabriError.budgetNotFound
        }
        guard result.personalExpense != 0 else { return nil }
        return try await recordExpense(
            budgetID: budgetID,
            categoryID: categoryID,
            title: title,
            amount: result.personalExpense,
            recordedAt: recordedAt
        )
    }

    /// Throws `.budgetNotFound`.
    public func summary(budgetID: UUID) async throws -> BudgetSummary {
        guard let budget = try await repository.budget(id: budgetID) else {
            throw BarabriError.budgetNotFound
        }
        let expenses = try await repository.personalExpenses(inBudget: budgetID)
        let spent = expenses.reduce(Decimal(0)) { $0 + $1.amount.amount }
        var spentByCategory: [UUID: Decimal] = [:]
        for expense in expenses {
            guard let categoryID = expense.categoryID else { continue }
            spentByCategory[categoryID, default: 0] += expense.amount.amount
        }
        return BudgetSummary(
            budget: budget,
            spent: spent,
            remaining: budget.limit.amount - spent,
            isOverBudget: spent > budget.limit.amount,
            spentByCategory: spentByCategory
        )
    }

    // MARK: - Validation helpers

    private static func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BarabriError.emptyName }
        return trimmed
    }

    private static func positiveMoney(_ amount: Decimal) throws -> Money {
        guard amount > 0 else { throw BarabriError.invalidAmount }
        return try Money(amount)
    }
}
