import Foundation

// Repository adapters over the shared `JSONFileStore`. Each one keeps no state of its own,
// so any number of them can share a single store and therefore a single document.

public struct JSONGroupRepository: GroupRepository {
    private let store: JSONFileStore

    public init(store: JSONFileStore) {
        self.store = store
    }

    public func save(_ group: ExpenseGroup) async throws {
        try await store.update { document in
            document.groups.upsert(group)
        }
    }

    public func group(id: UUID) async throws -> ExpenseGroup? {
        try await store.read().groups.first(where: { $0.id == id })
    }

    public func groups() async throws -> [ExpenseGroup] {
        try await store.read().groups
    }
}

public struct JSONBudgetRepository: BudgetRepository {
    private let store: JSONFileStore

    public init(store: JSONFileStore) {
        self.store = store
    }

    public func save(_ budget: Budget) async throws {
        try await store.update { document in
            document.budgets.upsert(budget)
        }
    }

    public func budget(id: UUID) async throws -> Budget? {
        try await store.read().budgets.first(where: { $0.id == id })
    }

    public func budgets() async throws -> [Budget] {
        try await store.read().budgets
    }

    public func save(_ expense: PersonalExpense) async throws {
        try await store.update { document in
            document.personalExpenses.upsert(expense)
        }
    }

    public func personalExpenses(inBudget budgetID: UUID) async throws -> [PersonalExpense] {
        try await store.read().personalExpenses.filter { $0.budgetID == budgetID }
    }

    public func allPersonalExpenses() async throws -> [PersonalExpense] {
        try await store.read().personalExpenses
    }
}

public struct JSONExpenseRepository: ExpenseRepository {
    private let store: JSONFileStore

    public init(store: JSONFileStore) {
        self.store = store
    }

    public func save(_ expense: SharedExpenseRecord) async throws {
        try await store.update { document in
            document.sharedExpenses.upsert(expense)
        }
    }

    public func sharedExpenses(inGroup groupID: UUID) async throws -> [SharedExpenseRecord] {
        try await store.read().sharedExpenses.filter { $0.groupID == groupID }
    }

    public func allSharedExpenses() async throws -> [SharedExpenseRecord] {
        try await store.read().sharedExpenses
    }
}

public struct JSONSettlementRepository: SettlementRepository {
    private let store: JSONFileStore

    public init(store: JSONFileStore) {
        self.store = store
    }

    public func save(_ settlement: Settlement) async throws {
        try await store.update { document in
            document.settlements.upsert(settlement)
        }
    }

    public func settlements(inGroup groupID: UUID) async throws -> [Settlement] {
        try await store.read().settlements.filter { $0.groupID == groupID }
    }

    public func allSettlements() async throws -> [Settlement] {
        try await store.read().settlements
    }
}

private extension Array where Element: Identifiable {
    /// Replaces the element with the same `id` in place, or appends it if none exists.
    mutating func upsert(_ element: Element) {
        if let index = firstIndex(where: { $0.id == element.id }) {
            self[index] = element
        } else {
            append(element)
        }
    }
}
