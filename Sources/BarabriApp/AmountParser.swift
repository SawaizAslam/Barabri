import Foundation
import BarabriCore

/// Turns text typed by the user into a positive amount.
enum AmountParser {
    private static let allowedCharacters = Set("0123456789.")

    /// Trims whitespace, ignores "," separators, and accepts only digits with at most one ".".
    /// - Throws: `BarabriError.invalidAmount` when the text is not a positive number.
    static func parse(_ text: String) throws -> Decimal {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")

        guard cleaned.allSatisfy({ allowedCharacters.contains($0) }),
              cleaned.contains(where: { $0.isASCII && $0.isNumber }),
              cleaned.filter({ $0 == "." }).count <= 1,
              let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")),
              value > 0
        else {
            throw BarabriError.invalidAmount
        }
        return value
    }
}
