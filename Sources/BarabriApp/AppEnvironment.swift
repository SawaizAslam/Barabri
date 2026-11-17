import Foundation
import BarabriCore

/// Composition root: the one place that creates the store, the repositories and the services.
/// Everything else receives its dependencies through initialisers.
struct AppEnvironment: Sendable {
    let user: ParticipantID
    let budgetID: UUID
    let group: ExpenseGroup
    let budgetService: BudgetService
    let expenseService: ExpenseService
    let settlementService: SettlementService
    let facade: DashboardFacade

    /// Builds all repositories and services over one `JSONFileStore`.
    /// Seeds a "Monthly budget" (limit 50000) and a "Flatmates" group (Ali, Ahmed, Sara) when the store has none.
    /// Otherwise reuses the first existing budget and group.
    static func make(fileURL: URL?) async throws -> AppEnvironment {
        let store = JSONFileStore(fileURL: fileURL)
        let budgetRepository = JSONBudgetRepository(store: store)
        let groupRepository = JSONGroupRepository(store: store)
        let expenseRepository = JSONExpenseRepository(store: store)
        let settlementRepository = JSONSettlementRepository(store: store)

        let budgetService = BudgetService(repository: budgetRepository)
        let groupService = GroupService(repository: groupRepository)
        let expenseService = ExpenseService(expenses: expenseRepository, groups: groupRepository)
        let settlementService = SettlementService(
            settlements: settlementRepository,
            expenses: expenseRepository,
            groups: groupRepository
        )

        let budget: Budget
        if let existing = try await budgetRepository.budgets().first {
            budget = existing
        } else {
            budget = try await budgetService.createBudget(name: "Monthly budget", limit: 50000)
        }

        let group: ExpenseGroup
        if let existing = try await groupService.groups().first {
            group = existing
        } else {
            var created = try await groupService.createGroup(name: "Flatmates")
            let members: [(id: String, name: String)] = [("ali", "Ali"), ("ahmed", "Ahmed"), ("sara", "Sara")]
            for member in members {
                created = try await groupService.addMember(
                    toGroup: created.id,
                    id: ParticipantID(member.id),
                    name: member.name
                )
            }
            group = created
        }

        let user = ParticipantID("ali")
        let facade = DashboardFacade(
            user: user,
            budgetID: budget.id,
            budgetService: budgetService,
            expenses: expenseRepository,
            settlements: settlementRepository
        )

        return AppEnvironment(
            user: user,
            budgetID: budget.id,
            group: group,
            budgetService: budgetService,
            expenseService: expenseService,
            settlementService: settlementService,
            facade: facade
        )
    }
}
