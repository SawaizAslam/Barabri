import Foundation

public enum BarabriError: Error, Equatable, LocalizedError {
    // Amounts and splitting
    case invalidAmount
    case noParticipants
    case participantNotFound
    case duplicateParticipant
    case invalidAllocationTotal
    case invalidPercentageTotal
    case payerNotFound

    // Groups
    case emptyName
    case duplicateMember
    case groupNotFound
    case memberNotFound

    // Budgets
    case budgetNotFound
    case categoryNotFound

    // Settlements
    case invalidSettlement
    case settlementExceedsObligation

    // Storage
    case persistenceFailure(String)

    public var errorDescription: String? {
        switch self {
        case .invalidAmount: "Amount must be greater than zero."
        case .noParticipants: "At least one participant is required."
        case .participantNotFound: "Every allocation must belong to a participant."
        case .duplicateParticipant: "A participant can only appear once in an expense."
        case .invalidAllocationTotal: "Allocations must equal the expense total."
        case .invalidPercentageTotal: "Percentages must total 100%."
        case .payerNotFound: "The payer must be one of the participants."
        case .emptyName: "A name is required."
        case .duplicateMember: "This member is already in the group."
        case .groupNotFound: "The group does not exist."
        case .memberNotFound: "This person is not a member of the group."
        case .budgetNotFound: "The budget does not exist."
        case .categoryNotFound: "The budget category does not exist."
        case .invalidSettlement: "A settlement needs two different group members."
        case .settlementExceedsObligation: "The settlement is larger than the amount owed."
        case .persistenceFailure(let reason): "Data could not be saved or loaded: \(reason)"
        }
    }
}
