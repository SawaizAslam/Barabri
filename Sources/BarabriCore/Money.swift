import Foundation

public struct Money: Equatable, Codable, Sendable {
    public let amount: Decimal

    public init(_ amount: Decimal) throws {
        guard amount >= 0 else { throw BarabriError.invalidAmount }
        self.amount = amount
    }
}
