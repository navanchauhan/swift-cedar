import XCTest
@testable import CedarSpecSwift

final class EvaluatorTests: XCTestCase {
    private let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
    private let action = EntityUID(ty: Name(id: "Action"), eid: "view")
    private let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
    private let staffGroup = EntityUID(ty: Name(id: "Group"), eid: "staff")
    private let engineeringGroup = EntityUID(ty: Name(id: "Group"), eid: "engineering")
    private let companyGroup = EntityUID(ty: Name(id: "Group"), eid: "company")
    private let unrelatedGroup = EntityUID(ty: Name(id: "Group"), eid: "unrelated")
    private let missingUser = EntityUID(ty: Name(id: "User"), eid: "missing")
    private let selfCycleGroup = EntityUID(ty: Name(id: "Group"), eid: "self-cycle")
    private let cycleA = EntityUID(ty: Name(id: "Group"), eid: "cycle-a")
    private let cycleB = EntityUID(ty: Name(id: "Group"), eid: "cycle-b")
    private let cycleTarget = EntityUID(ty: Name(id: "Group"), eid: "cycle-target")
    private let actionReadFamily = EntityUID(ty: Name(id: "Action"), eid: "read-family")
    private let actionAll = EntityUID(ty: Name(id: "Action"), eid: "all")
    private let chain0 = EntityUID(ty: Name(id: "Group"), eid: "chain-0")
    private let chain1 = EntityUID(ty: Name(id: "Group"), eid: "chain-1")
    private let chain2 = EntityUID(ty: Name(id: "Group"), eid: "chain-2")
    private let chain3 = EntityUID(ty: Name(id: "Group"), eid: "chain-3")
    private let chain4 = EntityUID(ty: Name(id: "Group"), eid: "chain-4")
    private let chain5 = EntityUID(ty: Name(id: "Group"), eid: "chain-5")

    private var request: Request {
        Request(
            principal: principal,
            action: action,
            resource: resource,
            context: .record(CedarMap.make([
                (key: "department", value: .string("Engineering")),
                (key: "level", value: .int(5)),
                (key: "active", value: .bool(true)),
            ]))
        )
    }

    private let entities = Entities()

    private var populatedEntities: Entities {
        Entities(CedarMap.make([
            (key: principal, value: EntityData(
                ancestors: CedarSet.make([staffGroup]),
                attrs: CedarMap.make([
                    (key: "department", value: .prim(.string("Engineering"))),
                    (key: "manager", value: .prim(.entityUID(staffGroup))),
                ]),
                tags: CedarMap.make([
                    (key: "active", value: .prim(.bool(true))),
                    (key: "team", value: .prim(.entityUID(engineeringGroup))),
                ])
            )),
            (key: action, value: EntityData(ancestors: CedarSet.make([actionReadFamily]))),
            (key: resource, value: EntityData()),
            (key: staffGroup, value: EntityData(ancestors: CedarSet.make([engineeringGroup]))),
            (key: engineeringGroup, value: EntityData(ancestors: CedarSet.make([companyGroup]))),
            (key: companyGroup, value: EntityData()),
            (key: unrelatedGroup, value: EntityData()),
            (key: selfCycleGroup, value: EntityData(ancestors: CedarSet.make([selfCycleGroup]))),
            (key: cycleA, value: EntityData(ancestors: CedarSet.make([cycleB]))),
            (key: cycleB, value: EntityData(ancestors: CedarSet.make([cycleA]))),
            (key: cycleTarget, value: EntityData()),
            (key: actionReadFamily, value: EntityData(ancestors: CedarSet.make([actionAll]))),
            (key: actionAll, value: EntityData()),
            (key: chain0, value: EntityData(ancestors: CedarSet.make([chain1]))),
            (key: chain1, value: EntityData(ancestors: CedarSet.make([chain2]))),
            (key: chain2, value: EntityData(ancestors: CedarSet.make([chain3]))),
            (key: chain3, value: EntityData(ancestors: CedarSet.make([chain4]))),
            (key: chain4, value: EntityData(ancestors: CedarSet.make([chain5]))),
            (key: chain5, value: EntityData()),
        ]))
    }

    func testVariablesEvaluateToRequestBindings() throws {
        XCTAssertEqual(try evaluate(.variable(.principal), request: request, entities: entities, maxSteps: 1).get(), .prim(.entityUID(principal)))
        XCTAssertEqual(try evaluate(.variable(.action), request: request, entities: entities, maxSteps: 1).get(), .prim(.entityUID(action)))
        XCTAssertEqual(try evaluate(.variable(.resource), request: request, entities: entities, maxSteps: 1).get(), .prim(.entityUID(resource)))
        XCTAssertEqual(
            try evaluate(.variable(.context), request: request, entities: entities, maxSteps: 1).get(),
            .record(CedarMap.make([
                (key: "active", value: .prim(.bool(true))),
                (key: "department", value: .prim(.string("Engineering"))),
                (key: "level", value: .prim(.int(5))),
            ]))
        )
    }

    func testContextVariableMaterializesRestrictedRecordLazily() throws {
        let request = Request(
            principal: principal,
            action: action,
            resource: resource,
            context: .record(CedarMap.make([
                (key: "launchedAt", value: .call(.datetime, [.string("2024-01-01")])),
                (key: "ttl", value: .call(.duration, [.string("1h")])),
            ]))
        )

        XCTAssertEqual(
            try evaluate(.variable(.principal), request: request, entities: entities, maxSteps: 1).get(),
            .prim(.entityUID(principal))
        )
        XCTAssertEqual(
            try evaluate(.variable(.context), request: request, entities: entities, maxSteps: 1).get(),
            .record(CedarMap.make([
                (key: "launchedAt", value: .ext(.datetime(.init(rawValue: "2024-01-01")))),
                (key: "ttl", value: .ext(.duration(.init(rawValue: "1h")))),
            ]))
        )
    }

    func testContextVariablePropagatesRestrictedContextMaterializationFailure() {
        let request = Request(
            principal: principal,
            action: action,
            resource: resource,
            context: .record(CedarMap.make([
                (key: "ttl", value: .call(.duration, [.string("PT1H")])),
            ]))
        )

        XCTAssertEqual(
            failure(of: evaluate(.variable(.context), request: request, entities: entities, maxSteps: 1)),
            .restrictedExprError(.extensionConstructorError(.duration))
        )
    }

    func testEntityAttrsAndTagsRemainDirectModelControlsAfterRestrictedContextMigration() throws {
        let request = Request(
            principal: principal,
            action: action,
            resource: resource,
            context: .record(CedarMap.make([
                (key: "ttl", value: .call(.duration, [.string("PT1H")])),
            ]))
        )

        XCTAssertEqual(
            try evaluate(.getAttr(.variable(.principal), "department"), request: request, entities: populatedEntities, maxSteps: 2).get(),
            .prim(.string("Engineering"))
        )
        XCTAssertEqual(
            try evaluate(
                .binaryApp(.getTag, .variable(.principal), .lit(.prim(.string("active")))),
                request: request,
                entities: populatedEntities,
                maxSteps: 3
            ).get(),
            .prim(.bool(true))
        )
    }

