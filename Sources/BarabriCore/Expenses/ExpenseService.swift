import Foundation
import os

private let logger = Logger(subsystem: "com.barabri.core", category: "ExpenseService")

/// Records shared expenses for a group. Every request is validated before anything is saved.
public struct ExpenseService: Sendable {
    private let expenses: any ExpenseRepository
    private let groups: any GroupRepository

    public init(expenses: any ExpenseRepository, groups: any GroupRepository) {
        self.expenses = expenses
        self.groups = groups
    }

    /// Validates the request, splits the total, and saves it as a shared expense.
    ///
    /// Validation runs in a fixed order and stops at the first failure. Nothing is saved when this throws.
    /// - Throws: `BarabriError` describing the first rule the request breaks.
    public func addExpense(
        groupID: UUID,
        title: String,
        total: Decimal,
        payer: ParticipantID,
        participants: [ParticipantID],
        split: SplitType,
        recordedAt: Date = Date()
    ) async throws -> SharedExpenseRecord {
        do {
            let record = try await makeRecord(
                groupID: groupID,
                title: title,
                total: total,
                payer: payer,
                participants: participants,
                split: split,
                recordedAt: recordedAt
            )
            // The save is the last step that can fail, so a rejected request leaves no trace.
            try await expenses.save(record)
            logger.info("Shared expense saved")
            return record
        } catch {
            logger.error("addExpense rejected: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    /// Returns every shared expense recorded in the group.
    public func expenses(inGroup groupID: UUID) async throws -> [SharedExpenseRecord] {
        try await expenses.sharedExpenses(inGroup: groupID)
    }

    // MARK: - Private

    /// Runs every check and builds the record, without saving it.
    private func makeRecord(
        groupID: UUID,
        title: String,
        total: Decimal,
        payer: ParticipantID,
        participants: [ParticipantID],
        split: SplitType,
        recordedAt: Date
    ) async throws -> SharedExpenseRecord {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw BarabriError.emptyName }
        guard total > 0 else { throw BarabriError.invalidAmount }
        guard !participants.isEmpty else { throw BarabriError.noParticipants }
        guard Set(participants).count == participants.count else { throw BarabriError.duplicateParticipant }

        guard let group = try await groups.group(id: groupID) else { throw BarabriError.groupNotFound }
        let memberIDs = Set(group.members.map(\.id))
        guard memberIDs.contains(payer), participants.allSatisfy({ memberIDs.contains($0) }) else {
            throw BarabriError.memberNotFound
        }
        guard participants.contains(payer) else { throw BarabriError.payerNotFound }

        // Factory method: the split type's creator chooses the concrete strategy. This code never names one.
        let allocations = try split.creator.allocate(total: total, participants: participants)
        let expense = try Expense(total: total, payer: payer, allocations: allocations)
        return try SharedExpenseRecord(
            groupID: groupID,
            title: trimmedTitle,
            expense: expense,
            recordedAt: recordedAt
        )
    }
}
