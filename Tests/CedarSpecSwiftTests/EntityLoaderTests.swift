import XCTest
@testable import CedarSpecSwift

final class EntityLoaderTests: XCTestCase {
    func testLoadEntitiesMaterializesAttrsTagsAndActionConstraints() {
        let schema = unwrapLoad(loadSchema(LoaderFixtures.schemaJSON))
        let entities = unwrapLoad(loadEntities(LoaderFixtures.entitiesJSON, schema: schema))
        let alice = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")

        XCTAssertEqual(unwrapResult(entities.attrs(alice)).find("department"), .prim(.string("Engineering")))
        XCTAssertEqual(unwrapResult(entities.tags(alice)).find("active"), .prim(.bool(true)))
        XCTAssertEqual(unwrapResult(entities.ancestors(action)), CedarSet.make([EntityUID(ty: Name(id: "Action"), eid: "read")]))
    }

    func testLoadEntitiesRejectsCycles() {
        let diagnostics = unwrapFailure(loadEntities(LoaderFixtures.cycleEntitiesJSON))
        XCTAssertEqual(diagnostics.elements.first?.code, "entity.cycle")
    }
}