import XCTest
@testable import BarabriApp
import BarabriCore

final class AmountParserTests: XCTestCase {
    func testWholeNumberParses() throws {
        let value = try AmountParser.parse("250")
        XCTAssertEqual(value, 250)
    }

    func testSurroundingWhitespaceIsTrimmed() throws {
        let value = try AmountParser.parse(" 250.75 ")
        XCTAssertEqual(value, Decimal(string: "250.75")!)
    }

    func testCommaSeparatorsAreIgnored() throws {
        let value = try AmountParser.parse("1,500")
        XCTAssertEqual(value, 1500)
    }

    func testEmptyTextIsRejected() {
        assertInvalidAmount("")
    }

    func testWhitespaceOnlyTextIsRejected() {
        assertInvalidAmount("   ")
    }

    func testLettersAreRejected() {
        assertInvalidAmount("abc")
    }

    func testTrailingLettersAreRejected() {
        assertInvalidAmount("12abc")
    }

    func testNegativeAmountIsRejected() {
        assertInvalidAmount("-5")
    }

    func testZeroIsRejected() {
        assertInvalidAmount("0")
    }

    func testTwoDecimalPointsAreRejected() {
        assertInvalidAmount("1.2.3")
    }

    func testLoneDecimalPointIsRejected() {
        assertInvalidAmount(".")
    }

    private func assertInvalidAmount(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try AmountParser.parse(text), file: file, line: line) { error in
            XCTAssertEqual(error as? BarabriError, BarabriError.invalidAmount, file: file, line: line)
        }
    }
}