    func testUnaryNotSuccessAndFailure() throws {
        XCTAssertEqual(
            try evaluate(.unaryApp(.not, .lit(.prim(.bool(false)))), request: request, entities: entities, maxSteps: 2).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            failure(of: evaluate(.unaryApp(.not, .lit(.prim(.int(1)))), request: request, entities: entities, maxSteps: 2)),
            .typeError
        )
    }

    func testUnaryNegSuccessAndFailure() throws {
        XCTAssertEqual(
            try evaluate(.unaryApp(.neg, .lit(.prim(.int(5)))), request: request, entities: entities, maxSteps: 2).get(),
            .prim(.int(-5))
        )
        XCTAssertEqual(
            failure(of: evaluate(.unaryApp(.neg, .lit(.prim(.bool(true)))), request: request, entities: entities, maxSteps: 2)),
            .typeError
        )
    }

    func testUnaryIsEmptySupportsEmptyAndNonEmptySetsAndPreservesExistingUnaryRows() throws {
        XCTAssertEqual(
            try evaluate(.unaryApp(.isEmpty, .set([])), request: request, entities: entities, maxSteps: 2).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            try evaluate(
                .unaryApp(.isEmpty, .set([.lit(.prim(.int(1))), .lit(.prim(.int(2)))])),
                request: request,
                entities: entities,
                maxSteps: 4
            ).get(),
            .prim(.bool(false))
        )
        XCTAssertEqual(
            try evaluate(.unaryApp(.not, .lit(.prim(.bool(true)))), request: request, entities: entities, maxSteps: 2).get(),
            .prim(.bool(false))
        )
        XCTAssertEqual(
            try evaluate(.unaryApp(.neg, .lit(.prim(.int(-7)))), request: request, entities: entities, maxSteps: 2).get(),
            .prim(.int(7))
        )
    }

    func testUnaryIsEmptyRejectsRecordScalarEntityAndExtensionOperands() {
        XCTAssertEqual(
            failure(of: evaluate(.unaryApp(.isEmpty, .record([])), request: request, entities: entities, maxSteps: 2)),
            .typeError
        )
        XCTAssertEqual(
            failure(of: evaluate(
                .unaryApp(
                    .isEmpty,
                    .record([(key: "department", value: .lit(.prim(.string("Engineering"))))])
                ),
                request: request,
                entities: entities,
                maxSteps: 3
            )),
            .typeError
        )
        XCTAssertEqual(
            failure(of: evaluate(.unaryApp(.isEmpty, .lit(.prim(.int(0)))), request: request, entities: entities, maxSteps: 2)),
            .typeError
        )
        XCTAssertEqual(
            failure(of: evaluate(
                .unaryApp(.isEmpty, .lit(.prim(.entityUID(principal)))),
                request: request,
                entities: entities,
                maxSteps: 2
            )),
            .typeError
        )
        XCTAssertEqual(
            failure(of: evaluate(
                .unaryApp(.isEmpty, .lit(.ext(.decimal(.init(rawValue: "1.23"))))),
                request: request,
                entities: entities,
                maxSteps: 2
            )),
            .typeError
        )
    }

    func testAddSuccessAndFailure() throws {
        XCTAssertEqual(
            try evaluate(binary(.add, .lit(.prim(.int(20))), .lit(.prim(.int(22)))), request: request, entities: entities, maxSteps: 3).get(),
            .prim(.int(42))
        )
        XCTAssertEqual(
            failure(of: evaluate(binary(.add, .lit(.prim(.int(1))), .lit(.prim(.bool(false)))), request: request, entities: entities, maxSteps: 3)),
            .typeError
        )
    }

    func testSubSuccessAndFailure() throws {
        XCTAssertEqual(
            try evaluate(binary(.sub, .lit(.prim(.int(52))), .lit(.prim(.int(10)))), request: request, entities: entities, maxSteps: 3).get(),
            .prim(.int(42))
        )
        XCTAssertEqual(
            failure(of: evaluate(binary(.sub, .lit(.prim(.int(Int64.min))), .lit(.prim(.int(1)))), request: request, entities: entities, maxSteps: 3)),
            .arithBoundsError
        )
    }

    func testMulSuccessAndFailure() throws {
        XCTAssertEqual(
            try evaluate(binary(.mul, .lit(.prim(.int(6))), .lit(.prim(.int(7)))), request: request, entities: entities, maxSteps: 3).get(),
            .prim(.int(42))
        )
        XCTAssertEqual(
            failure(of: evaluate(binary(.mul, .lit(.prim(.int(6))), .lit(.prim(.string("7")))), request: request, entities: entities, maxSteps: 3)),
            .typeError
        )
    }

    func testContainsSuccessAndFailure() throws {
        XCTAssertEqual(
            try evaluate(
                binary(.contains, .set([.lit(.prim(.int(1))), .lit(.prim(.int(2)))]), .lit(.prim(.int(2)))),
                request: request,
                entities: entities,
                maxSteps: 5
            ).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            failure(of: evaluate(binary(.contains, .lit(.prim(.int(1))), .lit(.prim(.int(1)))), request: request, entities: entities, maxSteps: 3)),
            .typeError
        )
    }

    func testContainsAllSuccessAndFailure() throws {
        XCTAssertEqual(
            try evaluate(
                binary(
                    .containsAll,
                    .set([.lit(.prim(.int(1))), .lit(.prim(.int(2))), .lit(.prim(.int(3)))]),
                    .set([.lit(.prim(.int(2))), .lit(.prim(.int(3)))])
                ),
                request: request,
                entities: entities,
                maxSteps: 8
            ).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            failure(of: evaluate(binary(.containsAll, .set([.lit(.prim(.int(1)))]), .lit(.prim(.int(1)))), request: request, entities: entities, maxSteps: 4)),
            .typeError
        )
    }

    func testContainsAnySuccessAndFailure() throws {
        XCTAssertEqual(
            try evaluate(
                binary(
                    .containsAny,
                    .set([.lit(.prim(.int(1))), .lit(.prim(.int(2)))]),
                    .set([.lit(.prim(.int(2))), .lit(.prim(.int(4)))])
                ),
                request: request,
                entities: entities,
                maxSteps: 7
            ).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            failure(of: evaluate(binary(.containsAny, .lit(.prim(.int(1))), .set([.lit(.prim(.int(1)))])), request: request, entities: entities, maxSteps: 4)),
            .typeError
        )
    }

