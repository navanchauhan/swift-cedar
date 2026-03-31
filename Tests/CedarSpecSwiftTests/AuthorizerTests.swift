import XCTest
@testable import CedarSpecSwift

final class AuthorizerTests: XCTestCase {
    private let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
    private let otherPrincipal = EntityUID(ty: Name(id: "User"), eid: "bob")
    private let action = EntityUID(ty: Name(id: "Action"), eid: "view")
    private let otherAction = EntityUID(ty: Name(id: "Action"), eid: "edit")
    private let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
    private let otherResource = EntityUID(ty: Name(id: "Photo"), eid: "archive")

    private var request: Request {
        Request(
            principal: principal,
            action: action,
            resource: resource,
            context: .record(CedarMap.make([
                (key: "active", value: .bool(true)),
                (key: "department", value: .string("Engineering")),
            ]))
        )
    }

    private let entities = Entities()

    func testHelperPredicatesSeparateSatisfiedUnsatisfiedAndErroredPolicies() {
        let satisfiedPermit = permitPolicy(id: "permit-satisfied")
        let unsatisfiedPermit = permitPolicy(id: "permit-unsatisfied", actionScope: .eq(entity: otherAction))
        let erroredPermit = permitPolicy(
            id: "permit-errored",
            conditions: [Condition(kind: .when, body: .getAttr(.variable(.context), "missing"))]
        )
        let policies: Policies = .make([
            (key: satisfiedPermit.id, value: satisfiedPermit),
            (key: unsatisfiedPermit.id, value: unsatisfiedPermit),
            (key: erroredPermit.id, value: erroredPermit),
        ])

        XCTAssertTrue(satisfied(satisfiedPermit, request, entities))
        XCTAssertFalse(satisfied(unsatisfiedPermit, request, entities))
        XCTAssertEqual(satisfiedWithEffect(.permit, satisfiedPermit, request, entities), "permit-satisfied")
        XCTAssertNil(satisfiedWithEffect(.forbid, satisfiedPermit, request, entities))
        XCTAssertEqual(
            satisfiedPolicies(.permit, policies, request, entities),
            CedarSet.make(["permit-satisfied"])
        )
        XCTAssertFalse(hasError(satisfiedPermit, request, entities))
        XCTAssertTrue(hasError(erroredPermit, request, entities))
        XCTAssertNil(errored(satisfiedPermit, request, entities))
        XCTAssertEqual(errored(erroredPermit, request, entities), "permit-errored")
        XCTAssertEqual(errorPolicies(policies, request, entities), CedarSet.make(["permit-errored"]))
    }

    func testSatisfiedPermitAllowsAndDeterminesPermitPolicy() {
        let policy = permitPolicy(id: "permit-allow")
        let response = isAuthorized(
            request: request,
            entities: entities,
            policies: .make([(key: policy.id, value: policy)])
        )

        XCTAssertEqual(response.decision, .allow)
        XCTAssertEqual(response.determining, CedarSet.make([policy.id]))
        XCTAssertEqual(response.erroring, .empty)
    }

    func testIsAuthorizedStillAllowsPoliciesWhenRestrictedContextMaterializesSuccessfully() {
        let request = Request(
            principal: principal,
            action: action,
            resource: resource,
            context: .record(CedarMap.make([
                (key: "ttl", value: .call(.duration, [.string("1h")])),
            ]))
        )
        let policy = permitPolicy(
            id: "permit-restricted-context-success",
            conditions: [Condition(kind: .when, body: .hasAttr(.variable(.context), "ttl"))]
        )
        let response = isAuthorized(
            request: request,
            entities: entities,
            policies: .make([(key: policy.id, value: policy)])
        )

        XCTAssertEqual(response.decision, .allow)
        XCTAssertEqual(response.determining, CedarSet.make([policy.id]))
        XCTAssertEqual(response.erroring, .empty)
    }

