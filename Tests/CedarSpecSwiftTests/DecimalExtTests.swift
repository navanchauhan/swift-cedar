import XCTest
@testable import CedarSpecSwift

final class DecimalExtTests: XCTestCase {
    func testDecimalParseMatchesLeanScaleAndCanonicalRendering() {
        XCTAssertEqual(decimalParse("1.23"), 12_300)
        XCTAssertEqual(decimalParse("-0.1"), -1_000)
        XCTAssertEqual(decimalCanonicalString(12_300), "1.2300")
        XCTAssertEqual(decimalCanonicalString(-1_000), "-0.1000")
    }

    func testDecimalParseRejectsMalformedInputs() {
        XCTAssertNil(decimalParse("-"))
        XCTAssertNil(decimalParse("1"))
        XCTAssertNil(decimalParse("1."))
        XCTAssertNil(decimalParse(".1"))
        XCTAssertNil(decimalParse("1.23456"))
    }

    func testDecimalDispatchDistinguishesSuccessParseFailureWrongArityAndWrongType() {
        XCTAssertEqual(
            dispatchExtensionCall(.decimal, arguments: [.prim(.string("1.2300"))]),
            .success(.ext(.decimal(.init(rawValue: "1.2300"))))
        )
        XCTAssertEqual(
            dispatchExtensionCall(.decimal, arguments: [.prim(.string("invalid"))]),
            .failure(.extensionError)
        )
        XCTAssertEqual(
            dispatchExtensionCall(.decimal, arguments: []),
            .failure(.typeError)
        )
        XCTAssertEqual(
            dispatchExtensionCall(.decimal, arguments: [.prim(.int(1))]),
            .failure(.typeError)
        )
    }
}