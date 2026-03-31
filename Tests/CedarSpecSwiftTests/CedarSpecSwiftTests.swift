import XCTest
@testable import CedarSpecSwift

final class CedarSpecSwiftTests: XCTestCase {
    func testPackageSmokeExprRecordPreservesDuplicateKeys() {
        let expression = Expr.record([
            (key: "department", value: .lit(.prim(.string("Engineering")))),
            (key: "department", value: .getAttr(.variable(.context), "department")),
        ])

        guard case let .record(entries) = expression else {
            return XCTFail("Expected record expression")
        }

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.key), ["department", "department"])
    }
}