    func testIsAuthorizedPropagatesRestrictedContextFailureIntoErroring() {
        let request = Request(
            principal: principal,
            action: action,
            resource: resource,
            context: .record(CedarMap.make([
                (key: "ttl", value: .call(.duration, [.string("PT1H")])),
            ]))
        )
        let policy = permitPolicy(
            id: "permit-restricted-context-error",
            conditions: [Condition(kind: .when, body: .hasAttr(.variable(.context), "ttl"))]
        )
        let response = isAuthorized(
            request: request,
            entities: entities,
            policies: .make([(key: policy.id, value: policy)])
        )

        XCTAssertEqual(response.decision, .deny)
        XCTAssertEqual(response.determining, .empty)
        XCTAssertEqual(response.erroring, CedarSet.make([policy.id]))
    }

    func testSatisfiedForbidDeniesAndDeterminesForbidPolicy() {
        let policy = forbidPolicy(id: "forbid-deny")
        let response = isAuthorized(
            request: request,
            entities: entities,
            policies: .make([(key: policy.id, value: policy)])
        )

        XCTAssertEqual(response.decision, .deny)
        XCTAssertEqual(response.determining, CedarSet.make([policy.id]))
        XCTAssertEqual(response.erroring, .empty)
    }

    func testUnsatisfiedPermitDoesNotPopulateDeterminingOrErroring() {
        let policy = permitPolicy(id: "permit-unsatisfied", actionScope: .eq(entity: otherAction))
        let response = isAuthorized(
            request: request,
            entities: entities,
            policies: .make([(key: policy.id, value: policy)])
        )

        XCTAssertEqual(response.decision, .deny)
        XCTAssertEqual(response.determining, .empty)
        XCTAssertEqual(response.erroring, .empty)
    }

    func testUnsatisfiedForbidDoesNotPopulateDeterminingOrErroring() {
        let policy = forbidPolicy(id: "forbid-unsatisfied", resourceScope: .eq(entity: otherResource))
        let response = isAuthorized(
            request: request,
            entities: entities,
            policies: .make([(key: policy.id, value: policy)])
        )

        XCTAssertEqual(response.decision, .deny)
        XCTAssertEqual(response.determining, .empty)
        XCTAssertEqual(response.erroring, .empty)
    }

    func testErroredPolicyPopulatesErroringOnly() {
        let policy = permitPolicy(
            id: "permit-errored",
            conditions: [Condition(kind: .when, body: .getAttr(.variable(.context), "missing"))]
        )
        let response = isAuthorized(
            request: request,
            entities: entities,
            policies: .make([(key: policy.id, value: policy)])
        )

        XCTAssertEqual(response.decision, .deny)
        XCTAssertEqual(response.determining, .empty)
        XCTAssertEqual(response.erroring, CedarSet.make([policy.id]))
    }

    func testMultipleSatisfiedPermitsAggregateIntoAllow() {
        let first = permitPolicy(id: "permit-a")
        let second = permitPolicy(id: "permit-b", principalScope: .isEntityType(entityType: Name(id: "User")))
        let response = isAuthorized(
            request: request,
            entities: entities,
            policies: .make([
                (key: first.id, value: first),
                (key: second.id, value: second),
            ])
        )

        XCTAssertEqual(response.decision, .allow)
        XCTAssertEqual(response.determining, CedarSet.make([first.id, second.id]))
        XCTAssertEqual(response.erroring, .empty)
    }

    func testMultipleSatisfiedForbidsAggregateIntoDeny() {
        let first = forbidPolicy(id: "forbid-a")
        let second = forbidPolicy(id: "forbid-b", principalScope: .isEntityType(entityType: Name(id: "User")))
        let response = isAuthorized(
            request: request,
            entities: entities,
            policies: .make([
                (key: first.id, value: first),
                (key: second.id, value: second),
            ])
        )

        XCTAssertEqual(response.decision, .deny)
        XCTAssertEqual(response.determining, CedarSet.make([first.id, second.id]))
        XCTAssertEqual(response.erroring, .empty)
    }