    func testContainsOperatorsSupportStructuralExtensionMembershipForAllFamilies() throws {
        XCTAssertEqual(
            try evaluate(
                binary(
                    .contains,
                    .set([
                        .lit(.ext(.decimal(.init(rawValue: "1.2300")))),
                        .lit(.ext(.ipaddr(.init(rawValue: "127.0.0.1")))),
                    ]),
                    .lit(.ext(.decimal(.init(rawValue: "1.23"))))
                ),
                request: request,
                entities: populatedEntities,
                maxSteps: 6
            ).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            try evaluate(
                binary(
                    .contains,
                    .set([
                        .lit(.ext(.ipaddr(.init(rawValue: "127.0.0.1/32")))),
                    ]),
                    .lit(.ext(.ipaddr(.init(rawValue: "127.0.0.1"))))
                ),
                request: request,
                entities: populatedEntities,
                maxSteps: 4
            ).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            try evaluate(
                binary(
                    .containsAll,
                    .set([
                        .lit(.ext(.datetime(.init(rawValue: "2024-01-01T00:00:00Z")))),
                        .lit(.ext(.duration(.init(rawValue: "1h")))),
                    ]),
                    .set([
                        .lit(.ext(.datetime(.init(rawValue: "2024-01-01")))),
                        .lit(.ext(.duration(.init(rawValue: "60m")))),
                    ])
                ),
                request: request,
                entities: populatedEntities,
                maxSteps: 7
            ).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            try evaluate(
                binary(
                    .containsAny,
                    .set([
                        .lit(.ext(.datetime(.init(rawValue: "2024-01-01T00:00:00Z")))),
                        .lit(.ext(.duration(.init(rawValue: "1h")))),
                    ]),
                    .set([
                        .lit(.ext(.duration(.init(rawValue: "60m")))),
                        .lit(.ext(.ipaddr(.init(rawValue: "10.0.0.1")))),
                    ])
                ),
                request: request,
                entities: populatedEntities,
                maxSteps: 7
            ).get(),
            .prim(.bool(true))
        )
    }

    func testContainsOperatorsKeepNonExtensionControls() throws {
        XCTAssertEqual(
            try evaluate(
                binary(.contains, .set([.lit(.prim(.int(1))), .lit(.prim(.int(2)))]), .lit(.prim(.int(2)))),
                request: request,
                entities: populatedEntities,
                maxSteps: 5
            ).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            try evaluate(
                binary(
                    .containsAll,
                    .set([.lit(.prim(.int(1))), .lit(.prim(.int(2)))]),
                    .set([])
                ),
                request: request,
                entities: populatedEntities,
                maxSteps: 5
            ).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            try evaluate(
                binary(
                    .containsAny,
                    .set([.lit(.prim(.int(1))), .lit(.prim(.int(2)))]),
                    .set([])
                ),
                request: request,
                entities: populatedEntities,
                maxSteps: 5
            ).get(),
            .prim(.bool(false))
        )
    }

    func testDirectDecimalAndDatetimeExtensionLiteralsEvaluateSuccessfully() throws {
        XCTAssertEqual(
            try evaluate(
                .lit(.ext(.decimal(.init(rawValue: "1.23")))),
                request: request,
                entities: populatedEntities,
                maxSteps: 1
            ).get(),
            .ext(.decimal(.init(rawValue: "1.23")))
        )
        XCTAssertEqual(
            try evaluate(
                .lit(.ext(.datetime(.init(rawValue: "2024-01-01T00:00:00Z")))),
                request: request,
                entities: populatedEntities,
                maxSteps: 1
            ).get(),
            .ext(.datetime(.init(rawValue: "2024-01-01T00:00:00Z")))
        )
    }

    func testDirectIPAddrAndDurationExtensionLiteralsEvaluateSuccessfully() throws {
        XCTAssertEqual(
            try evaluate(
                .lit(.ext(.ipaddr(.init(rawValue: "127.0.0.1")))),
                request: request,
                entities: populatedEntities,
                maxSteps: 1
            ).get(),
            .ext(.ipaddr(.init(rawValue: "127.0.0.1")))
        )
        XCTAssertEqual(
            try evaluate(
                .lit(.ext(.duration(.init(rawValue: "1h")))),
                request: request,
                entities: populatedEntities,
                maxSteps: 1
            ).get(),
            .ext(.duration(.init(rawValue: "1h")))
        )
    }

    func testDecimalBearingLiteralSetEvaluatesSuccessfully() throws {
        XCTAssertEqual(
            try evaluate(
                .lit(.set(CedarSet.make([
                    .ext(.decimal(.init(rawValue: "1.23"))),
                ]))),
                request: request,
                entities: populatedEntities,
                maxSteps: 1
            ).get(),
            .set(CedarSet.make([
                .ext(.decimal(.init(rawValue: "1.23"))),
            ]))
        )
    }

    func testDecimalBearingLiteralRecordEvaluatesSuccessfully() throws {
        XCTAssertEqual(
            try evaluate(
                .lit(.record(CedarMap.make([
                    (key: "nested", value: .ext(.decimal(.init(rawValue: "1.23")))),
                ]))),
                request: request,
                entities: populatedEntities,
                maxSteps: 1
            ).get(),
            .record(CedarMap.make([
                (key: "nested", value: .ext(.decimal(.init(rawValue: "1.23")))),
            ]))
        )
    }

    func testIPAddrBearingLiteralSetEvaluatesSuccessfully() throws {
        XCTAssertEqual(
            try evaluate(
                .lit(.set(CedarSet.make([
                    .ext(.ipaddr(.init(rawValue: "127.0.0.1"))),
                ]))),
                request: request,
                entities: populatedEntities,
                maxSteps: 1
            ).get(),
            .set(CedarSet.make([
                .ext(.ipaddr(.init(rawValue: "127.0.0.1"))),
            ]))
        )
    }

    func testIPAddrBearingLiteralRecordEvaluatesSuccessfully() throws {
        XCTAssertEqual(
            try evaluate(
                .lit(.record(CedarMap.make([
                    (key: "nested", value: .ext(.ipaddr(.init(rawValue: "127.0.0.1")))),
                ]))),
                request: request,
                entities: populatedEntities,
                maxSteps: 1
            ).get(),
            .record(CedarMap.make([
                (key: "nested", value: .ext(.ipaddr(.init(rawValue: "127.0.0.1")))),
            ]))
        )
    }

    func testDatetimeAndDurationBearingLiteralContainersEvaluateSuccessfully() throws {
        XCTAssertEqual(
            try evaluate(
                .lit(.set(CedarSet.make([
                    .ext(.datetime(.init(rawValue: "2024-01-01"))),
                ]))),
                request: request,
                entities: populatedEntities,
                maxSteps: 1
            ).get(),
            .set(CedarSet.make([
                .ext(.datetime(.init(rawValue: "2024-01-01"))),
            ]))
        )
        XCTAssertEqual(
            try evaluate(
                .lit(.record(CedarMap.make([
                    (key: "nested", value: .ext(.duration(.init(rawValue: "1h")))),
                ]))),
                request: request,
                entities: populatedEntities,
                maxSteps: 1
            ).get(),
            .record(CedarMap.make([
                (key: "nested", value: .ext(.duration(.init(rawValue: "1h")))),
            ]))
        )
    }

    func testMixedSupportedExtensionContainersEvaluateSuccessfullyThroughNestedChildren() throws {
        let expr = Expr.record([
            (key: "mixed", value: .set([
                .lit(.ext(.decimal(.init(rawValue: "1.23")))),
                .lit(.ext(.ipaddr(.init(rawValue: "127.0.0.1")))),
                .lit(.ext(.datetime(.init(rawValue: "2024-01-01T00:00:00Z")))),
                .lit(.ext(.duration(.init(rawValue: "1h")))),
            ])),
        ])

        XCTAssertEqual(
            try evaluate(expr, request: request, entities: populatedEntities, maxSteps: 8).get(),
            .record(CedarMap.make([
                (key: "mixed", value: .set(CedarSet.make([
                    .ext(.decimal(.init(rawValue: "1.23"))),
                    .ext(.ipaddr(.init(rawValue: "127.0.0.1"))),
                    .ext(.datetime(.init(rawValue: "2024-01-01T00:00:00Z"))),
                    .ext(.duration(.init(rawValue: "1h"))),
                ]))),
            ]))
        )
    }

