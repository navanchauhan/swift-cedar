import XCTest
@testable import CedarSpecSwift

final class RequestLoaderTests: XCTestCase {
    func testLoadRequestMaterializesRestrictedContextAndValidatesSchema() {
        let schema = unwrapLoad(loadSchema(LoaderFixtures.schemaJSON))
        let request = unwrapLoad(loadRequest(LoaderFixtures.requestJSON, schema: schema, source: "request.json"))

        XCTAssertEqual(request.action, EntityUID(ty: Name(id: "Action"), eid: "view"))
        XCTAssertEqual(unwrapResult(evaluate(.variable(.context), request: request, entities: Entities())), .record(CedarMap.make([
            (key: "department", value: .prim(.string("Engineering"))),
            (key: "ttl", value: .ext(.duration(.init(rawValue: "1h"))))
        ])))
    }

    func testLoadRequestRejectsInvalidRestrictedExtensionConstructor() {
        let diagnostics = unwrapFailure(loadRequest(LoaderFixtures.invalidRequestJSON, source: "request.json"))
        XCTAssertEqual(diagnostics.elements.first?.code, "request.invalidContext")
    }
}