    func testPermitAndForbidConflictDeterminesOnlyForbids() {
        let permit = permitPolicy(id: "permit-conflict")
        let forbid = forbidPolicy(id: "forbid-conflict")
        let response = isAuthorized(
            request: request,
            entities: entities,
            policies: .make([
                (key: permit.id, value: permit),
                (key: forbid.id, value: forbid),
            ])
        )

        XCTAssertEqual(response.decision, .deny)
        XCTAssertEqual(response.determining, CedarSet.make([forbid.id]))
        XCTAssertEqual(response.erroring, .empty)
        XCTAssertFalse(response.determining.contains(permit.id))
    }

    func testImplicitDenyWithNoSatisfiedPoliciesHasEmptyDetermining() {
        let permit = permitPolicy(id: "permit-unsatisfied", actionScope: .eq(entity: otherAction))
        let forbid = forbidPolicy(id: "forbid-unsatisfied", principalScope: .eq(entity: otherPrincipal))
        let response = isAuthorized(
            request: request,
            entities: entities,
            policies: .make([
                (key: permit.id, value: permit),
                (key: forbid.id, value: forbid),
            ])
        )

        XCTAssertEqual(response.decision, .deny)
        XCTAssertEqual(response.determining, .empty)
        XCTAssertEqual(response.erroring, .empty)
    }

    func testImplicitDenyWithErrorsKeepsEmptyDeterminingAndExactErroring() {
        let unsatisfied = permitPolicy(id: "permit-unsatisfied", actionScope: .eq(entity: otherAction))
        let errored = forbidPolicy(
            id: "forbid-errored",
            conditions: [Condition(kind: .when, body: .getAttr(.variable(.context), "missing"))]
        )
        let response = isAuthorized(
            request: request,
            entities: entities,
            policies: .make([
                (key: unsatisfied.id, value: unsatisfied),
                (key: errored.id, value: errored),
            ])
        )

        XCTAssertEqual(response.decision, .deny)
        XCTAssertEqual(response.determining, .empty)
        XCTAssertEqual(response.erroring, CedarSet.make([errored.id]))
    }

    func testMixedSatisfiedAndErroredPoliciesRemainDisjoint() {
        let permit = permitPolicy(id: "permit-satisfied")
        let errored = forbidPolicy(
            id: "forbid-errored",
            conditions: [Condition(kind: .when, body: .getAttr(.variable(.context), "missing"))]
        )
        let response = isAuthorized(
            request: request,
            entities: entities,
            policies: .make([
                (key: permit.id, value: permit),
                (key: errored.id, value: errored),
            ])
        )

        XCTAssertEqual(response.decision, .allow)
        XCTAssertEqual(response.determining, CedarSet.make([permit.id]))
        XCTAssertEqual(response.erroring, CedarSet.make([errored.id]))
        XCTAssertFalse(response.erroring.contains(permit.id))
        XCTAssertFalse(response.determining.contains(errored.id))
    }

    func testMultiConditionPoliciesUseWhenAndUnless() {
        let policy = permitPolicy(
            id: "permit-multi-condition",
            conditions: [
                Condition(kind: .when, body: .getAttr(.variable(.context), "active")),
                Condition(kind: .unless, body: .hasAttr(.variable(.context), "blocked")),
            ]
        )
        let response = isAuthorized(
            request: request,
            entities: entities,
            policies: .make([(key: policy.id, value: policy)])
        )

        XCTAssertEqual(response.decision, .allow)
        XCTAssertEqual(response.determining, CedarSet.make([policy.id]))
        XCTAssertEqual(response.erroring, .empty)
    }

    func testDuplicatePolicyIDsOnlyLetRetainedEarliestPolicyAffectResponse() {
        let retained = permitPolicy(id: "duplicate-policy")
        let ignored = forbidPolicy(
            id: "duplicate-policy",
            conditions: [Condition(kind: .when, body: .getAttr(.variable(.context), "missing"))]
        )
        let response = isAuthorized(
            request: request,
            entities: entities,
            policies: .make([
                (key: retained.id, value: retained),
                (key: ignored.id, value: ignored),
            ])
        )

        XCTAssertEqual(response.decision, .allow)
        XCTAssertEqual(response.determining, CedarSet.make([retained.id]))
        XCTAssertEqual(response.erroring, .empty)
    }

