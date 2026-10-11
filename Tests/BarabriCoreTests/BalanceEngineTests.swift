import XCTest
@testable import BarabriCore

final class BalanceEngineTests: XCTestCase {
    func testPayerCashDecreasesByFullAmountButPersonalExpenseIsOnlyOwnShare() throws {
        let ali = ParticipantID("Ali")
        let ahmed = ParticipantID("Ahmed")
        let expense = try Expense(
            total: 3000,
            payer: ali,
            allocations: [ali: 1000, ahmed: 2000]
        )

        let result = BalanceEngine().calculate(for: expense)

        XCTAssertEqual(result.cashChange, -3000)
        XCTAssertEqual(result.personalExpense, 1000)
        XCTAssertEqual(result.receivables[ahmed], 2000)
    }
}
