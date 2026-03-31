import XCTest
@testable import CedarSpecSwift

final class PolicyTests: XCTestCase {
    private let userType = Name(id: "User")
    private let groupType = Name(id: "Group")
    private let actionType = Name(id: "Action")
    private let photoType = Name(id: "Photo")
    private let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
    private let group = EntityUID(ty: Name(id: "Group"), eid: "staff")
    private let readAction = EntityUID(ty: Name(id: "Action"), eid: "read")
    private let writeAction = EntityUID(ty: Name(id: "Action"), eid: "write")
    private let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
    private let composedEAcute = "\u{00E9}"
    private let decomposedEAcute = "e\u{0301}"

    func testEffectComparableUsesLeanConstructorOrder() {
        XCTAssertEqual(Effect.allCases, [.permit, .forbid])
        XCTAssertEqual([Effect.forbid, .permit].sorted(), Effect.allCases)
    }

    func testConditionKindComparableUsesLeanConstructorOrder() {
        XCTAssertEqual(ConditionKind.allCases, [.when, .unless])
        XCTAssertEqual([ConditionKind.unless, .when].sorted(), ConditionKind.allCases)
    }

    func testConditionEqualityAndHashRoundTrip() {
        let lhs = Condition(kind: .unless, body: .lit(.prim(.bool(false))))
        let rhs = Condition(kind: .unless, body: .lit(.prim(.bool(false))))

        XCTAssertEqual(lhs, rhs)
        XCTAssertEqual(hash(of: lhs), hash(of: rhs))
    }

    func testPolicyEqualityHashAndDefaultEmptyConditionsInitializer() {
        let lhs = Policy(
            id: "allow-read",
            effect: .permit,
            principalScope: .eq(entity: principal),
            actionScope: .eq(entity: readAction),
            resourceScope: .eq(entity: resource)
        )
        let rhs = Policy(
            id: "allow-read",
            effect: .permit,
            principalScope: .eq(entity: principal),
            actionScope: .eq(entity: readAction),
            resourceScope: .eq(entity: resource),
            conditions: []
        )

        XCTAssertEqual(lhs.conditions, [])
        XCTAssertEqual(lhs, rhs)
        XCTAssertEqual(hash(of: lhs), hash(of: rhs))
    }

    func testPrincipalScopeToExprCoversEveryConstructor() {
        XCTAssertEqual(PrincipalScope.any.toExpr(), .lit(.prim(.bool(true))))
        XCTAssertEqual(
            PrincipalScope.eq(entity: principal).toExpr(),
            .binaryApp(.equal, .variable(.principal), .lit(.prim(.entityUID(principal))))
        )
        XCTAssertEqual(
            PrincipalScope.in(entity: group).toExpr(),
            .binaryApp(.in, .variable(.principal), .lit(.prim(.entityUID(group))))
        )
        XCTAssertEqual(
            PrincipalScope.isEntityType(entityType: userType).toExpr(),
            .isEntityType(.variable(.principal), userType)
        )
        XCTAssertEqual(
            PrincipalScope.isEntityTypeIn(entityType: userType, entity: group).toExpr(),
            .binaryApp(
                .and,
                .isEntityType(.variable(.principal), userType),
                .binaryApp(.in, .variable(.principal), .lit(.prim(.entityUID(group))))
            )
        )
    }

    func testActionScopeToExprCoversEveryConstructor() {
        XCTAssertEqual(ActionScope.any.toExpr(), .lit(.prim(.bool(true))))
        XCTAssertEqual(
            ActionScope.eq(entity: readAction).toExpr(),
            .binaryApp(.equal, .variable(.action), .lit(.prim(.entityUID(readAction))))
        )
        XCTAssertEqual(
            ActionScope.in(entity: writeAction).toExpr(),
            .binaryApp(.in, .variable(.action), .lit(.prim(.entityUID(writeAction))))
        )
        XCTAssertEqual(
            ActionScope.isEntityType(entityType: actionType).toExpr(),
            .isEntityType(.variable(.action), actionType)
        )
        XCTAssertEqual(
            ActionScope.isEntityTypeIn(entityType: actionType, entity: group).toExpr(),
            .binaryApp(
                .and,
                .isEntityType(.variable(.action), actionType),
                .binaryApp(.in, .variable(.action), .lit(.prim(.entityUID(group))))
            )
        )
        XCTAssertEqual(
            ActionScope.actionInAny(entities: CedarSet.make([writeAction, readAction, writeAction])).toExpr(),
            .binaryApp(
                .in,
                .variable(.action),
                .set([
                    .lit(.prim(.entityUID(readAction))),
                    .lit(.prim(.entityUID(writeAction))),
                ])
            )
        )
    }