    func testIsAuthorizedGivesEachPolicyAFreshBudget() throws {
        let first = Policy(
            id: "permit-fuel-a",
            effect: .permit,
            principalScope: .any,
            actionScope: .any,
            resourceScope: .any
        )
        let second = Policy(
            id: "permit-fuel-b",
            effect: .permit,
            principalScope: .any,
            actionScope: .any,
            resourceScope: .any
        )
        let policies: Policies = .make([
            (key: first.id, value: first),
            (key: second.id, value: second),
        ])

        XCTAssertEqual(
            try evaluate(first.toExpr(), request: request, entities: entities, maxSteps: 7).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            failure(of: evaluate(first.toExpr(), request: request, entities: entities, maxSteps: 6)),
            .evaluationLimitError
        )

        let response = isAuthorized(
            request: request,
            entities: entities,
            policies: policies,
            maxStepsPerPolicy: 7
        )

        XCTAssertEqual(response.decision, .allow)
        XCTAssertEqual(response.determining, CedarSet.make([first.id, second.id]))
        XCTAssertEqual(response.erroring, .empty)
    }

    func testCompiledAuthorizerMatchesInterpretedAuthorizer() {
        let permit = permitPolicy(
            id: "permit-compiled-match",
            conditions: [
                Condition(kind: .when, body: .getAttr(.variable(.context), "active")),
                Condition(kind: .unless, body: .hasAttr(.variable(.context), "blocked")),
            ]
        )
        let forbid = forbidPolicy(
            id: "forbid-compiled-error",
            conditions: [Condition(kind: .when, body: .getAttr(.variable(.context), "missing"))]
        )
        let policies: Policies = .make([
            (key: permit.id, value: permit),
            (key: forbid.id, value: forbid),
        ])
        let interpreted = isAuthorized(
            request: request,
            entities: entities,
            policies: policies,
            evaluatePolicy: { policy, request, entities in
                evaluate(policy.toExpr(), request: request, entities: entities)
            }
        )
        let compiled = isAuthorizedCompiled(
            request: request,
            entities: entities,
            compiledPolicies: CompiledPolicies(policies)
        )

        XCTAssertEqual(compiled, interpreted)
    }

    func testCompiledAuthorizerPreservesEvaluationBudgetParity() {
        let policy = Policy(
            id: "permit-compiled-budget",
            effect: .permit,
            principalScope: .any,
            actionScope: .any,
            resourceScope: .any
        )
        let policies: Policies = .make([(key: policy.id, value: policy)])
        let compiledPolicies = CompiledPolicies(policies)

        XCTAssertEqual(
            isAuthorizedCompiled(
                request: request,
                entities: entities,
                compiledPolicies: compiledPolicies,
                maxStepsPerPolicy: 7
            ),
            Response(decision: .allow, determining: CedarSet.make([policy.id]), erroring: .empty)
        )
        XCTAssertEqual(
            isAuthorizedCompiled(
                request: request,
                entities: entities,
                compiledPolicies: compiledPolicies,
                maxStepsPerPolicy: 6
            ),
            Response(decision: .deny, determining: .empty, erroring: CedarSet.make([policy.id]))
        )
    }

    func testDecimalPermitConditionAllowsWhenComparisonSucceeds() {
        let policy = permitPolicy(
            id: "permit-decimal-allow",
            conditions: [Condition(
                kind: .when,
                body: .call(
                    .greaterThan,
                    [
                        .call(.decimal, [.lit(.prim(.string("1.2300")))]),
                        .lit(.ext(.decimal(.init(rawValue: "1.2")))),
                    ]
                )
            )]
        )

        let response = isAuthorized(
            request: request,
            entities: entities,
            policies: .make([(key: policy.id, value: policy)])
        )

        XCTAssertEqual(response.decision, .allow)
        XCTAssertEqual(response.determining, CedarSet.make([policy.id]))
        XCTAssertEqual(response.erroring, .empty)
    }

