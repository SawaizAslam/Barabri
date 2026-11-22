import Foundation

/// Everything the dashboard shows, as plain numbers in PKR.
public struct DashboardSummary: Equatable, Sendable {
    /// Budget limit minus personal spending (negative when over budget).
    public let budgetRemaining: Decimal
    /// Cash paid out for shared expenses and settlements, net of settlements received.
    /// Covers shared expenses and settlements only, not personal spending. Zero or below means money left the pocket.
    public let cashChange: Decimal
    /// Personal expenses recorded in the budget.
    public let personalSpending: Decimal
    /// Total others owe the user, summed over groups.
    public let receivables: Decimal
    /// Total the user owes others, summed over groups.
    public let payables: Decimal

    public init(
        budgetRemaining: Decimal,
        cashChange: Decimal,
        personalSpending: Decimal,
        receivables: Decimal,
        payables: Decimal
    ) {
        self.budgetRemaining = budgetRemaining
        self.cashChange = cashChange
        self.personalSpending = personalSpending
        self.receivables = receivables
        self.payables = payables
    }
}

/// Facade pattern: the dashboard screen calls one method instead of knowing about `BudgetService`,
/// the two repositories, and `BalanceEngine`. The facade gathers the data and delegates the arithmetic.
public struct DashboardFacade: Sendable {
    private let user: ParticipantID
    private let budgetID: UUID
    private let budgetService: BudgetService
    private let expenses: any ExpenseRepository
    private let settlements: any SettlementRepository
    private let balanceEngine: BalanceEngine

    public init(
        user: ParticipantID,
        budgetID: UUID,
        budgetService: BudgetService,
        expenses: any ExpenseRepository,
        settlements: any SettlementRepository,
        balanceEngine: BalanceEngine = BalanceEngine()
    ) {
        self.user = user
        self.budgetID = budgetID
        self.budgetService = budgetService
        self.expenses = expenses
        self.settlements = settlements
        self.balanceEngine = balanceEngine
    }

    /// Loads the budget summary, all shared expenses and all settlements concurrently (`async let`),
    /// then awaits them together. This is safe because the repositories are `Sendable` and the
    /// underlying `JSONFileStore` is an actor.
    ///
    /// Balances are computed per group and summed, so a debt in one group is never netted
    /// against a debt in another group.
    public func loadSummary() async throws -> DashboardSummary {
        async let budgetSummary = budgetService.summary(budgetID: budgetID)
        async let expenseRecords = expenses.allSharedExpenses()
        async let settlementRecords = settlements.allSettlements()
        let (budget, records, settled) = try await (budgetSummary, expenseRecords, settlementRecords)

        let expensesByGroup = Dictionary(grouping: records) { $0.groupID }
        let settlementsByGroup = Dictionary(grouping: settled) { $0.groupID }

        var cashChange: Decimal = 0
        var receivables: Decimal = 0
        var payables: Decimal = 0
        for groupID in Set(expensesByGroup.keys).union(settlementsByGroup.keys) {
            let result = try groupBalance(
                records: expensesByGroup[groupID] ?? [],
                settlements: settlementsByGroup[groupID] ?? []
            )
            cashChange += result.cashChange
            receivables += result.receivables.values.reduce(0, +)
            payables += result.payables.values.reduce(0, +)
        }

        return DashboardSummary(
            budgetRemaining: budget.remaining,
            cashChange: cashChange,
            personalSpending: budget.spent,
            receivables: receivables,
            payables: payables
        )
    }

    /// The user's balance within a single group. Rebuilds the validated expenses before calculating.
    private func groupBalance(
        records: [SharedExpenseRecord],
        settlements: [Settlement]
    ) throws -> BalanceResult {
        let groupExpenses = try records.map { try $0.expense() }
        return balanceEngine.calculate(for: user, expenses: groupExpenses, settlements: settlements)
    }
}