    func testDecimalBearingSetEvaluatesSuccessfullyThroughNestedChildren() throws {
        let expr = Expr.set([
            .lit(.prim(.int(1))),
            .record([
                (key: "nested", value: .lit(.ext(.decimal(.init(rawValue: "1.23"))))),
            ]),
        ])

        XCTAssertEqual(
            try evaluate(expr, request: request, entities: populatedEntities, maxSteps: 6).get(),
            .set(CedarSet.make([
                .prim(.int(1)),
                .record(CedarMap.make([
                    (key: "nested", value: .ext(.decimal(.init(rawValue: "1.23")))),
                ])),
            ]))
        )
    }

    func testDecimalBearingRecordEvaluatesSuccessfullyThroughNestedChildren() throws {
        let expr = Expr.record([
            (key: "ok", value: .lit(.prim(.int(1)))),
            (key: "nested", value: .set([
                .lit(.ext(.decimal(.init(rawValue: "1.23")))),
            ])),
        ])

        XCTAssertEqual(
            try evaluate(expr, request: request, entities: populatedEntities, maxSteps: 6).get(),
            .record(CedarMap.make([
                (key: "nested", value: .set(CedarSet.make([
                    .ext(.decimal(.init(rawValue: "1.23"))),
                ]))),
                (key: "ok", value: .prim(.int(1))),
            ]))
        )
    }

    func testIPAddrBearingSetEvaluatesSuccessfullyThroughNestedChildren() throws {
        let expr = Expr.set([
            .lit(.prim(.int(1))),
            .record([
                (key: "nested", value: .lit(.ext(.ipaddr(.init(rawValue: "127.0.0.1"))))),
            ]),
        ])

        XCTAssertEqual(
            try evaluate(expr, request: request, entities: populatedEntities, maxSteps: 6).get(),
            .set(CedarSet.make([
                .prim(.int(1)),
                .record(CedarMap.make([
                    (key: "nested", value: .ext(.ipaddr(.init(rawValue: "127.0.0.1")))),
                ])),
            ]))
        )
    }

    func testIPAddrBearingRecordEvaluatesSuccessfullyThroughNestedChildren() throws {
        let expr = Expr.record([
            (key: "ok", value: .lit(.prim(.int(1)))),
            (key: "nested", value: .set([
                .lit(.ext(.ipaddr(.init(rawValue: "127.0.0.1")))),
            ])),
        ])

        XCTAssertEqual(
            try evaluate(expr, request: request, entities: populatedEntities, maxSteps: 6).get(),
            .record(CedarMap.make([
                (key: "nested", value: .set(CedarSet.make([
                    .ext(.ipaddr(.init(rawValue: "127.0.0.1"))),
                ]))),
                (key: "ok", value: .prim(.int(1))),
            ]))
        )
    }

    func testGenericLessOperatorsReturnTypeErrorForUnsupportedDirectIPAddrAndMixedFamilyOperands() {
        let lhs = Expr.lit(.ext(.ipaddr(.init(rawValue: "127.0.0.1"))))
        let rhs = Expr.lit(.ext(.ipaddr(.init(rawValue: "127.0.0.1/32"))))

        XCTAssertEqual(
            failure(of: evaluate(binary(.lessThan, lhs, rhs), request: request, entities: populatedEntities, maxSteps: 3)),
            .typeError
        )
        XCTAssertEqual(
            failure(of: evaluate(binary(.lessThanOrEqual, lhs, rhs), request: request, entities: populatedEntities, maxSteps: 3)),
            .typeError
        )
        XCTAssertEqual(
            failure(of: evaluate(
                binary(
                    .lessThan,
                    .lit(.ext(.datetime(.init(rawValue: "2024-01-01T00:00:00Z")))),
                    .lit(.ext(.duration(.init(rawValue: "1h"))))
                ),
                request: request,
                entities: populatedEntities,
                maxSteps: 3
            )),
            .typeError
        )
    }

    func testIPAddrCallAndPredicatePathsFollowC4bContracts() throws {
        XCTAssertEqual(
            try evaluate(
                .call(.ip, [.lit(.prim(.string("127.0.0.1")))]),
                request: request,
                entities: populatedEntities,
                maxSteps: 2
            ).get(),
            .ext(.ipaddr(.init(rawValue: "127.0.0.1")))
        )
        XCTAssertEqual(
            try evaluate(
                .call(
                    .isInRange,
                    [
                        .lit(.ext(.ipaddr(.init(rawValue: "10.0.0.1")))),
                        .call(.ip, [.lit(.prim(.string("10.0.0.0/24")))]),
                    ]
                ),
                request: request,
                entities: populatedEntities,
                maxSteps: 4
            ).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            failure(of: evaluate(
                .call(.ip, [.lit(.prim(.string("::ffff:127.0.0.1")))]),
                request: request,
                entities: populatedEntities,
                maxSteps: 2
            )),
            .extensionError
        )
    }

    func testPrimitiveOnlySetAndRecordControlsStillSucceed() throws {
        XCTAssertEqual(
            try evaluate(
                .set([.lit(.prim(.int(1))), .lit(.prim(.int(2)))]),
                request: request,
                entities: populatedEntities,
                maxSteps: 3
            ).get(),
            .set(CedarSet.make([.prim(.int(1)), .prim(.int(2))]))
        )
        XCTAssertEqual(
            try evaluate(
                .record([
                    (key: "department", value: .lit(.prim(.string("Engineering")))),
                    (key: "level", value: .lit(.prim(.int(5)))),
                ]),
                request: request,
                entities: populatedEntities,
                maxSteps: 3
            ).get(),
            .record(CedarMap.make([
                (key: "department", value: .prim(.string("Engineering"))),
                (key: "level", value: .prim(.int(5))),
            ]))
        )
    }

