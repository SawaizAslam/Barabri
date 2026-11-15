import Foundation

/// Creator in the GoF Factory Method pattern.
///
/// `makeStrategy()` is the factory method: each conforming type decides which
/// `SplitStrategy` (the Product) to create. `allocate` is the operation that
/// relies on the factory method and never names a concrete strategy.
public protocol SplitStrategyCreator: Sendable {
    /// The factory method.
    func makeStrategy() -> any SplitStrategy
}

extension SplitStrategyCreator {
    /// Operation that uses the product returned by the factory method.
    public func allocate(total: Decimal, participants: [ParticipantID]) throws -> Allocations {
        try makeStrategy().allocate(total: total, participants: participants)
    }
}

/// ConcreteCreator for equal splits.
public struct EqualSplitCreator: SplitStrategyCreator {
    public init() {}

    public func makeStrategy() -> any SplitStrategy {
        EqualSplitStrategy()
    }
}

/// ConcreteCreator for exact-amount splits.
public struct ExactAmountSplitCreator: SplitStrategyCreator {
    public let allocations: Allocations

    public init(allocations: Allocations) {
        self.allocations = allocations
    }

    public func makeStrategy() -> any SplitStrategy {
        ExactAmountSplitStrategy(requestedAllocations: allocations)
    }
}

/// ConcreteCreator for percentage splits.
public struct PercentageSplitCreator: SplitStrategyCreator {
    public let percentages: [ParticipantID: Decimal]

    public init(percentages: [ParticipantID: Decimal]) {
        self.percentages = percentages
    }

    public func makeStrategy() -> any SplitStrategy {
        PercentageSplitStrategy(percentages: percentages)
    }
}

/// The kinds of split a caller can request. Each case maps to its own creator,
/// so adding a split type means adding a creator rather than editing a switch.
public enum SplitType: Sendable {
    case equal
    case exact(Allocations)
    case percentage([ParticipantID: Decimal])

    public var creator: any SplitStrategyCreator {
        switch self {
        case .equal: EqualSplitCreator()
        case .exact(let allocations): ExactAmountSplitCreator(allocations: allocations)
        case .percentage(let percentages): PercentageSplitCreator(percentages: percentages)
        }
    }
}
