import Foundation

public struct BudgetSummary: Equatable, Sendable {
    public let budget: Budget
    /// Sum of personal expenses recorded in this budget.
    public let spent: Decimal
    /// `budget.limit.amount - spent`; negative when over budget.
    public let remaining: Decimal
    /// True when `spent` is greater than the budget limit.
    public let isOverBudget: Bool

    public init(budget: Budget, spent: Decimal, remaining: Decimal, isOverBudget: Bool) {
        self.budget = budget
        self.spent = spent
        self.remaining = remaining
        self.isOverBudget = isOverBudget
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

    /// Throws `.budgetNotFound`, `.emptyName` (blank title), `.invalidAmount` (amount <= 0).
    /// Nothing is saved when it throws.
    public func recordExpense(
        budgetID: UUID,
        title: String,
        amount: Decimal,
        recordedAt: Date
    ) async throws -> PersonalExpense {
        let trimmedTitle = try Self.validatedName(title)
        let amountMoney = try Self.positiveMoney(amount)
        let budget = try await repository.budget(id: budgetID)
        guard budget != nil else { throw BarabriError.budgetNotFound }
        let expense = PersonalExpense(
            budgetID: budgetID,
            title: trimmedTitle,
            amount: amountMoney,
            recordedAt: recordedAt
        )
        try await repository.save(expense)
        return expense
    }

    /// Throws `.budgetNotFound`.
    public func summary(budgetID: UUID) async throws -> BudgetSummary {
        guard let budget = try await repository.budget(id: budgetID) else {
            throw BarabriError.budgetNotFound
        }
        let expenses = try await repository.personalExpenses(inBudget: budgetID)
        let spent = expenses.reduce(Decimal(0)) { $0 + $1.amount.amount }
        return BudgetSummary(
            budget: budget,
            spent: spent,
            remaining: budget.limit.amount - spent,
            isOverBudget: spent > budget.limit.amount
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
