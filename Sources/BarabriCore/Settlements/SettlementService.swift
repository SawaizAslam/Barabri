import Foundation
import os

private let logger = Logger(subsystem: "com.barabri.core", category: "SettlementService")

/// Records settlements between members of a group, checked against the debt `BalanceEngine` reports.
///
/// Payment methods are labels only: no payment provider is contacted and no money is moved.
///
/// The check-then-save is not atomic across concurrent callers. Two simultaneous settlements for the
/// same debt can both pass the check. This is a known limitation of the current design.
public struct SettlementService: Sendable {
    private let settlements: any SettlementRepository
    private let expenses: any ExpenseRepository
    private let groups: any GroupRepository
    private let balanceEngine: BalanceEngine

    public init(
        settlements: any SettlementRepository,
        expenses: any ExpenseRepository,
        groups: any GroupRepository,
        balanceEngine: BalanceEngine = BalanceEngine()
    ) {
        self.settlements = settlements
        self.expenses = expenses
        self.groups = groups
        self.balanceEngine = balanceEngine
    }

    /// Records a completed settlement: `from` (the debtor) paid `to` (the creditor) `amount`.
    /// `method` is only a label (cash, bank transfer, Easypaisa, JazzCash); no money is moved.
    /// Nothing is saved when it throws.
    public func recordSettlement(
        groupID: UUID,
        from: ParticipantID,
        to: ParticipantID,
        amount: Decimal,
        method: SettlementMethod,
        recordedAt: Date = Date()
    ) async throws -> Settlement {
        do {
            let settlement = try await validatedSettlement(
                groupID: groupID,
                from: from,
                to: to,
                amount: amount,
                method: method,
                recordedAt: recordedAt
            )
            try await settlements.save(settlement)
            logger.info("Settlement recorded with method \(method.rawValue, privacy: .public)")
            return settlement
        } catch {
            logger.error("recordSettlement rejected: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    /// What `from` currently owes `to` in this group, after expenses and completed settlements.
    public func outstanding(groupID: UUID, from: ParticipantID, to: ParticipantID) async throws -> Decimal {
        _ = try await requireGroup(id: groupID)
        return try await owed(groupID: groupID, from: from, to: to)
    }

    // MARK: - Private

    /// Runs the validation in the documented order and builds the settlement without saving it.
    private func validatedSettlement(
        groupID: UUID,
        from: ParticipantID,
        to: ParticipantID,
        amount: Decimal,
        method: SettlementMethod,
        recordedAt: Date
    ) async throws -> Settlement {
        guard amount > 0 else { throw BarabriError.invalidAmount }
        guard from != to else { throw BarabriError.invalidSettlement }

        let group = try await requireGroup(id: groupID)
        let memberIDs = Set(group.members.map(\.id))
        guard memberIDs.contains(from), memberIDs.contains(to) else {
            throw BarabriError.memberNotFound
        }

        let outstandingAmount = try await owed(groupID: groupID, from: from, to: to)
        guard amount <= outstandingAmount else { throw BarabriError.settlementExceedsObligation }

        return Settlement(
            groupID: groupID,
            from: from,
            to: to,
            amount: try Money(amount),
            method: method,
            status: .completed,
            recordedAt: recordedAt
        )
    }

    private func requireGroup(id: UUID) async throws -> ExpenseGroup {
        guard let group = try await groups.group(id: id) else {
            throw BarabriError.groupNotFound
        }
        return group
    }

    /// The netted amount `from` owes `to` in the group. All arithmetic is delegated to `BalanceEngine`.
    private func owed(groupID: UUID, from: ParticipantID, to: ParticipantID) async throws -> Decimal {
        let expenseRecords = try await expenses.sharedExpenses(inGroup: groupID)
        let domainExpenses = try expenseRecords.map { try $0.expense() }
        let settlementRecords = try await settlements.settlements(inGroup: groupID)
        return balanceEngine.outstanding(
            from: from,
            to: to,
            expenses: domainExpenses,
            settlements: settlementRecords
        )
    }
}