    func testDecimalParseFailureFlowsIntoAuthorizerErroringWithoutChangingDecisionTable() {
        let policy = permitPolicy(
            id: "permit-decimal-error",
            conditions: [Condition(
                kind: .when,
                body: .call(
                    .lessThan,
                    [
                        .call(.decimal, [.lit(.prim(.string("1.23456")))]),
                        .lit(.ext(.decimal(.init(rawValue: "2.0")))),
                    ]
                )
            )]
        )

        let response = isAuthorized(
            request: request,
            entities: entities,
            policies: .make([(key: policy.id, value: policy)])
        )

        XCTAssertEqual(response.decision, .deny)
        XCTAssertEqual(response.determining, .empty)
        XCTAssertEqual(response.erroring, CedarSet.make([policy.id]))
    }

    func testIPAddrPermitConditionAllowsWhenRangeCheckSucceeds() {
        let policy = permitPolicy(
            id: "permit-ipaddr-allow",
            conditions: [Condition(
                kind: .when,
                body: .call(
                    .isInRange,
                    [
                        .lit(.ext(.ipaddr(.init(rawValue: "10.0.0.1")))),
                        .call(.ip, [.lit(.prim(.string("10.0.0.0/24")))]),
                    ]
                )
            )]
        )

        let response = isAuthorized(
            request: request,
            entities: entities,
            policies: .make([(key: policy.id, value: policy)])
        )

        XCTAssertEqual(response.decision, .allow)
        XCTAssertEqual(response.determining, CedarSet.make([policy.id]))
        XCTAssertEqual(response.erroring, .empty)
    }

    func testIPAddrParseFailureFlowsIntoAuthorizerErroringWithoutChangingDecisionTable() {
        let policy = permitPolicy(
            id: "permit-ipaddr-error",
            conditions: [Condition(
                kind: .when,
                body: .call(
                    .isLoopback,
                    [
                        .call(.ip, [.lit(.prim(.string("::ffff:127.0.0.1")))]),
                    ]
                )
            )]
        )

        let response = isAuthorized(
            request: request,
            entities: entities,
            policies: .make([(key: policy.id, value: policy)])
        )

        XCTAssertEqual(response.decision, .deny)
        XCTAssertEqual(response.determining, .empty)
        XCTAssertEqual(response.erroring, CedarSet.make([policy.id]))
    }

    func testDatetimePermitConditionAllowsWhenDirectTemporalComparisonSucceeds() {
        let policy = permitPolicy(
            id: "permit-datetime-allow",
            conditions: [Condition(
                kind: .when,
                body: .binaryApp(
                    .lessThan,
                    .call(.datetime, [.lit(.prim(.string("2024-01-01T00:00:00Z")))]),
                    .lit(.ext(.datetime(.init(rawValue: "2024-01-02"))))
                )
            )]
        )

        let response = isAuthorized(
            request: request,
            entities: entities,
            policies: .make([(key: policy.id, value: policy)])
        )

        XCTAssertEqual(response.decision, .allow)
        XCTAssertEqual(response.determining, CedarSet.make([policy.id]))
        XCTAssertEqual(response.erroring, .empty)
    }

    func testDatetimeParseFailureFlowsIntoAuthorizerErroringWithoutChangingDecisionTable() {
        let policy = permitPolicy(
            id: "permit-datetime-error",
            conditions: [Condition(
                kind: .when,
                body: .binaryApp(
                    .lessThan,
                    .call(.datetime, [.lit(.prim(.string("2024-01-01T00:00:60Z")))]),
                    .lit(.ext(.datetime(.init(rawValue: "2024-01-02"))))
                )
            )]
        )

        let response = isAuthorized(
            request: request,
            entities: entities,
            policies: .make([(key: policy.id, value: policy)])
        )

        XCTAssertEqual(response.decision, .deny)
        XCTAssertEqual(response.determining, .empty)
        XCTAssertEqual(response.erroring, CedarSet.make([policy.id]))
    }

