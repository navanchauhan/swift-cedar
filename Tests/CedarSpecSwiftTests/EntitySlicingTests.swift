import XCTest
@testable import CedarSpecSwift

final class EntitySlicingTests: XCTestCase {
    private let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
    private let action = EntityUID(ty: Name(id: "Action"), eid: "view")
    private let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
    private let staff = EntityUID(ty: Name(id: "Group"), eid: "staff")
    private let company = EntityUID(ty: Name(id: "Group"), eid: "company")
    private let manager = EntityUID(ty: Name(id: "User"), eid: "manager")

    private var entities: Entities {
        Entities(CedarMap.make([
            (key: principal, value: EntityData(
                ancestors: CedarSet.make([staff]),
                attrs: CedarMap.make([(key: "manager", value: .prim(.entityUID(manager)))]),
                tags: .empty
            )),
            (key: staff, value: EntityData(ancestors: CedarSet.make([company]))),
            (key: company, value: EntityData()),
            (key: manager, value: EntityData()),
        ]))
    }

    func testSliceEUIDsResolvesConcreteRequestVariables() {
        let request = Request(
            principal: principal,
            action: action,
            resource: resource,
            context: .record(CedarMap.make([
                (key: "owner", value: .entityUID(company)),
            ]))
        )
        let expr = Expr.binaryApp(
            .and,
            .binaryApp(.equal, .variable(.principal), .lit(.prim(.entityUID(staff)))),
            .binaryApp(.equal, .variable(.context), .lit(.record(CedarMap.make([
                (key: "owner", value: .prim(.entityUID(company))),
            ]))))
        )

        XCTAssertEqual(sliceEUIDs(expr), CedarSet.make([staff, company]))
        XCTAssertEqual(sliceEUIDs(expr, request: request), CedarSet.make([principal, staff, company]))
        XCTAssertEqual(sliceEUIDs(request), CedarSet.make([principal, action, resource, company]))
    }

    func testSliceAtLevelTraversesAncestorsAndEntityValuedAttributesBreadthFirst() {
        let level0 = sliceAtLevel(CedarSet.make([principal]), entities: entities, level: 0)
        let level1 = sliceAtLevel(CedarSet.make([principal]), entities: entities, level: 1)
        let level2 = sliceAtLevel(CedarSet.make([principal]), entities: entities, level: 2)

        XCTAssertEqual(level0.required, CedarSet.make([principal]))
        XCTAssertEqual(level1.required, CedarSet.make([principal, staff, manager]))
        XCTAssertEqual(level2.required, CedarSet.make([principal, staff, manager, company]))
    }
}