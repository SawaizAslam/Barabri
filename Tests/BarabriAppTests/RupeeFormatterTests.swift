import XCTest
@testable import BarabriApp

final class RupeeFormatterTests: XCTestCase {
    func testZeroFormatsWithoutFraction() {
        XCTAssertEqual(RupeeFormatter.string(from: 0), "Rs. 0")
    }

    func testWholeAmountGetsCommaGrouping() {
        XCTAssertEqual(RupeeFormatter.string(from: 3000), "Rs. 3,000")
    }

    func testNegativeAmountPutsMinusBeforeRs() {
        XCTAssertEqual(RupeeFormatter.string(from: -3000), "-Rs. 3,000")
    }

    func testLargeAmountGroupsEveryThreeDigits() {
        XCTAssertEqual(RupeeFormatter.string(from: 1_234_567), "Rs. 1,234,567")
    }

    func testOneFractionDigitIsKept() {
        XCTAssertEqual(RupeeFormatter.string(from: Decimal(string: "1234.5")!), "Rs. 1,234.5")
    }

    func testFractionIsLimitedToTwoDigits() {
        XCTAssertEqual(RupeeFormatter.string(from: Decimal(string: "1234.567")!), "Rs. 1,234.57")
    }
}