    func testResourceScopeToExprCoversEveryConstructor() {
        XCTAssertEqual(ResourceScope.any.toExpr(), .lit(.prim(.bool(true))))
        XCTAssertEqual(
            ResourceScope.eq(entity: resource).toExpr(),
            .binaryApp(.equal, .variable(.resource), .lit(.prim(.entityUID(resource))))
        )
        XCTAssertEqual(
            ResourceScope.in(entity: group).toExpr(),
            .binaryApp(.in, .variable(.resource), .lit(.prim(.entityUID(group))))
        )
        XCTAssertEqual(
            ResourceScope.isEntityType(entityType: photoType).toExpr(),
            .isEntityType(.variable(.resource), photoType)
        )
        XCTAssertEqual(
            ResourceScope.isEntityTypeIn(entityType: photoType, entity: group).toExpr(),
            .binaryApp(
                .and,
                .isEntityType(.variable(.resource), photoType),
                .binaryApp(.in, .variable(.resource), .lit(.prim(.entityUID(group))))
            )
        )
    }

    func testScalarDistinctPolicyIDsRemainDistinctAndCanonicalized() {
        let first = permitPolicy(id: composedEAcute)
        let second = forbidPolicy(id: decomposedEAcute)
        let policies: Policies = .make([
            (key: composedEAcute, value: first),
            (key: decomposedEAcute, value: second),
        ])

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(policies.keys.elements, [decomposedEAcute, composedEAcute])
        XCTAssertEqual(policies.find(decomposedEAcute), second)
        XCTAssertEqual(policies.find(composedEAcute), first)
    }

    func testPoliciesDuplicateKeysKeepEarliestOccurrence() {
        let first = permitPolicy(id: "duplicate")
        let second = forbidPolicy(id: "duplicate")
        let policies: Policies = .make([
            (key: "duplicate", value: first),
            (key: "duplicate", value: second),
        ])

        XCTAssertEqual(policies.find("duplicate"), first)
        XCTAssertEqual(policies.entries.count, 1)
    }

    func testConditionToExprLowersWhenAndUnless() {
        let whenCondition = Condition(kind: .when, body: .lit(.prim(.bool(true))))
        let unlessCondition = Condition(kind: .unless, body: .lit(.prim(.bool(false))))

        XCTAssertEqual(whenCondition.toExpr(), .lit(.prim(.bool(true))))
        XCTAssertEqual(unlessCondition.toExpr(), .unaryApp(.not, .lit(.prim(.bool(false)))))
    }

    func testPolicyToExprUsesTrueIdentityForZeroConditions() {
        let policy = Policy(
            id: "allow-all-users",
            effect: .permit,
            principalScope: .eq(entity: principal),
            actionScope: .eq(entity: readAction),
            resourceScope: .eq(entity: resource)
        )

        XCTAssertEqual(policy.toExpr(), expectedPolicyExpr(
            principalClause: .binaryApp(.equal, .variable(.principal), .lit(.prim(.entityUID(principal)))),
            actionClause: .binaryApp(.equal, .variable(.action), .lit(.prim(.entityUID(readAction)))),
            resourceClause: .binaryApp(.equal, .variable(.resource), .lit(.prim(.entityUID(resource)))),
            conditionsClause: .lit(.prim(.bool(true)))
        ))
    }