    func testDurationPermitConditionAllowsWhenDirectTemporalComparisonSucceeds() {
        let policy = permitPolicy(
            id: "permit-duration-allow",
            conditions: [Condition(
                kind: .when,
                body: .binaryApp(
                    .lessThanOrEqual,
                    .call(.duration, [.lit(.prim(.string("60m")))]),
                    .lit(.ext(.duration(.init(rawValue: "1h"))))
                )
            )]
        )

        let response = isAuthorized(
            request: request,
            entities: entities,
            policies: .make([(key: policy.id, value: policy)])
        )

        XCTAssertEqual(response.decision, .allow)
        XCTAssertEqual(response.determining, CedarSet.make([policy.id]))
        XCTAssertEqual(response.erroring, .empty)
    }

    func testDurationParseFailureFlowsIntoAuthorizerErroringWithoutChangingDecisionTable() {
        let policy = permitPolicy(
            id: "permit-duration-error",
            conditions: [Condition(
                kind: .when,
                body: .binaryApp(
                    .lessThanOrEqual,
                    .call(.duration, [.lit(.prim(.string("PT1H")))]),
                    .lit(.ext(.duration(.init(rawValue: "1h"))))
                )
            )]
        )

        let response = isAuthorized(
            request: request,
            entities: entities,
            policies: .make([(key: policy.id, value: policy)])
        )

        XCTAssertEqual(response.decision, .deny)
        XCTAssertEqual(response.determining, .empty)
        XCTAssertEqual(response.erroring, CedarSet.make([policy.id]))
    }

    func testTraceAuthorizationCapturesSatisfiedUnsatisfiedErroredAndDeterminingPolicies() {
        let satisfiedPermit = permitPolicy(id: "trace-permit")
        let unsatisfiedPermit = permitPolicy(id: "trace-unsatisfied", actionScope: .eq(entity: otherAction))
        let erroredForbid = forbidPolicy(
            id: "trace-error",
            conditions: [Condition(kind: .when, body: .getAttr(.variable(.context), "missing"))]
        )
        let policies: Policies = .make([
            (key: satisfiedPermit.id, value: satisfiedPermit),
            (key: unsatisfiedPermit.id, value: unsatisfiedPermit),
            (key: erroredForbid.id, value: erroredForbid),
        ])

        let trace = traceAuthorization(request: request, entities: entities, policies: policies)

        XCTAssertEqual(trace.response.decision, .allow)
        XCTAssertEqual(trace.matched, CedarSet.make([satisfiedPermit.id]))
        XCTAssertEqual(trace.errors.find(erroredForbid.id), .attrDoesNotExist)
        XCTAssertEqual(Set(trace.satisfied.map(\.policyID)), Set([satisfiedPermit.id]))
        XCTAssertEqual(Set(trace.unsatisfied.map(\.policyID)), Set([unsatisfiedPermit.id]))
        XCTAssertEqual(Set(trace.errored.map(\.policyID)), Set([erroredForbid.id]))
        XCTAssertEqual(Set(trace.determiningEvaluations.map(\.policyID)), Set([satisfiedPermit.id]))
    }

    private func permitPolicy(
        id: PolicyID,
        principalScope: PrincipalScope? = nil,
        actionScope: ActionScope? = nil,
        resourceScope: ResourceScope? = nil,
        conditions: [Condition] = []
    ) -> Policy {
        Policy(
            id: id,
            effect: .permit,
            principalScope: principalScope ?? .eq(entity: principal),
            actionScope: actionScope ?? .eq(entity: action),
            resourceScope: resourceScope ?? .eq(entity: resource),
            conditions: conditions
        )
    }

    private func forbidPolicy(
        id: PolicyID,
        principalScope: PrincipalScope? = nil,
        actionScope: ActionScope? = nil,
        resourceScope: ResourceScope? = nil,
        conditions: [Condition] = []
    ) -> Policy {
        Policy(
            id: id,
            effect: .forbid,
            principalScope: principalScope ?? .eq(entity: principal),
            actionScope: actionScope ?? .eq(entity: action),
            resourceScope: resourceScope ?? .eq(entity: resource),
            conditions: conditions
        )
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