    func testOuterSetAndRecordGuardsAllowSupportedContextValuesButRejectInvalidTemporalPayloads() throws {
        let request = Request(
            principal: principal,
            action: action,
            resource: resource,
            context: .record(CedarMap.make([
                (key: "nested", value: .call(.duration, [.string("1h")])),
            ]))
        )

        XCTAssertEqual(
            try evaluate(
                .set([
                    .lit(.prim(.int(1))),
                    .variable(.context),
                ]),
                request: request,
                entities: populatedEntities,
                maxSteps: 3
            ).get(),
            .set(CedarSet.make([
                .prim(.int(1)),
                .record(CedarMap.make([
                    (key: "nested", value: .ext(.duration(.init(rawValue: "1h")))),
                ])),
            ]))
        )
        XCTAssertEqual(
            try evaluate(
                .record([
                    (key: "ok", value: .lit(.prim(.int(1)))),
                    (key: "ctx", value: .variable(.context)),
                ]),
                request: request,
                entities: populatedEntities,
                maxSteps: 3
            ).get(),
            .record(CedarMap.make([
                (key: "ctx", value: .record(CedarMap.make([
                    (key: "nested", value: .ext(.duration(.init(rawValue: "1h")))),
                ]))),
                (key: "ok", value: .prim(.int(1))),
            ]))
        )

        let invalidTemporalRequest = Request(
            principal: principal,
            action: action,
            resource: resource,
            context: .record(CedarMap.make([
                (key: "nested", value: .call(.duration, [.string("PT1H")])),
            ]))
        )

        XCTAssertEqual(
            failure(of: evaluate(
                .set([
                    .lit(.prim(.int(1))),
                    .variable(.context),
                ]),
                request: invalidTemporalRequest,
                entities: populatedEntities,
                maxSteps: 3
            )),
            .restrictedExprError(.extensionConstructorError(.duration))
        )
    }

    func testLazyFormsSuppressLiteralAndContainerExtensionErrorsOnUnreachedBranches() throws {
        let extensionLiteral = Expr.lit(.ext(.ipaddr(.init(rawValue: "10.0.0.1"))))
        let extensionSet = Expr.set([
            .lit(.prim(.int(1))),
            .lit(.ext(.ipaddr(.init(rawValue: "10.0.0.1")))),
        ])
        let extensionRecord = Expr.record([
            (key: "nested", value: .lit(.ext(.ipaddr(.init(rawValue: "10.0.0.1"))))),
        ])

        XCTAssertEqual(
            try evaluate(.binaryApp(.and, .lit(.prim(.bool(false))), extensionLiteral), request: request, entities: populatedEntities, maxSteps: 2).get(),
            .prim(.bool(false))
        )
        XCTAssertEqual(
            try evaluate(.binaryApp(.or, .lit(.prim(.bool(true))), extensionSet), request: request, entities: populatedEntities, maxSteps: 2).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            try evaluate(.ifThenElse(.lit(.prim(.bool(false))), extensionRecord, .lit(.prim(.int(1)))), request: request, entities: populatedEntities, maxSteps: 3).get(),
            .prim(.int(1))
        )
    }

    func testLazyFormsSuppressWidenedLiteralContainerExtensionErrorsOnUnreachedBranches() throws {
        let literalSet = Expr.lit(.set(CedarSet.make([
            .ext(.ipaddr(.init(rawValue: "10.0.0.1"))),
        ])))
        let literalRecord = Expr.lit(.record(CedarMap.make([
            (key: "nested", value: .ext(.ipaddr(.init(rawValue: "10.0.0.1")))),
        ])))

        XCTAssertEqual(
            try evaluate(.binaryApp(.and, .lit(.prim(.bool(false))), literalSet), request: request, entities: populatedEntities, maxSteps: 2).get(),
            .prim(.bool(false))
        )
        XCTAssertEqual(
            try evaluate(.ifThenElse(.lit(.prim(.bool(false))), literalRecord, .lit(.prim(.int(1)))), request: request, entities: populatedEntities, maxSteps: 3).get(),
            .prim(.int(1))
        )
    }

    func testEqualSuccessAndFailure() throws {
        XCTAssertEqual(
            try evaluate(binary(.equal, .lit(.prim(.string("cedar"))), .lit(.prim(.string("cedar")))), request: request, entities: entities, maxSteps: 3).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            try evaluate(
                binary(
                    .equal,
                    .lit(.ext(.decimal(.init(rawValue: "1.2300")))),
                    .lit(.ext(.decimal(.init(rawValue: "1.23"))))
                ),
                request: request,
                entities: populatedEntities,
                maxSteps: 3
            ).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            failure(of: evaluate(binary(.equal, .getAttr(.variable(.context), "missing"), .lit(.prim(.int(1)))), request: request, entities: entities, maxSteps: 4)),
            .attrDoesNotExist
        )
    }

    func testLessThanSuccessAndFailure() throws {
        XCTAssertEqual(
            try evaluate(binary(.lessThan, .lit(.prim(.int(1))), .lit(.prim(.int(2)))), request: request, entities: entities, maxSteps: 3).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            failure(of: evaluate(binary(.lessThan, .lit(.prim(.string("1"))), .lit(.prim(.string("2")))), request: request, entities: entities, maxSteps: 3)),
            .typeError
        )
    }

    func testLessThanOrEqualSuccessAndFailure() throws {
        XCTAssertEqual(
            try evaluate(binary(.lessThanOrEqual, .lit(.prim(.int(2))), .lit(.prim(.int(2)))), request: request, entities: entities, maxSteps: 3).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            failure(of: evaluate(binary(.lessThanOrEqual, .lit(.prim(.int(2))), .lit(.prim(.bool(true)))), request: request, entities: entities, maxSteps: 3)),
            .typeError
        )
    }

    func testDirectTemporalLessOperatorsSucceedAndRejectInvalidPayloads() throws {
        XCTAssertEqual(
            try evaluate(
                binary(
                    .lessThan,
                    .lit(.ext(.datetime(.init(rawValue: "2024-01-01T00:00:00Z")))),
                    .lit(.ext(.datetime(.init(rawValue: "2024-01-01T00:00:00.001Z"))))
                ),
                request: request,
                entities: populatedEntities,
                maxSteps: 3
            ).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            try evaluate(
                binary(
                    .lessThanOrEqual,
                    .lit(.ext(.duration(.init(rawValue: "60m")))),
                    .lit(.ext(.duration(.init(rawValue: "1h"))))
                ),
                request: request,
                entities: populatedEntities,
                maxSteps: 3
            ).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            failure(of: evaluate(
                binary(
                    .lessThan,
                    .lit(.ext(.datetime(.init(rawValue: "2024-01-01T00:00:60Z")))),
                    .lit(.ext(.datetime(.init(rawValue: "2024-01-01T00:00:00Z"))))
                ),
                request: request,
                entities: populatedEntities,
                maxSteps: 3
            )),
            .extensionError
        )
    }

    func testGenericLessOperatorsReturnTypeErrorForUnsupportedDirectDecimalOperands() {
        let decimal = CedarValue.ext(.decimal(.init(rawValue: "1.23")))

        XCTAssertEqual(
            failure(of: evaluate(binary(.lessThan, .lit(decimal), .lit(decimal)), request: request, entities: populatedEntities, maxSteps: 3)),
            .typeError
        )
        XCTAssertEqual(
            failure(of: evaluate(binary(.lessThanOrEqual, .lit(decimal), .lit(decimal)), request: request, entities: populatedEntities, maxSteps: 3)),
            .typeError
        )
    }

    func testAndShortCircuitsRightHandSide() throws {
        let expr = binary(.and, .lit(.prim(.bool(false))), .getAttr(.variable(.context), "missing"))

        XCTAssertEqual(
            try evaluate(expr, request: request, entities: entities, maxSteps: 2).get(),
            .prim(.bool(false))
        )
    }

    func testOrShortCircuitsRightHandSide() throws {
        let expr = binary(.or, .lit(.prim(.bool(true))), .getAttr(.variable(.context), "missing"))

        XCTAssertEqual(
            try evaluate(expr, request: request, entities: entities, maxSteps: 2).get(),
            .prim(.bool(true))
        )
    }

