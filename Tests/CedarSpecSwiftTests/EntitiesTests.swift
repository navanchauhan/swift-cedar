import XCTest
@testable import CedarSpecSwift

final class EntitiesTests: XCTestCase {
    private let user = EntityUID(ty: Name(id: "User"), eid: "alice")
    private let group = EntityUID(ty: Name(id: "Group"), eid: "staff")
    private let role = EntityUID(ty: Name(id: "Role"), eid: "admin")
    private let project = EntityUID(ty: Name(id: "Project"), eid: "phoenix")
    private let composedEAcute = "\u{00E9}"
    private let decomposedEAcute = "e\u{0301}"

    func testFailingAccessorsReturnEntityDoesNotExistForMissingEntity() {
        let entities = Entities()

        XCTAssertEqual(failure(of: entities.ancestors(user)), .entityDoesNotExist)
        XCTAssertEqual(failure(of: entities.attrs(user)), .entityDoesNotExist)
        XCTAssertEqual(failure(of: entities.tags(user)), .entityDoesNotExist)
    }

    func testOrEmptyAccessorsReturnEmptyForMissingEntity() {
        let entities = Entities()

        XCTAssertEqual(entities.ancestorsOrEmpty(user), .empty)
        XCTAssertEqual(entities.attrsOrEmpty(user), .empty)
        XCTAssertEqual(entities.tagsOrEmpty(user), .empty)
    }

    func testExistingEntityWithEmptyCollectionsSucceedsWithoutFailure() throws {
        let entities = Entities(CedarMap.make([
            (key: user, value: EntityData()),
        ]))

        XCTAssertEqual(try entities.ancestors(user).get(), .empty)
        XCTAssertEqual(try entities.attrs(user).get(), .empty)
        XCTAssertEqual(try entities.tags(user).get(), .empty)
    }

    func testAccessorsReturnStoredAncestorsAttrsAndTags() throws {
        let entityData = EntityData(
            ancestors: CedarSet.make([role, group]),
            attrs: CedarMap.make([
                (key: "team", value: .prim(.string("engineering"))),
                (key: "level", value: .prim(.int(7))),
            ]),
            tags: CedarMap.make([
                (key: "active", value: .prim(.bool(true))),
            ])
        )
        let entities = Entities(CedarMap.make([
            (key: user, value: entityData),
        ]))

        XCTAssertEqual(try entities.ancestors(user).get(), CedarSet.make([group, role]))
        XCTAssertEqual(try entities.attrs(user).get(), entityData.attrs)
        XCTAssertEqual(try entities.tags(user).get(), entityData.tags)
    }

    func testAttrAndTagStorageRemainScalarStrictAndCanonical() throws {
        let entityData = EntityData(
            attrs: CedarMap.make([
                (key: composedEAcute, value: .prim(.string("composed"))),
                (key: decomposedEAcute, value: .prim(.string("decomposed"))),
            ]),
            tags: CedarMap.make([
                (key: composedEAcute, value: .prim(.bool(true))),
                (key: decomposedEAcute, value: .prim(.bool(false))),
            ])
        )
        let entities = Entities(CedarMap.make([
            (key: user, value: entityData),
        ]))

        let attrs = try entities.attrs(user).get()
        let tags = try entities.tags(user).get()

        XCTAssertEqual(attrs.entries.map(\.key), [decomposedEAcute, composedEAcute])
        XCTAssertEqual(tags.entries.map(\.key), [decomposedEAcute, composedEAcute])
        XCTAssertEqual(attrs.find(decomposedEAcute), .prim(.string("decomposed")))
        XCTAssertEqual(attrs.find(composedEAcute), .prim(.string("composed")))
        XCTAssertEqual(tags.find(decomposedEAcute), .prim(.bool(false)))
        XCTAssertEqual(tags.find(composedEAcute), .prim(.bool(true)))
    }

    func testEntitiesEqualityIsDeterministicAcrossInsertionOrder() {
        let first = Entities(CedarMap.make([
            (key: project, value: EntityData(tags: CedarMap.make([
                (key: "beta", value: .prim(.bool(true))),
                (key: "alpha", value: .prim(.bool(false))),
            ]))),
            (key: user, value: EntityData(
                ancestors: CedarSet.make([role, group]),
                attrs: CedarMap.make([
                    (key: "zeta", value: .prim(.int(2))),
                    (key: "alpha", value: .prim(.int(1))),
                ]),
                tags: CedarMap.make([
                    (key: "owner", value: .prim(.string("alice"))),
                    (key: "region", value: .prim(.string("us-east-1"))),
                ])
            )),
        ]))
        let second = Entities(CedarMap.make([
            (key: user, value: EntityData(
                ancestors: CedarSet.make([group, role]),
                attrs: CedarMap.make([
                    (key: "alpha", value: .prim(.int(1))),
                    (key: "zeta", value: .prim(.int(2))),
                ]),
                tags: CedarMap.make([
                    (key: "region", value: .prim(.string("us-east-1"))),
                    (key: "owner", value: .prim(.string("alice"))),
                ])
            )),
            (key: project, value: EntityData(tags: CedarMap.make([
                (key: "alpha", value: .prim(.bool(false))),
                (key: "beta", value: .prim(.bool(true))),
            ]))),
        ]))

        XCTAssertEqual(first, second)
    }

    private func failure<T>(of result: CedarResult<T>) -> CedarError {
        switch result {
        case .success:
            XCTFail("Expected failure")
            return .typeError
        case let .failure(error):
            return error
        }
    }
}