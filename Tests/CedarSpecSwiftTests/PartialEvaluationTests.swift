import XCTest
@testable import CedarSpecSwift

final class PartialEvaluationTests: XCTestCase {
    private let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
    private let action = EntityUID(ty: Name(id: "Action"), eid: "view")
    private let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
    private let staff = EntityUID(ty: Name(id: "Group"), eid: "staff")
    private let company = EntityUID(ty: Name(id: "Group"), eid: "company")
    private let album = EntityUID(ty: Name(id: "Album"), eid: "vacation")

    private var request: Request {
        Request(
            principal: principal,
            action: action,
            resource: resource,
            context: .record(CedarMap.make([
                (key: "department", value: .string("Engineering")),
            ]))
        )
    }

    private var entities: Entities {
        Entities(CedarMap.make([
            (key: principal, value: EntityData(
                ancestors: CedarSet.make([staff]),
                attrs: CedarMap.make([
                    (key: "department", value: .prim(.string("Engineering"))),
                ])
            )),
            (key: staff, value: EntityData(ancestors: CedarSet.make([company]))),
            (key: company, value: EntityData()),
            (key: album, value: EntityData()),
        ]))
    }

    func testPartialEvaluatePolicySimplifiesKnownScopesAndConditions() {
        let policy = Policy(
            id: "residual-policy",
            effect: .permit,
            principalScope: .in(entity: company),
            actionScope: .eq(entity: action),
            resourceScope: .any,
            conditions: [
                Condition(
                    kind: .when,
                    body: .binaryApp(
                        .equal,
                        .getAttr(.variable(.context), "department"),
                        .lit(.prim(.string("Engineering")))
                    )
                )
            ]
        )

        let residual = unwrapResult(partialEvaluate(
            policy,
            request: request,
            entities: entities,
            unknowns: CedarSet.make([.principal])
        ))

        XCTAssertEqual(residual?.principalScope, .in(entity: company))
        XCTAssertEqual(residual?.actionScope, .any)
        XCTAssertEqual(residual?.conditions, [])
    }

    func testPartialEvaluateDropsUnsatisfiedPolicies() {
        let policy = Policy(
            id: "drop-me",
            effect: .permit,
            principalScope: .any,
            actionScope: .eq(entity: EntityUID(ty: Name(id: "Action"), eid: "delete")),
            resourceScope: .any
        )

        let residual = unwrapResult(partialEvaluate(policy, request: request, entities: entities))

        XCTAssertNil(residual)
    }

    func testSliceEntitiesPreservesConcreteAuthorization() {
        let policy = Policy(
            id: "slice-me",
            effect: .permit,
            principalScope: .in(entity: company),
            actionScope: .any,
            resourceScope: .any,
            conditions: [
                Condition(
                    kind: .when,
                    body: .binaryApp(
                        .equal,
                        .getAttr(.variable(.principal), "department"),
                        .lit(.prim(.string("Engineering")))
                    )
                )
            ]
        )
        let policies: Policies = .make([(key: policy.id, value: policy)])

        let slice = unwrapResult(sliceEntities(for: policies, request: request, entities: entities))
        let full = isAuthorized(request: request, entities: entities, policies: policies)
        let sliced = isAuthorized(request: request, entities: slice.entities, policies: policies)

        XCTAssertEqual(slice.required, CedarSet.make([principal, staff, company]))
        XCTAssertEqual(full, sliced)
    }

    func testSliceEntitiesForPartialEvaluationCombinesKnownAccessesAndResidualRefs() {
        let policy = Policy(
            id: "partial-slice",
            effect: .permit,
            principalScope: .any,
            actionScope: .any,
            resourceScope: .any,
            conditions: [
                Condition(
                    kind: .when,
                    body: .binaryApp(
                        .equal,
                        .getAttr(.variable(.principal), "department"),
                        .lit(.prim(.string("Engineering")))
                    )
                ),
                Condition(
                    kind: .when,
                    body: .binaryApp(
                        .in,
                        .variable(.resource),
                        .lit(.prim(.entityUID(album)))
                    )
                )
            ]
        )

        let slice = unwrapResult(sliceEntitiesForPartialEvaluation(
            of: policy,
            request: request,
            entities: entities,
            unknowns: CedarSet.make([.resource])
        ))
        let manifest = unwrapResult(entityManifestForPartialEvaluation(
            policy,
            request: request,
            entities: entities,
            unknowns: CedarSet.make([.resource])
        ))

        XCTAssertEqual(slice.required, CedarSet.make([principal, album]))
        XCTAssertEqual(manifest, slice.required)
    }

    func testPartialEvaluateCollapsesBooleanConditionalIntoResidualCondition() {
        let expr = Expr.ifThenElse(
            .binaryApp(
                .equal,
                .variable(.principal),
                .lit(.prim(.entityUID(principal)))
            ),
            .lit(.prim(.bool(true))),
            .lit(.prim(.bool(false)))
        )

        let residual = unwrapResult(partialEvaluate(
            expr,
            request: request,
            entities: entities,
            unknowns: CedarSet.make([.principal])
        ))

        XCTAssertEqual(
            residual,
            .binaryApp(
                .equal,
                .variable(.principal),
                .lit(.prim(.entityUID(principal)))
            )
        )
    }

    func testPartialEvaluateTemplateSimplifiesKnownActionAndRoundTripsThroughCedarText() {
        let template = Template(
            id: "template-residual",
            effect: .permit,
            principalScope: PrincipalScopeTemplate(.eq(.slot(.principal))),
            actionScope: .eq(entity: action),
            resourceScope: ResourceScopeTemplate(.in(.slot(.resource))),
            conditions: [
                Condition(
                    kind: .when,
                    body: .binaryApp(
                        .equal,
                        .getAttr(.variable(.context), "department"),
                        .lit(.prim(.string("Engineering")))
                    )
                )
            ]
        )

        let residual = unwrapResult(partialEvaluate(template, request: request, entities: entities))

        XCTAssertEqual(residual?.actionScope, .any)
        XCTAssertEqual(residual?.principalScope, template.principalScope)
        XCTAssertEqual(residual?.resourceScope, template.resourceScope)
        XCTAssertEqual(residual?.conditions, [])

        let emitted = emitCedar(residual!)
        let reparsed = unwrapLoad(loadTemplatesCedar(emitted, source: "residual-template.cedar"))

        XCTAssertEqual(reparsed.find("template-residual"), residual)
    }
}