    func testIfThenElseEvaluatesOnlyTakenBranch() throws {
        let expr = Expr.ifThenElse(
            .lit(.prim(.bool(true))),
            .lit(.prim(.int(42))),
            .getAttr(.variable(.context), "missing")
        )

        XCTAssertEqual(
            try evaluate(expr, request: request, entities: entities, maxSteps: 3).get(),
            .prim(.int(42))
        )
    }

    func testLikeEvaluatesWithWildcardMatching() throws {
        let a = Array("a".unicodeScalars)[0]
        let z = Array("z".unicodeScalars)[0]
        let pattern = Pattern([.literal(a), .wildcard, .literal(z)])

        XCTAssertEqual(
            try evaluate(.like(.lit(.prim(.string("abz"))), pattern), request: request, entities: entities, maxSteps: 2).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            failure(of: evaluate(.like(.lit(.prim(.bool(true))), pattern), request: request, entities: entities, maxSteps: 2)),
            .typeError
        )
    }

    func testRecordHasAttrAndGetAttrUseEvaluatedRecordValues() throws {
        let record = Expr.record([
            (key: "department", value: .getAttr(.variable(.context), "department")),
            (key: "level", value: .lit(.prim(.int(5)))),
        ])

        XCTAssertEqual(
            try evaluate(.hasAttr(record, "department"), request: request, entities: entities, maxSteps: 6).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            try evaluate(.getAttr(record, "department"), request: request, entities: entities, maxSteps: 6).get(),
            .prim(.string("Engineering"))
        )
    }

    func testGetAttrFailsForMissingRecordAttribute() {
        let record = Expr.record([
            (key: "department", value: .lit(.prim(.string("Engineering")))),
        ])

        XCTAssertEqual(
            failure(of: evaluate(.getAttr(record, "missing"), request: request, entities: entities, maxSteps: 3)),
            .attrDoesNotExist
        )
    }

    func testIsEntityTypeSuccessAndFailure() throws {
        XCTAssertEqual(
            try evaluate(.isEntityType(.lit(.prim(.entityUID(principal))), Name(id: "User")), request: request, entities: entities, maxSteps: 2).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            failure(of: evaluate(.isEntityType(.lit(.prim(.string("alice"))), Name(id: "User")), request: request, entities: entities, maxSteps: 2)),
            .typeError
        )
    }

    func testEntityMembershipSupportsDirectAndTransitiveAncestors() throws {
        XCTAssertEqual(
            try evaluate(
                binary(.in, .lit(.prim(.entityUID(principal))), .lit(.prim(.entityUID(staffGroup)))),
                request: request,
                entities: populatedEntities,
                maxSteps: 6
            ).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            try evaluate(
                binary(.in, .lit(.prim(.entityUID(principal))), .lit(.prim(.entityUID(companyGroup)))),
                request: request,
                entities: populatedEntities,
                maxSteps: 8
            ).get(),
            .prim(.bool(true))
        )
    }

    func testEntityMembershipHandlesNonMemberAndMissingEntity() throws {
        XCTAssertEqual(
            try evaluate(
                binary(.in, .lit(.prim(.entityUID(principal))), .lit(.prim(.entityUID(unrelatedGroup)))),
                request: request,
                entities: populatedEntities,
                maxSteps: 8
            ).get(),
            .prim(.bool(false))
        )
        // Per Lean spec and DRT: `in` on a missing entity returns false (missing entities
        // are treated as having empty ancestor sets), not an error
        XCTAssertEqual(
            try evaluate(
                binary(.in, .lit(.prim(.entityUID(missingUser))), .lit(.prim(.entityUID(staffGroup)))),
                request: request,
                entities: populatedEntities,
                maxSteps: 6
            ).get(),
            .prim(.bool(false))
        )
    }

    func testActionHierarchyMembershipUsesEntityTraversal() throws {
        XCTAssertEqual(
            try evaluate(
                binary(.in, .variable(.action), .lit(.prim(.entityUID(actionAll)))),
                request: request,
                entities: populatedEntities,
                maxSteps: 7
            ).get(),
            .prim(.bool(true))
        )
    }

    func testEntityMembershipHandlesCyclesWithoutTrapping() throws {
        XCTAssertEqual(
            try evaluate(
                binary(.in, .lit(.prim(.entityUID(selfCycleGroup))), .lit(.prim(.entityUID(unrelatedGroup)))),
                request: request,
                entities: populatedEntities,
                maxSteps: 6
            ).get(),
            .prim(.bool(false))
        )
        XCTAssertEqual(
            try evaluate(
                binary(.in, .lit(.prim(.entityUID(cycleA))), .lit(.prim(.entityUID(cycleTarget)))),
                request: request,
                entities: populatedEntities,
                maxSteps: 8
            ).get(),
            .prim(.bool(false))
        )
    }

    func testDeepEntityMembershipChainUsesBoundedTraversal() throws {
        let expr = binary(.in, .lit(.prim(.entityUID(chain0))), .lit(.prim(.entityUID(chain5))))

        XCTAssertEqual(
            failure(of: evaluate(expr, request: request, entities: populatedEntities, maxSteps: 7)),
            .evaluationLimitError
        )
        XCTAssertEqual(
            try evaluate(expr, request: request, entities: populatedEntities, maxSteps: 9).get(),
            .prim(.bool(true))
        )
    }

    func testEntityToSetMembershipCoercesEntitiesAndRejectsNonEntityMembers() throws {
        XCTAssertEqual(
            try evaluate(
                binary(
                    .in,
                    .lit(.prim(.entityUID(principal))),
                    .set([
                        .lit(.prim(.entityUID(unrelatedGroup))),
                        .lit(.prim(.entityUID(companyGroup))),
                    ])
                ),
                request: request,
                entities: populatedEntities,
                maxSteps: 10
            ).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            failure(of: evaluate(
                binary(
                    .in,
                    .lit(.prim(.entityUID(principal))),
                    .set([
                        .lit(.prim(.entityUID(companyGroup))),
                        .set([]),
                    ])
                ),
                request: request,
                entities: populatedEntities,
                maxSteps: 10
            )),
            .typeError
        )
    }

    func testEntityToSetMembershipKeepsLeftToRightOperandErrorPrecedence() {
        XCTAssertEqual(
            failure(of: evaluate(
                binary(
                    .in,
                    .getAttr(.variable(.context), "missing"),
                    .set([
                        .lit(.prim(.entityUID(companyGroup))),
                        .set([]),
                    ])
                ),
                request: request,
                entities: populatedEntities,
                maxSteps: 10
            )),
            .attrDoesNotExist
        )
    }

    func testEntityBackedHasAttrAndGetAttrRespectRecordAndEntityBranches() throws {
        XCTAssertEqual(
            try evaluate(.hasAttr(.variable(.principal), "department"), request: request, entities: populatedEntities, maxSteps: 2).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            try evaluate(.hasAttr(.variable(.principal), "missing"), request: request, entities: populatedEntities, maxSteps: 2).get(),
            .prim(.bool(false))
        )
        XCTAssertEqual(
            try evaluate(.getAttr(.variable(.principal), "department"), request: request, entities: populatedEntities, maxSteps: 2).get(),
            .prim(.string("Engineering"))
        )
    }

