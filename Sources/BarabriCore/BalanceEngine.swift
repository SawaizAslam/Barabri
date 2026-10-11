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