    func testPolicyToExprLowersSingleWhenCondition() {
        let conditionExpr = Expr.hasAttr(.variable(.context), "department")
        let policy = Policy(
            id: "when-policy",
            effect: .permit,
            principalScope: .any,
            actionScope: .eq(entity: readAction),
            resourceScope: .isEntityType(entityType: photoType),
            conditions: [Condition(kind: .when, body: conditionExpr)]
        )

        XCTAssertEqual(policy.toExpr(), expectedPolicyExpr(
            principalClause: .lit(.prim(.bool(true))),
            actionClause: .binaryApp(.equal, .variable(.action), .lit(.prim(.entityUID(readAction)))),
            resourceClause: .isEntityType(.variable(.resource), photoType),
            conditionsClause: conditionExpr
        ))
    }

    func testPolicyToExprLowersSingleUnlessCondition() {
        let conditionExpr = Expr.hasAttr(.variable(.context), "blocked")
        let policy = Policy(
            id: "unless-policy",
            effect: .forbid,
            principalScope: .isEntityType(entityType: userType),
            actionScope: .any,
            resourceScope: .any,
            conditions: [Condition(kind: .unless, body: conditionExpr)]
        )

        XCTAssertEqual(policy.toExpr(), expectedPolicyExpr(
            principalClause: .isEntityType(.variable(.principal), userType),
            actionClause: .lit(.prim(.bool(true))),
            resourceClause: .lit(.prim(.bool(true))),
            conditionsClause: .unaryApp(.not, conditionExpr)
        ))
    }

    func testPolicyToExprRightNestsMultipleConditionsInSourceOrder() {
        let first = Condition(kind: .when, body: .hasAttr(.variable(.context), "owner"))
        let second = Condition(kind: .unless, body: .hasAttr(.variable(.context), "blocked"))
        let third = Condition(kind: .when, body: .getAttr(.variable(.context), "department"))
        let policy = Policy(
            id: "multi-condition",
            effect: .permit,
            principalScope: .isEntityTypeIn(entityType: userType, entity: group),
            actionScope: .actionInAny(entities: CedarSet.make([writeAction, readAction])),
            resourceScope: .isEntityTypeIn(entityType: photoType, entity: resource),
            conditions: [first, second, third]
        )

        XCTAssertEqual(policy.toExpr(), expectedPolicyExpr(
            principalClause: .binaryApp(
                .and,
                .isEntityType(.variable(.principal), userType),
                .binaryApp(.in, .variable(.principal), .lit(.prim(.entityUID(group))))
            ),
            actionClause: .binaryApp(
                .in,
                .variable(.action),
                .set([
                    .lit(.prim(.entityUID(readAction))),
                    .lit(.prim(.entityUID(writeAction))),
                ])
            ),
            resourceClause: .binaryApp(
                .and,
                .isEntityType(.variable(.resource), photoType),
                .binaryApp(.in, .variable(.resource), .lit(.prim(.entityUID(resource))))
            ),
            conditionsClause: .binaryApp(
                .and,
                .hasAttr(.variable(.context), "owner"),
                .binaryApp(
                    .and,
                    .unaryApp(.not, .hasAttr(.variable(.context), "blocked")),
                    .getAttr(.variable(.context), "department")
                )
            )
        ))
    }

    private func permitPolicy(id: PolicyID) -> Policy {
        Policy(
            id: id,
            effect: .permit,
            principalScope: .isEntityType(entityType: userType),
            actionScope: .eq(entity: readAction),
            resourceScope: .isEntityType(entityType: photoType)
        )
    }

    private func forbidPolicy(id: PolicyID) -> Policy {
        Policy(
            id: id,
            effect: .forbid,
            principalScope: .in(entity: group),
            actionScope: .in(entity: writeAction),
            resourceScope: .isEntityTypeIn(entityType: photoType, entity: resource)
        )
    }

    private func expectedPolicyExpr(
        principalClause: Expr,
        actionClause: Expr,
        resourceClause: Expr,
        conditionsClause: Expr
    ) -> Expr {
        .binaryApp(
            .and,
            principalClause,
            .binaryApp(
                .and,
                actionClause,
                .binaryApp(.and, resourceClause, conditionsClause)
            )
        )
    }

    private func hash(of value: some Hashable) -> Int {
        var hasher = Hasher()
        hasher.combine(value)
        return hasher.finalize()
    }
}