    func testEntityBackedAttrLookupHandlesMissingEntityAndTypeErrors() {
        XCTAssertEqual(
            failure(of: evaluate(.getAttr(.variable(.principal), "missing"), request: request, entities: populatedEntities, maxSteps: 2)),
            .attrDoesNotExist
        )
        XCTAssertEqual(
            failure(of: evaluate(.hasAttr(.lit(.prim(.bool(true))), "department"), request: request, entities: populatedEntities, maxSteps: 2)),
            .typeError
        )
        XCTAssertEqual(
            tryFailureOrFalse(of: evaluate(.hasAttr(.lit(.prim(.entityUID(missingUser))), "department"), request: request, entities: populatedEntities, maxSteps: 2)),
            .prim(.bool(false))
        )
        XCTAssertEqual(
            failure(of: evaluate(.getAttr(.lit(.prim(.entityUID(missingUser))), "department"), request: request, entities: populatedEntities, maxSteps: 2)),
            .entityDoesNotExist
        )
    }

    func testHasTagAndGetTagRespectContracts() throws {
        XCTAssertEqual(
            try evaluate(
                binary(.hasTag, .variable(.principal), .lit(.prim(.string("active")))),
                request: request,
                entities: populatedEntities,
                maxSteps: 3
            ).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            try evaluate(
                binary(.hasTag, .variable(.principal), .lit(.prim(.string("missing")))),
                request: request,
                entities: populatedEntities,
                maxSteps: 3
            ).get(),
            .prim(.bool(false))
        )
        XCTAssertEqual(
            try evaluate(
                binary(.getTag, .variable(.principal), .lit(.prim(.string("active")))),
                request: request,
                entities: populatedEntities,
                maxSteps: 3
            ).get(),
            .prim(.bool(true))
        )
    }

    func testTagOperatorsHandleTypeAndMissingEntityContracts() {
        XCTAssertEqual(
            failure(of: evaluate(
                binary(.hasTag, .lit(.prim(.bool(true))), .lit(.prim(.string("active")))),
                request: request,
                entities: populatedEntities,
                maxSteps: 3
            )),
            .typeError
        )
        XCTAssertEqual(
            failure(of: evaluate(
                binary(.getTag, .variable(.principal), .lit(.prim(.bool(true)))),
                request: request,
                entities: populatedEntities,
                maxSteps: 3
            )),
            .typeError
        )
        XCTAssertEqual(
            tryFailureOrFalse(of: evaluate(
                binary(.hasTag, .lit(.prim(.entityUID(missingUser))), .lit(.prim(.string("active")))),
                request: request,
                entities: populatedEntities,
                maxSteps: 3
            )),
            .prim(.bool(false))
        )
        XCTAssertEqual(
            failure(of: evaluate(
                binary(.getTag, .lit(.prim(.entityUID(missingUser))), .lit(.prim(.string("active")))),
                request: request,
                entities: populatedEntities,
                maxSteps: 3
            )),
            .entityDoesNotExist
        )
        XCTAssertEqual(
            failure(of: evaluate(
                binary(.getTag, .variable(.principal), .lit(.prim(.string("missing")))),
                request: request,
                entities: populatedEntities,
                maxSteps: 3
            )),
            .tagDoesNotExist
        )
    }

    func testIsEntityTypeHandlesDerivedEntitiesAndMissingEntityPropagation() throws {
        XCTAssertEqual(
            try evaluate(.isEntityType(.variable(.principal), Name(id: "User")), request: request, entities: populatedEntities, maxSteps: 2).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            try evaluate(.isEntityType(.variable(.principal), Name(id: "Group")), request: request, entities: populatedEntities, maxSteps: 2).get(),
            .prim(.bool(false))
        )
        XCTAssertEqual(
            try evaluate(
                .isEntityType(.getAttr(.variable(.principal), "manager"), Name(id: "Group")),
                request: request,
                entities: populatedEntities,
                maxSteps: 4
            ).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            try evaluate(
                .isEntityType(binary(.getTag, .variable(.principal), .lit(.prim(.string("team")))), Name(id: "Group")),
                request: request,
                entities: populatedEntities,
                maxSteps: 5
            ).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            failure(of: evaluate(.isEntityType(.lit(.prim(.string("alice"))), Name(id: "User")), request: request, entities: populatedEntities, maxSteps: 2)),
            .typeError
        )
        XCTAssertEqual(
            failure(of: evaluate(
                .isEntityType(.getAttr(.lit(.prim(.entityUID(missingUser))), "manager"), Name(id: "Group")),
                request: request,
                entities: populatedEntities,
                maxSteps: 3
            )),
            .entityDoesNotExist
        )
    }

    func testDecimalCallAndComparisonPathsFollowC4aContracts() throws {
        let decimalExt = CedarValue.ext(.decimal(.init(rawValue: "1.23")))
        let invalidDurationExt = CedarValue.ext(.duration(.init(rawValue: "PT1H")))

        XCTAssertEqual(
            try evaluate(.call(.decimal, [.lit(.prim(.string("1.23")))]), request: request, entities: populatedEntities, maxSteps: 3).get(),
            decimalExt
        )
        XCTAssertEqual(
            failure(of: evaluate(.call(.decimal, [.lit(.prim(.string("1.23456")))]), request: request, entities: populatedEntities, maxSteps: 3)),
            .extensionError
        )
        XCTAssertEqual(
            failure(of: evaluate(.call(.decimal, []), request: request, entities: populatedEntities, maxSteps: 3)),
            .typeError
        )
        XCTAssertEqual(
            failure(of: evaluate(.call(.lessThan, [.lit(.prim(.int(1))), .lit(.prim(.int(2)))]), request: request, entities: populatedEntities, maxSteps: 3)),
            .typeError
        )
        XCTAssertEqual(
            try evaluate(binary(.equal, .lit(decimalExt), .lit(.ext(.decimal(.init(rawValue: "1.2300"))))), request: request, entities: populatedEntities, maxSteps: 3).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            failure(of: evaluate(binary(.lessThan, .lit(invalidDurationExt), .lit(invalidDurationExt)), request: request, entities: populatedEntities, maxSteps: 3)),
            .extensionError
        )
        XCTAssertEqual(
            failure(of: evaluate(binary(.lessThanOrEqual, .lit(invalidDurationExt), .lit(invalidDurationExt)), request: request, entities: populatedEntities, maxSteps: 3)),
            .extensionError
        )
        XCTAssertEqual(
            failure(of: evaluate(.call(.decimal, [.getAttr(.variable(.context), "missing")]), request: request, entities: populatedEntities, maxSteps: 3)),
            .attrDoesNotExist
        )
    }

