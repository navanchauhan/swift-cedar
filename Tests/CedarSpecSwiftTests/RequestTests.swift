import XCTest
@testable import CedarSpecSwift

final class RequestTests: XCTestCase {
    private let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
    private let action = EntityUID(ty: Name(id: "Action"), eid: "view")
    private let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
    private let composedEAcute = "\u{00E9}"
    private let decomposedEAcute = "e\u{0301}"

    func testFrozenInitializerStoresPropertiesAndDefaultsContextToEmpty() {
        let request = Request(principal: principal, action: action, resource: resource)

        XCTAssertEqual(request.principal, principal)
        XCTAssertEqual(request.action, action)
        XCTAssertEqual(request.resource, resource)
        XCTAssertEqual(request.context, .emptyRecord)
    }

    func testContextCanonicalizationUsesScalarStrictAttrOrdering() {
        let request = Request(
            principal: principal,
            action: action,
            resource: resource,
            context: .record(CedarMap.make([
                (key: composedEAcute, value: .string("composed")),
                (key: decomposedEAcute, value: .string("decomposed")),
            ]))
        )

        guard case let .record(context) = request.context else {
            return XCTFail("Expected restricted record context")
        }

        XCTAssertEqual(context.entries.map(\.key), [decomposedEAcute, composedEAcute])
        XCTAssertEqual(context.find(decomposedEAcute), .string("decomposed"))
        XCTAssertEqual(context.find(composedEAcute), .string("composed"))
    }

    func testEqualityUsesDeterministicContextMapSemantics() {
        let lhs = Request(
            principal: principal,
            action: action,
            resource: resource,
            context: .record(CedarMap.make([
                (key: "zeta", value: .int(2)),
                (key: "alpha", value: .int(1)),
            ]))
        )
        let rhs = Request(
            principal: principal,
            action: action,
            resource: resource,
            context: .record(CedarMap.make([
                (key: "alpha", value: .int(1)),
                (key: "zeta", value: .int(2)),
            ]))
        )

        XCTAssertEqual(lhs, rhs)
    }
}
