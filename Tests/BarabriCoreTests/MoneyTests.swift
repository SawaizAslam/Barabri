import XCTest
@testable import BarabriCore

final class MoneyTests: XCTestCase {
    func testRejectsNegativeAmount() {
        XCTAssertThrowsError(try Money(-1)) { error in
            XCTAssertEqual(error as? BarabriError, .invalidAmount)
        }
    }

    func testEncodesAmountAsDecimalStringSoNoPrecisionIsLost() throws {
        let money = try Money(Decimal(string: "1234.56")!)

        let json = String(decoding: try JSONEncoder().encode([money]), as: UTF8.self)

        XCTAssertEqual(json, "[\"1234.56\"]")
    }

    func testDecodesAmountFromDecimalString() throws {
        let data = Data("[\"0.10\",\"3000\"]".utf8)

        let decoded = try JSONDecoder().decode([Money].self, from: data)

        XCTAssertEqual(decoded.map(\.amount), [Decimal(string: "0.1")!, 3000])
    }

    func testDecodingNegativeAmountFails() {
        let data = Data("[\"-5\"]".utf8)

        XCTAssertThrowsError(try JSONDecoder().decode([Money].self, from: data))
    }

    func testDecodingNonNumericStringFails() {
        let data = Data("[\"abc\"]".utf8)

        XCTAssertThrowsError(try JSONDecoder().decode([Money].self, from: data))
    }
}
