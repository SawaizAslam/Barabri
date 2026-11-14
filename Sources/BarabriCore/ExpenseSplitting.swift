import Foundation

public struct ParticipantID: Hashable, Codable, Sendable {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }
}

public typealias Allocations = [ParticipantID: Decimal]

public protocol SplitStrategy: Sendable {
    func allocate(total: Decimal, participants: [ParticipantID]) throws -> Allocations
}

/// Shared checks run before any split strategy computes allocations.
private func validateSplitInput(total: Decimal, participants: [ParticipantID]) throws {
    guard total > 0 else { throw BarabriError.invalidAmount }
    guard !participants.isEmpty else { throw BarabriError.noParticipants }
    guard Set(participants).count == participants.count else { throw BarabriError.duplicateParticipant }
}

public struct EqualSplitStrategy: SplitStrategy {
    public init() {}

    public func allocate(total: Decimal, participants: [ParticipantID]) throws -> Allocations {
        try validateSplitInput(total: total, participants: participants)
        let share = (total / Decimal(participants.count)).rounded(scale: 2)
        var result = Dictionary(uniqueKeysWithValues: participants.map { ($0, share) })
        let difference = total - result.values.reduce(0, +)
        result[participants[0], default: 0] += difference
        return result
    }
}

public struct ExactAmountSplitStrategy: SplitStrategy {
    public let requestedAllocations: Allocations

    public init(requestedAllocations: Allocations) {
        self.requestedAllocations = requestedAllocations
    }

    public func allocate(total: Decimal, participants: [ParticipantID]) throws -> Allocations {
        try validateSplitInput(total: total, participants: participants)
        guard Set(requestedAllocations.keys) == Set(participants) else {
            throw BarabriError.participantNotFound
        }
        guard requestedAllocations.values.allSatisfy({ $0 >= 0 }) else {
            throw BarabriError.invalidAmount
        }
        guard requestedAllocations.values.reduce(0, +) == total else {
            throw BarabriError.invalidAllocationTotal
        }
        return requestedAllocations
    }
}

public struct PercentageSplitStrategy: SplitStrategy {
    public let percentages: [ParticipantID: Decimal]

    public init(percentages: [ParticipantID: Decimal]) {
        self.percentages = percentages
    }

    public func allocate(total: Decimal, participants: [ParticipantID]) throws -> Allocations {
        try validateSplitInput(total: total, participants: participants)
        guard Set(percentages.keys) == Set(participants) else {
            throw BarabriError.participantNotFound
        }
        guard percentages.values.allSatisfy({ $0 >= 0 }) else {
            throw BarabriError.invalidAmount
        }
        guard percentages.values.reduce(0, +) == 100 else {
            throw BarabriError.invalidPercentageTotal
        }
        // Keys were verified to match participants above, so the default is never used.
        let raw = participants.reduce(into: Allocations()) { result, participant in
            result[participant] = (total * (percentages[participant] ?? 0)) / 100
        }
        let rounded = raw.mapValues { $0.rounded(scale: 2) }
        let difference = total - rounded.values.reduce(0, +)
        var result = rounded
        result[participants[0], default: 0] += difference
        return result
    }
}

public enum SplitType: Sendable {
    case equal
    case exact(Allocations)
    case percentage([ParticipantID: Decimal])
}

public struct SplitStrategyFactory: Sendable {
    public init() {}

    public func make(_ type: SplitType) -> any SplitStrategy {
        switch type {
        case .equal: EqualSplitStrategy()
        case .exact(let allocations): ExactAmountSplitStrategy(requestedAllocations: allocations)
        case .percentage(let percentages): PercentageSplitStrategy(percentages: percentages)
        }
    }
}

private extension Decimal {
    func rounded(scale: Int) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .bankers)
        return result
    }
}
