import Foundation

public struct Expense: Equatable, Sendable {
    public let total: Decimal
    public let payer: ParticipantID
    public let allocations: Allocations

    public init(total: Decimal, payer: ParticipantID, allocations: Allocations) throws {
        guard total > 0 else { throw BarabriError.invalidAmount }
        guard allocations[payer] != nil else { throw BarabriError.payerNotFound }
        guard allocations.values.reduce(0, +) == total else { throw BarabriError.invalidAllocationTotal }
        self.total = total
        self.payer = payer
        self.allocations = allocations
    }
}

public struct BalanceResult: Equatable, Sendable {
    public let cashChange: Decimal
    public let personalExpense: Decimal
    public let receivables: Allocations
    public let payables: Allocations
}

/// A net debt inside one group: `debtor` owes `creditor` `amount` (always > 0).
public struct Obligation: Equatable, Sendable {
    public let debtor: ParticipantID
    public let creditor: ParticipantID
    public let amount: Decimal

    public init(debtor: ParticipantID, creditor: ParticipantID, amount: Decimal) {
        self.debtor = debtor
        self.creditor = creditor
        self.amount = amount
    }
}

public struct BalanceEngine: Sendable {
    public init() {}

    public func calculate(for expense: Expense) -> BalanceResult {
        let personalShare = expense.allocations[expense.payer, default: 0]
        let receivables = expense.allocations
            .filter { $0.key != expense.payer && $0.value > 0 }
        return BalanceResult(
            cashChange: -expense.total,
            personalExpense: personalShare,
            receivables: receivables,
            payables: [:]
        )
    }
}

// MARK: - Net balances

/// Directional key for a gross debt: `debtor` owes `creditor`.
private struct DebtKey: Hashable {
    let debtor: ParticipantID
    let creditor: ParticipantID
}

extension BalanceEngine {
    /// Net pairwise obligations across many expenses and settlements.
    ///
    /// Each expense adds every non-payer's positive share to what that person owes the payer.
    /// Each `.completed` settlement subtracts its amount from what `from` owes `to`.
    /// `.pending` settlements are ignored. For each pair of people, the two directions are
    /// offset against each other, leaving at most one obligation per pair.
    ///
    /// Returns only amounts greater than zero, sorted by debtor, then creditor.
    public func obligations(expenses: [Expense], settlements: [Settlement] = []) -> [Obligation] {
        let owes = grossDebts(expenses: expenses, settlements: settlements)

        var result: [Obligation] = []
        for (key, gross) in owes {
            let reverse = owes[DebtKey(debtor: key.creditor, creditor: key.debtor), default: 0]
            let net = gross - reverse
            if net > 0 {
                result.append(Obligation(debtor: key.debtor, creditor: key.creditor, amount: net))
            }
        }

        return result.sorted { lhs, rhs in
            if lhs.debtor.value != rhs.debtor.value {
                return lhs.debtor.value < rhs.debtor.value
            }
            return lhs.creditor.value < rhs.creditor.value
        }
    }

    /// What `debtor` currently owes `creditor` after netting. Returns 0 when nothing is owed
    /// or when the debt runs the other way.
    public func outstanding(
        from debtor: ParticipantID,
        to creditor: ParticipantID,
        expenses: [Expense],
        settlements: [Settlement] = []
    ) -> Decimal {
        obligations(expenses: expenses, settlements: settlements)
            .first { $0.debtor == debtor && $0.creditor == creditor }?
            .amount ?? 0
    }

    /// One participant's position across many expenses and settlements.
    ///
    /// - `cashChange`: minus the totals of expenses they paid, minus completed settlements they paid,
    ///   plus completed settlements they received.
    /// - `personalExpense`: the sum of their own shares in every expense, whoever paid.
    /// - `receivables`: who owes them, and how much, after netting (only amounts > 0).
    /// - `payables`: whom they owe, and how much, after netting (only amounts > 0).
    public func calculate(
        for participant: ParticipantID,
        expenses: [Expense],
        settlements: [Settlement] = []
    ) -> BalanceResult {
        let paidTotal = expenses
            .filter { $0.payer == participant }
            .reduce(Decimal(0)) { $0 + $1.total }

        let completed = settlements.filter { $0.status == .completed }
        let settledOut = completed
            .filter { $0.from == participant }
            .reduce(Decimal(0)) { $0 + $1.amount.amount }
        let settledIn = completed
            .filter { $0.to == participant }
            .reduce(Decimal(0)) { $0 + $1.amount.amount }

        let personalExpense = expenses
            .reduce(Decimal(0)) { $0 + $1.allocations[participant, default: 0] }

        let netted = obligations(expenses: expenses, settlements: settlements)
        let receivables = netted
            .filter { $0.creditor == participant }
            .reduce(into: Allocations()) { $0[$1.debtor] = $1.amount }
        let payables = netted
            .filter { $0.debtor == participant }
            .reduce(into: Allocations()) { $0[$1.creditor] = $1.amount }

        return BalanceResult(
            cashChange: -paidTotal - settledOut + settledIn,
            personalExpense: personalExpense,
            receivables: receivables,
            payables: payables
        )
    }

    /// Signed gross debts keyed by direction. Expenses add shares owed to the payer;
    /// completed settlements subtract from what `from` owes `to`. Pending settlements are skipped.
    private func grossDebts(expenses: [Expense], settlements: [Settlement]) -> [DebtKey: Decimal] {
        var owes: [DebtKey: Decimal] = [:]

        for expense in expenses {
            for (participant, share) in expense.allocations where participant != expense.payer && share > 0 {
                owes[DebtKey(debtor: participant, creditor: expense.payer), default: 0] += share
            }
        }

        for settlement in settlements where settlement.status == .completed {
            owes[DebtKey(debtor: settlement.from, creditor: settlement.to), default: 0] -= settlement.amount.amount
        }

        return owes
    }
}
