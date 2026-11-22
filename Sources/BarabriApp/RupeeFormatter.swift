import Foundation

/// Formats PKR amounts for display, for example "Rs. 3,000" or "-Rs. 3,000".
enum RupeeFormatter {
    static func string(from amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfUp

        // The sign is added by hand so that it always sits before "Rs.".
        let digits = formatter.string(from: NSDecimalNumber(decimal: amount.magnitude)) ?? "0"
        let sign = amount < 0 ? "-" : ""
        return "\(sign)Rs. \(digits)"
    }
}
