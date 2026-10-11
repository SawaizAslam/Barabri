import Foundation

public enum BarabriError: Error, Equatable, LocalizedError {
    case invalidAmount
    case noParticipants
    case participantNotFound
    case invalidAllocationTotal
    case invalidPercentageTotal
    case payerNotFound

    public var errorDescription: String? {
        switch self {
        case .invalidAmount: "Amount must be greater than zero."
        case .noParticipants: "At least one participant is required."
        case .participantNotFound: "Every allocation must belong to a participant."
        case .invalidAllocationTotal: "Allocations must equal the expense total."
        case .invalidPercentageTotal: "Percentages must total 100%."
        case .payerNotFound: "The payer must be one of the participants."
        }
    }
}
