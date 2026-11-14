import Foundation

// Focused repository protocols (ISP): each service depends only on the storage operations it needs,
// and on these abstractions rather than a concrete store (DIP).
//
// Saving a value whose `id` already exists replaces the stored value.

public protocol ExpenseRepository: Sendable {
    func save(_ expense: SharedExpenseRecord) async throws
    func sharedExpenses(inGroup groupID: UUID) async throws -> [SharedExpenseRecord]
    func allSharedExpenses() async throws -> [SharedExpenseRecord]
}

public protocol SettlementRepository: Sendable {
    func save(_ settlement: Settlement) async throws
    func settlements(inGroup groupID: UUID) async throws -> [Settlement]
    func allSettlements() async throws -> [Settlement]
}

public protocol BudgetRepository: Sendable {
    func save(_ budget: Budget) async throws
    func budget(id: UUID) async throws -> Budget?
    func budgets() async throws -> [Budget]
    func save(_ expense: PersonalExpense) async throws
    func personalExpenses(inBudget budgetID: UUID) async throws -> [PersonalExpense]
    func allPersonalExpenses() async throws -> [PersonalExpense]
}

public protocol GroupRepository: Sendable {
    func save(_ group: ExpenseGroup) async throws
    func group(id: UUID) async throws -> ExpenseGroup?
    func groups() async throws -> [ExpenseGroup]
}
