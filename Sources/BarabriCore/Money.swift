import Foundation

/// A non-negative PKR amount.
///
/// Encoded as a decimal string (for example `"1234.56"`) rather than a JSON number, because JSON
/// numbers are decoded through `Double` and can silently lose precision (risk R-01).
public struct Money: Equatable, Hashable, Codable, Sendable {
    public let amount: Decimal

    public init(_ amount: Decimal) throws {
        guard amount >= 0 else { throw BarabriError.invalidAmount }
        self.amount = amount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard Self.isPlainDecimal(text),
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "\"\(text)\" is not a decimal amount."
            )
        }
        do {
            try self.init(value)
        } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Amount must not be negative.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(NSDecimalNumber(decimal: amount).stringValue)
    }

    /// `Decimal(string:)` accepts a numeric prefix such as "12abc"; require the whole string to be a number.
    private static func isPlainDecimal(_ text: String) -> Bool {
        var seenDigit = false
        var seenPoint = false
        for (index, character) in text.enumerated() {
            switch character {
            case "0"..."9": seenDigit = true
            case ".": if seenPoint { return false }; seenPoint = true
            case "-": if index != 0 { return false }
            default: return false
            }
        }
        return seenDigit
    }
}
