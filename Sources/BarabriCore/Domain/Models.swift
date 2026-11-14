import Foundation

// MARK: - Groups

/// A person who belongs to an expense group.
public struct Member: Hashable, Codable, Sendable {
    public let id: ParticipantID
    public let name: String

    public init(id: ParticipantID, name: String) {
        self.id = id
        self.name = name
    }
}

/// A set of people who share expenses. Named `ExpenseGroup` so it does not clash with `SwiftUI.Group`.
public struct ExpenseGroup: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var members: [Member]

    public init(id: UUID = UUID(), name: String, members: [Member] = []) {
        self.id = id
        self.name = name
        self.members = members
    }
}

// MARK: - Personal budgeting

public struct BudgetCategory: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var limit: Money

    public init(id: UUID = UUID(), name: String, limit: Money) {
        self.id = id
        self.name = name
        self.limit = limit
    }
}

public struct Budget: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var limit: Money
    public var categories: [BudgetCategory]

    public init(id: UUID = UUID(), name: String, limit: Money, categories: [BudgetCategory] = []) {
        self.id = id
        self.name = name
        self.limit = limit
        self.categories = categories
    }
}

/// Money the user spent on themselves. A shared expense contributes only the payer's own share here.
public struct PersonalExpense: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let budgetID: UUID
    public let categoryID: UUID?
    public let title: String
    public let amount: Money
    public let recordedAt: Date

    public init(
        id: UUID = UUID(),
        budgetID: UUID,
        categoryID: UUID? = nil,
        title: String,
        amount: Money,
        recordedAt: Date = Date()
    ) {
        self.id = id
        self.budgetID = budgetID
        self.categoryID = categoryID
        self.title = title
        self.amount = amount
        self.recordedAt = recordedAt
    }
}

// MARK: - Shared expenses

/// One participant's allocated part of a shared expense.
public struct Share: Equatable, Codable, Sendable {
    public let participant: ParticipantID
    public let amount: Money

    public init(participant: ParticipantID, amount: Money) {
        self.participant = participant
        self.amount = amount
    }
}

/// The persisted form of a validated `Expense`.
///
/// The original total, the payer, and every participant's allocation are stored separately so that
/// cash impact, personal share, receivables, and payables can always be recalculated.
public struct SharedExpenseRecord: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let groupID: UUID
    public let title: String
    public let payer: ParticipantID
    public let total: Money
    public let shares: [Share]
    public let recordedAt: Date

    public init(
        id: UUID = UUID(),
        groupID: UUID,
        title: String,
        expense: Expense,
        recordedAt: Date = Date()
    ) throws {
        self.id = id
        self.groupID = groupID
        self.title = title
        self.payer = expense.payer
        self.total = try Money(expense.total)
        self.shares = try expense.allocations
            .sorted { $0.key.value < $1.key.value }
            .map { Share(participant: $0.key, amount: try Money($0.value)) }
        self.recordedAt = recordedAt
    }

    /// Rebuilds the validated domain value. Throws if stored data no longer satisfies the expense invariants.
    public func expense() throws -> Expense {
        var allocations = Allocations()
        for share in shares {
            guard allocations[share.participant] == nil else { throw BarabriError.duplicateParticipant }
            allocations[share.participant] = share.amount.amount
        }
        return try Expense(total: total.amount, payer: payer, allocations: allocations)
    }
}

// MARK: - Settlements

/// How a settlement was paid. These are labels only; Barabri does not move money.
public enum SettlementMethod: String, CaseIterable, Codable, Sendable {
    case cash
    case bankTransfer
    case easypaisa
    case jazzCash

    public var displayName: String {
        switch self {
        case .cash: "Cash"
        case .bankTransfer: "Bank transfer"
        case .easypaisa: "Easypaisa"
        case .jazzCash: "JazzCash"
        }
    }
}

public enum SettlementStatus: String, Codable, Sendable {
    /// Recorded but not yet confirmed; does not change balances.
    case pending
    /// Confirmed; reduces what `from` owes `to`.
    case completed
}

/// A payment from a debtor (`from`) to a creditor (`to`) inside one group.
public struct Settlement: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let groupID: UUID
    public let from: ParticipantID
    public let to: ParticipantID
    public let amount: Money
    public let method: SettlementMethod
    public var status: SettlementStatus
    public let recordedAt: Date

    public init(
        id: UUID = UUID(),
        groupID: UUID,
        from: ParticipantID,
        to: ParticipantID,
        amount: Money,
        method: SettlementMethod,
        status: SettlementStatus = .completed,
        recordedAt: Date = Date()
    ) {
        self.id = id
        self.groupID = groupID
        self.from = from
        self.to = to
        self.amount = amount
        self.method = method
        self.status = status
        self.recordedAt = recordedAt
    }
}
