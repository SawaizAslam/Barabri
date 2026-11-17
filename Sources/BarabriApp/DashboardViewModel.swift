import Combine
import Foundation
import BarabriCore

/// Holds the dashboard figures for SwiftUI. Reads them from the facade through `AppEnvironment`.
@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var summary: DashboardSummary?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading: Bool = false
    let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    /// On success, replaces `summary` and clears the error. On failure, keeps the previous summary.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            summary = try await environment.facade.loadSummary()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Records a personal expense in the budget. Returns true when it was saved.
    @discardableResult
    func addPersonalExpense(title: String, amountText: String) async -> Bool {
        await perform {
            let amount = try AmountParser.parse(amountText)
            _ = try await self.environment.budgetService.recordExpense(
                budgetID: self.environment.budgetID,
                title: title,
                amount: amount,
                recordedAt: Date()
            )
        }
    }

    /// Records a shared expense split equally, then records the user's own share as personal spending.
    /// Returns true when the expense was saved.
    @discardableResult
    func addGroupExpense(
        title: String,
        amountText: String,
        payer: ParticipantID,
        participants: [ParticipantID]
    ) async -> Bool {
        await perform {
            let amount = try AmountParser.parse(amountText)
            let record = try await self.environment.expenseService.addExpense(
                groupID: self.environment.group.id,
                title: title,
                total: amount,
                payer: payer,
                participants: participants,
                split: .equal
            )
            // The expense save and the personal share save are two separate writes, so they are not atomic.
            let position = BalanceEngine().calculate(
                for: self.environment.user,
                expenses: [try record.expense()]
            )
            _ = try await self.environment.budgetService.recordPersonalShare(
                of: position,
                budgetID: self.environment.budgetID,
                title: record.title,
                recordedAt: record.recordedAt
            )
        }
    }

    /// Records a settlement from `from` to `to`. Returns true when it was saved.
    @discardableResult
    func recordSettlement(
        from: ParticipantID,
        to: ParticipantID,
        amountText: String,
        method: SettlementMethod
    ) async -> Bool {
        await perform {
            let amount = try AmountParser.parse(amountText)
            _ = try await self.environment.settlementService.recordSettlement(
                groupID: self.environment.group.id,
                from: from,
                to: to,
                amount: amount,
                method: method
            )
        }
    }

    /// Runs one form action. On success reloads the summary and clears the error. On failure keeps
    /// the summary, shows the error's message and reports false.
    private func perform(_ action: () async throws -> Void) async -> Bool {
        do {
            try await action()
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        await load()
        return errorMessage == nil
    }

    var budgetRemainingText: String { text(summary.map { $0.budgetRemaining }) }
    var cashChangeText: String { text(summary.map { $0.cashChange }) }
    var personalSpendingText: String { text(summary.map { $0.personalSpending }) }
    var receivablesText: String { text(summary.map { $0.receivables }) }
    var payablesText: String { text(summary.map { $0.payables }) }

    private func text(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return RupeeFormatter.string(from: value)
    }
}