    func testDatetimeAndDurationCallAndComparisonPathsFollowC5Contracts() throws {
        XCTAssertEqual(
            try evaluate(
                .call(.datetime, [.lit(.prim(.string("2024-01-01T00:00:00Z")))]),
                request: request,
                entities: populatedEntities,
                maxSteps: 3
            ).get(),
            .ext(.datetime(.init(rawValue: "2024-01-01T00:00:00Z")))
        )
        XCTAssertEqual(
            try evaluate(
                .call(.duration, [.lit(.prim(.string("90m")))]),
                request: request,
                entities: populatedEntities,
                maxSteps: 3
            ).get(),
            .ext(.duration(.init(rawValue: "90m")))
        )
        XCTAssertEqual(
            try evaluate(
                .call(
                    .offset,
                    [
                        .lit(.ext(.datetime(.init(rawValue: "2024-01-01T00:00:00Z")))),
                        .call(.duration, [.lit(.prim(.string("90m")))]),
                    ]
                ),
                request: request,
                entities: populatedEntities,
                maxSteps: 5
            ).get(),
            .ext(.datetime(.init(rawValue: "2024-01-01T01:30:00.000Z")))
        )
        XCTAssertEqual(
            try evaluate(
                .call(
                    .toTime,
                    [
                        .lit(.ext(.datetime(.init(rawValue: "2024-01-01T18:20:30.045Z")))),
                    ]
                ),
                request: request,
                entities: populatedEntities,
                maxSteps: 3
            ).get(),
            .ext(.duration(.init(rawValue: "18h20m30s45ms")))
        )
        XCTAssertEqual(
            failure(of: evaluate(
                .call(.datetime, [.lit(.prim(.string("2024-01-01T00:00:60Z")))]),
                request: request,
                entities: populatedEntities,
                maxSteps: 3
            )),
            .extensionError
        )
        XCTAssertEqual(
            failure(of: evaluate(
                .call(.duration, [.lit(.prim(.string("PT1H")))]),
                request: request,
                entities: populatedEntities,
                maxSteps: 3
            )),
            .extensionError
        )
    }

    func testLazyFormsSuppressExtensionErrorsOnUnreachedBranches() throws {
        let extensionCall = Expr.call(.decimal, [.lit(.prim(.string("1.23456")))])
        let extensionCompare = binary(
            .equal,
            .lit(.ext(.duration(.init(rawValue: "PT1H")))),
            .lit(.ext(.duration(.init(rawValue: "PT1H"))))
        )

        XCTAssertEqual(
            try evaluate(binary(.and, .lit(.prim(.bool(false))), extensionCall), request: request, entities: populatedEntities, maxSteps: 2).get(),
            .prim(.bool(false))
        )
        XCTAssertEqual(
            try evaluate(binary(.or, .lit(.prim(.bool(true))), extensionCompare), request: request, entities: populatedEntities, maxSteps: 2).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            try evaluate(
                .ifThenElse(.lit(.prim(.bool(false))), extensionCall, .lit(.prim(.int(7)))),
                request: request,
                entities: populatedEntities,
                maxSteps: 3
            ).get(),
            .prim(.int(7))
        )
    }

    func testLazyFormsSuppressContainsExtensionErrorsOnUnreachedBranch() throws {
        let extensionContainsAny = binary(
            .containsAny,
            .set([.lit(.ext(.decimal(.init(rawValue: "1.23"))))]),
            .set([.lit(.prim(.int(1)))])
        )

        XCTAssertEqual(
            try evaluate(
                binary(.and, .lit(.prim(.bool(false))), extensionContainsAny),
                request: request,
                entities: populatedEntities,
                maxSteps: 4
            ).get(),
            .prim(.bool(false))
        )
    }

    func testRemainingEagerEntityPathsPreferLeftFailure() {
        XCTAssertEqual(
            failure(of: evaluate(
                binary(.in, .getAttr(.variable(.context), "missing"), .call(.decimal, [])),
                request: request,
                entities: populatedEntities,
                maxSteps: 6
            )),
            .attrDoesNotExist
        )
        XCTAssertEqual(
            failure(of: evaluate(
                binary(.getTag, .getAttr(.variable(.context), "missing"), .unaryApp(.neg, .lit(.prim(.bool(true))))),
                request: request,
                entities: populatedEntities,
                maxSteps: 6
            )),
            .attrDoesNotExist
        )
    }

    func testSetEvaluationIsLeftToRightOnFailure() {
        let expr = Expr.set([
            .getAttr(.variable(.context), "missing"),
            .unaryApp(.neg, .lit(.prim(.int(Int64.min)))),
        ])

        XCTAssertEqual(
            failure(of: evaluate(expr, request: request, entities: entities, maxSteps: 6)),
            .attrDoesNotExist
        )
    }

    func testRecordEvaluationIsLeftToRightOnFailure() {
        let expr = Expr.record([
            (key: "first", value: .getAttr(.variable(.context), "missing")),
            (key: "second", value: .unaryApp(.neg, .lit(.prim(.int(Int64.min))))),
        ])

        XCTAssertEqual(
            failure(of: evaluate(expr, request: request, entities: entities, maxSteps: 6)),
            .attrDoesNotExist
        )
    }

    func testBinaryOperatorsChooseLeftFailureBeforeRightFailure() {
        let expr = binary(
            .add,
            .getAttr(.variable(.context), "missing"),
            .unaryApp(.neg, .lit(.prim(.int(Int64.min))))
        )

        XCTAssertEqual(
            failure(of: evaluate(expr, request: request, entities: entities, maxSteps: 6)),
            .attrDoesNotExist
        )
    }

    func testRecordDuplicateKeysEvaluateLeftToRightButCanonicalizeToEarliestEntry() throws {
        let successExpr = Expr.record([
            (key: "department", value: .lit(.prim(.string("Engineering")))),
            (key: "department", value: .lit(.prim(.string("Finance")))),
        ])

        let value = try evaluate(successExpr, request: request, entities: entities, maxSteps: 5).get()
        XCTAssertEqual(value, .record(CedarMap.make([
            (key: "department", value: .prim(.string("Engineering"))),
            (key: "department", value: .prim(.string("Finance"))),
        ])))

        let failingExpr = Expr.record([
            (key: "department", value: .lit(.prim(.string("Engineering")))),
            (key: "department", value: .getAttr(.variable(.context), "missing")),
        ])

        XCTAssertEqual(
            failure(of: evaluate(failingExpr, request: request, entities: entities, maxSteps: 6)),
            .attrDoesNotExist
        )
    }

    func testEvaluationLimitSeamIsDeterministic() throws {
        let expr = binary(.add, .lit(.prim(.int(1))), .lit(.prim(.int(2))))

        XCTAssertEqual(
            failure(of: evaluate(expr, request: request, entities: entities, maxSteps: 2)),
            .evaluationLimitError
        )
        XCTAssertEqual(
            try evaluate(expr, request: request, entities: entities, maxSteps: 3).get(),
            .prim(.int(3))
        )
    }

    private func binary(_ op: BinaryOp, _ lhs: Expr, _ rhs: Expr) -> Expr {
        .binaryApp(op, lhs, rhs)
    }

    private func tryFailureOrFalse(of result: CedarResult<CedarValue>) -> CedarValue {
        switch result {
        case let .success(value):
            return value
        case let .failure(error):
            XCTFail("Expected success but got \(error)")
            return .prim(.bool(false))
        }
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
