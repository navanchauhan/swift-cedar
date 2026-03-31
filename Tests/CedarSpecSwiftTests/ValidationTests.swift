import XCTest
@testable import CedarSpecSwift

final class ValidationTests: XCTestCase {
    func testValidatePoliciesAcceptsLoadedFixturePolicies() {
        let schema = unwrapLoad(loadSchema(LoaderFixtures.schemaJSON))
        let policies = unwrapLoad(loadPolicies(LoaderFixtures.policiesJSON))

        let result = validatePolicies(policies, schema: schema)

        XCTAssertTrue(result.isValid)
        XCTAssertFalse(result.diagnostics.hasErrors)
    }

    func testValidatePoliciesHandlesSelfReferentialEntityHierarchy() {
        let schema = unwrapLoad(loadSchema(LoaderFixtures.schemaJSON))
        let policies = unwrapLoad(loadPolicies(LoaderFixtures.policiesJSON))

        let result = validatePolicies(policies, schema: schema, level: 2)

        XCTAssertTrue(result.isValid)
    }

    func testValidatePoliciesRejectsUnknownContextAttribute() {
        let schema = unwrapLoad(loadSchema(LoaderFixtures.schemaJSON))
        let policy = Policy(
            id: "bad-context-attr",
            effect: .permit,
            principalScope: .any,
            actionScope: .eq(entity: EntityUID(ty: Name(id: "Action"), eid: "view")),
            resourceScope: .any,
            conditions: [
                Condition(
                    kind: .when,
                    body: .binaryApp(
                        .equal,
                        .getAttr(.variable(.context), "missing"),
                        .lit(.prim(.string("Engineering")))
                    )
                )
            ]
        )
        let policies: Policies = .make([(key: policy.id, value: policy)])

        let result = validatePolicies(policies, schema: schema)

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.diagnostics.elements.first?.code, "validation.attrNotFound")
    }

    func testValidatePoliciesRejectsLevelViolations() {
        let schema = Schema(
            entityTypes: CedarMap.make([
                (key: Name(id: "User"), value: Schema.EntityTypeDefinition(
                    name: Name(id: "User"),
                    attributes: CedarMap.make([
                        (key: "manager", value: .required(.entity(Name(id: "Group"))))
                    ])
                )),
                (key: Name(id: "Group"), value: Schema.EntityTypeDefinition(
                    name: Name(id: "Group"),
                    attributes: CedarMap.make([
                        (key: "department", value: .required(.string))
                    ])
                )),
                (key: Name(id: "Photo"), value: Schema.EntityTypeDefinition(name: Name(id: "Photo")))
            ]),
            actions: CedarMap.make([
                (key: EntityUID(ty: Name(id: "Action"), eid: "view"), value: Schema.ActionDefinition(
                    uid: EntityUID(ty: Name(id: "Action"), eid: "view"),
                    principalTypes: CedarSet.make([Name(id: "User")]),
                    resourceTypes: CedarSet.make([Name(id: "Photo")])
                ))
            ])
        )
        let policy = Policy(
            id: "deep-deref",
            effect: .permit,
            principalScope: .any,
            actionScope: .eq(entity: EntityUID(ty: Name(id: "Action"), eid: "view")),
            resourceScope: .any,
            conditions: [
                Condition(
                    kind: .when,
                    body: .binaryApp(
                        .equal,
                        .getAttr(.getAttr(.variable(.principal), "manager"), "department"),
                        .lit(.prim(.string("Engineering")))
                    )
                )
            ]
        )

        let result = validatePolicies(.make([(key: policy.id, value: policy)]), schema: schema, level: 1)

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.diagnostics.elements.first?.code, "validation.levelError")
    }

    func testValidateRequestAcceptsLoadedFixtureRequest() {
        let schema = unwrapLoad(loadSchema(LoaderFixtures.schemaJSON))
        let request = unwrapLoad(loadRequest(LoaderFixtures.requestJSON, schema: schema))

        let result = validateRequest(request, schema: schema)

        XCTAssertTrue(result.isValid)
    }

    func testValidateRequestRejectsContextTypeMismatch() {
        let schema = unwrapLoad(loadSchema(LoaderFixtures.schemaJSON))
        let request = Request(
            principal: EntityUID(ty: Name(id: "User"), eid: "alice"),
            action: EntityUID(ty: Name(id: "Action"), eid: "view"),
            resource: EntityUID(ty: Name(id: "Photo"), eid: "vacation"),
            context: .record(CedarMap.make([
                (key: "department", value: .int(5)),
                (key: "ttl", value: .call(.duration, [.string("1h")]))
            ]))
        )

        let result = validateRequest(request, schema: schema)

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.diagnostics.elements.first?.code, "validation.requestNoMatchingEnvironment")
    }

    func testValidateEntitiesAcceptsLoadedFixtureEntities() {
        let schema = unwrapLoad(loadSchema(LoaderFixtures.schemaJSON))
        let entities = unwrapLoad(loadEntities(LoaderFixtures.entitiesJSON, schema: schema))

        let result = validateEntities(entities, schema: schema)

        XCTAssertTrue(result.isValid)
    }

    func testValidateEntitiesRejectsTypeMismatchAndMissingAction() {
        let schema = unwrapLoad(loadSchema(LoaderFixtures.schemaJSON))
        let entities = Entities(CedarMap.make([
            (key: EntityUID(ty: Name(id: "User"), eid: "alice"), value: EntityData(
                ancestors: CedarSet.make([EntityUID(ty: Name(id: "Group"), eid: "staff")]),
                attrs: CedarMap.make([
                    (key: "department", value: .prim(.int(42)))
                ]),
                tags: CedarMap.make([
                    (key: "active", value: .prim(.bool(true)))
                ])
            )),
            (key: EntityUID(ty: Name(id: "Group"), eid: "staff"), value: EntityData())
        ]))

        let result = validateEntities(entities, schema: schema)

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.diagnostics.elements.first?.code, "validation.entityAttributeTypeMismatch")
        XCTAssertTrue(result.diagnostics.elements.contains(where: { $0.code == "validation.missingActionEntity" }))
    }

    func testValidatePoliciesSupportsStrictAndPermissiveModes() {
        let schema = Schema(
            entityTypes: CedarMap.make([
                (key: Name(id: "User"), value: Schema.EntityTypeDefinition(name: Name(id: "User"))),
                (key: Name(id: "Photo"), value: Schema.EntityTypeDefinition(name: Name(id: "Photo"))),
            ]),
            actions: CedarMap.make([
                (key: EntityUID(ty: Name(id: "Action"), eid: "view"), value: Schema.ActionDefinition(
                    uid: EntityUID(ty: Name(id: "Action"), eid: "view"),
                    principalTypes: CedarSet.make([Name(id: "User")]),
                    resourceTypes: CedarSet.make([Name(id: "Photo")])
                ))
            ])
        )
        let policy = Policy(
            id: "empty-set-mode",
            effect: .permit,
            principalScope: .any,
            actionScope: .any,
            resourceScope: .any,
            conditions: [Condition(kind: .when, body: .unaryApp(.isEmpty, .set([])))]
        )
        let policies: Policies = .make([(key: policy.id, value: policy)])

        let strict = validatePolicies(policies, schema: schema, mode: .strict)
        let permissive = validatePolicies(policies, schema: schema, mode: .permissive)

        XCTAssertFalse(strict.isValid)
        XCTAssertEqual(strict.diagnostics.elements.first?.code, "validation.emptySet")
        XCTAssertTrue(permissive.isValid)
    }

    func testValidatePoliciesFiltersTypecheckingToApplicableActions() {
        let user = Name(id: "User")
        let photo = Name(id: "Photo")
        let view = EntityUID(ty: Name(id: "Action"), eid: "view")
        let delete = EntityUID(ty: Name(id: "Action"), eid: "delete")
        let schema = Schema(
            entityTypes: CedarMap.make([
                (key: user, value: Schema.EntityTypeDefinition(name: user)),
                (key: photo, value: Schema.EntityTypeDefinition(name: photo)),
            ]),
            actions: CedarMap.make([
                (key: view, value: Schema.ActionDefinition(
                    uid: view,
                    principalTypes: CedarSet.make([user]),
                    resourceTypes: CedarSet.make([photo]),
                    context: CedarMap.make([(key: "department", value: .required(.string))])
                )),
                (key: delete, value: Schema.ActionDefinition(
                    uid: delete,
                    principalTypes: CedarSet.make([user]),
                    resourceTypes: CedarSet.make([photo])
                )),
            ])
        )
        let policy = Policy(
            id: "view-context-only",
            effect: .permit,
            principalScope: .any,
            actionScope: .eq(entity: view),
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

        let result = validatePolicies(.make([(key: policy.id, value: policy)]), schema: schema, mode: .strict)

        XCTAssertTrue(result.isValid)
        XCTAssertFalse(result.diagnostics.elements.contains(where: { $0.code == "validation.attrNotFound" }))
    }

    func testValidatePoliciesStrictRejectsMixedEntitySetsWhilePermissiveAllowsEntityUnionLUBs() {
        let user = Name(id: "User")
        let photo = Name(id: "Photo")
        let view = EntityUID(ty: Name(id: "Action"), eid: "view")
        let schema = Schema(
            entityTypes: CedarMap.make([
                (key: user, value: Schema.EntityTypeDefinition(name: user)),
                (key: photo, value: Schema.EntityTypeDefinition(name: photo)),
            ]),
            actions: CedarMap.make([
                (key: view, value: Schema.ActionDefinition(
                    uid: view,
                    principalTypes: CedarSet.make([user]),
                    resourceTypes: CedarSet.make([photo])
                ))
            ])
        )
        let policy = Policy(
            id: "mixed-entity-set",
            effect: .permit,
            principalScope: .any,
            actionScope: .eq(entity: view),
            resourceScope: .any,
            conditions: [Condition(
                kind: .when,
                body: .binaryApp(
                    .contains,
                    .set([
                        .variable(.principal),
                        .variable(.resource),
                    ]),
                    .variable(.principal)
                )
            )]
        )
        let policies: Policies = .make([(key: policy.id, value: policy)])

        let strict = validatePolicies(policies, schema: schema, mode: .strict)
        let permissive = validatePolicies(policies, schema: schema, mode: .permissive)

        XCTAssertFalse(strict.isValid)
        XCTAssertTrue(strict.diagnostics.elements.contains(where: { $0.code == "validation.incompatibleSetTypes" }))
        XCTAssertTrue(permissive.isValid)
    }

    func testValidatePoliciesStrictRejectsDisjointEntityIfBranchesWhilePermissiveAllowsThem() {
        let user = Name(id: "User")
        let photo = Name(id: "Photo")
        let view = EntityUID(ty: Name(id: "Action"), eid: "view")
        let schema = Schema(
            entityTypes: CedarMap.make([
                (key: user, value: Schema.EntityTypeDefinition(name: user)),
                (key: photo, value: Schema.EntityTypeDefinition(name: photo)),
            ]),
            actions: CedarMap.make([
                (key: view, value: Schema.ActionDefinition(
                    uid: view,
                    principalTypes: CedarSet.make([user]),
                    resourceTypes: CedarSet.make([photo])
                ))
            ])
        )
        let policy = Policy(
            id: "mixed-entity-if",
            effect: .permit,
            principalScope: .any,
            actionScope: .eq(entity: view),
            resourceScope: .any,
            conditions: [Condition(
                kind: .when,
                body: .binaryApp(
                    .in,
                    .ifThenElse(
                        .binaryApp(.in, .variable(.resource), .variable(.resource)),
                        .variable(.action),
                        .variable(.resource)
                    ),
                    .lit(.prim(.entityUID(EntityUID(ty: photo, eid: "album"))))
                )
            )]
        )
        let policies: Policies = .make([(key: policy.id, value: policy)])

        XCTAssertFalse(validatePolicies(policies, schema: schema, mode: .strict).isValid)
        XCTAssertTrue(validatePolicies(policies, schema: schema, mode: .permissive).isValid)
    }

    func testValidatePoliciesDetectsImpossibleEntityMembershipUsingSchemaHierarchy() {
        let user = Name(id: "User")
        let team = Name(id: "Team")
        let photo = Name(id: "Photo")
        let view = EntityUID(ty: Name(id: "Action"), eid: "view")
        let schema = Schema(
            entityTypes: CedarMap.make([
                (key: user, value: Schema.EntityTypeDefinition(name: user, memberOfTypes: CedarSet.make([team]))),
                (key: team, value: Schema.EntityTypeDefinition(name: team)),
                (key: photo, value: Schema.EntityTypeDefinition(name: photo)),
            ]),
            actions: CedarMap.make([
                (key: view, value: Schema.ActionDefinition(
                    uid: view,
                    principalTypes: CedarSet.make([user]),
                    resourceTypes: CedarSet.make([photo])
                ))
            ])
        )
        let policy = Policy(
            id: "impossible-resource-membership",
            effect: .permit,
            principalScope: .any,
            actionScope: .eq(entity: view),
            resourceScope: .any,
            conditions: [Condition(
                kind: .when,
                body: .binaryApp(.in, .variable(.resource), .lit(.prim(.entityUID(EntityUID(ty: team, eid: "eng")))))
            )]
        )

        let result = validatePolicies(.make([(key: policy.id, value: policy)]), schema: schema, mode: .strict)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.diagnostics.elements.contains(where: { $0.code == "validation.impossiblePolicy" }))
    }

    func testValidatePoliciesRejectsImpossibleScopedPrincipalAndResourceMembership() {
        let container = Name(id: "Container")
        let member = Name(id: "Member")
        let other = Name(id: "Other")
        let view = EntityUID(ty: Name(id: "Action"), eid: "view")
        let schema = Schema(
            entityTypes: CedarMap.make([
                (key: container, value: Schema.EntityTypeDefinition(name: container)),
                (key: member, value: Schema.EntityTypeDefinition(name: member)),
                (key: other, value: Schema.EntityTypeDefinition(name: other)),
            ]),
            actions: CedarMap.make([
                (key: view, value: Schema.ActionDefinition(
                    uid: view,
                    principalTypes: CedarSet.make([member]),
                    resourceTypes: CedarSet.make([other])
                ))
            ])
        )
        let policy = Policy(
            id: "impossible-scoped-membership",
            effect: .forbid,
            principalScope: .isEntityTypeIn(entityType: member, entity: EntityUID(ty: container, eid: "group")),
            actionScope: .eq(entity: view),
            resourceScope: .isEntityTypeIn(entityType: other, entity: EntityUID(ty: container, eid: "group")),
            conditions: [Condition(kind: .when, body: .lit(.prim(.bool(true))))]
        )

        let result = validatePolicies(.make([(key: policy.id, value: policy)]), schema: schema, mode: .strict)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.diagnostics.elements.contains(where: { $0.code == "validation.actionNotApplicable" }))
    }

    func testValidateEntitiesAllowsTransitiveAncestorTypes() {
        let user = Name(id: "User")
        let team = Name(id: "Team")
        let org = Name(id: "Org")
        let schema = Schema(entityTypes: CedarMap.make([
            (key: user, value: Schema.EntityTypeDefinition(name: user, memberOfTypes: CedarSet.make([team]))),
            (key: team, value: Schema.EntityTypeDefinition(name: team, memberOfTypes: CedarSet.make([org]))),
            (key: org, value: Schema.EntityTypeDefinition(name: org)),
        ]))
        let entities = Entities(CedarMap.make([
            (key: EntityUID(ty: user, eid: "alice"), value: EntityData(
                ancestors: CedarSet.make([
                    EntityUID(ty: team, eid: "eng"),
                    EntityUID(ty: org, eid: "company"),
                ])
            )),
            (key: EntityUID(ty: team, eid: "eng"), value: EntityData(ancestors: CedarSet.make([
                EntityUID(ty: org, eid: "company"),
            ]))),
            (key: EntityUID(ty: org, eid: "company"), value: EntityData()),
        ]))

        let result = validateEntities(entities, schema: schema)

        XCTAssertTrue(result.isValid)
    }

    func testValidateEntitiesAllowsActionAncestorClosure() {
        let view = EntityUID(ty: Name(id: "Action"), eid: "view")
        let write = EntityUID(ty: Name(id: "Action"), eid: "write")
        let all = EntityUID(ty: Name(id: "Action"), eid: "all")
        let schema = Schema(actions: CedarMap.make([
            (key: view, value: Schema.ActionDefinition(uid: view, memberOf: CedarSet.make([write, all]))),
            (key: write, value: Schema.ActionDefinition(uid: write, memberOf: CedarSet.make([all]))),
            (key: all, value: Schema.ActionDefinition(uid: all)),
        ]))
        let entities = Entities(CedarMap.make([
            (key: view, value: EntityData(ancestors: CedarSet.make([write, all]))),
            (key: write, value: EntityData(ancestors: CedarSet.make([all]))),
            (key: all, value: EntityData()),
        ]))

        let result = validateEntities(entities, schema: schema)

        XCTAssertTrue(result.isValid)
    }

    func testValidatePoliciesRequiresHasGuardsForOptionalContextAndEntityAttributes() {
        let user = Name(id: "User")
        let photo = Name(id: "Photo")
        let view = EntityUID(ty: Name(id: "Action"), eid: "view")
        let schema = Schema(
            entityTypes: CedarMap.make([
                (key: user, value: Schema.EntityTypeDefinition(name: user, attributes: CedarMap.make([
                    (key: "nickname", value: .optional(.string))
                ]))),
                (key: photo, value: Schema.EntityTypeDefinition(name: photo)),
            ]),
            actions: CedarMap.make([
                (key: view, value: Schema.ActionDefinition(
                    uid: view,
                    principalTypes: CedarSet.make([user]),
                    resourceTypes: CedarSet.make([photo]),
                    context: CedarMap.make([
                        (key: "department", value: .optional(.string))
                    ])
                ))
            ])
        )
        let policy = Policy(
            id: "unsafe-optional-access",
            effect: .permit,
            principalScope: .any,
            actionScope: .eq(entity: view),
            resourceScope: .any,
            conditions: [Condition(
                kind: .when,
                body: .binaryApp(
                    .and,
                    .binaryApp(
                        .equal,
                        .getAttr(.variable(.context), "department"),
                        .lit(.prim(.string("Engineering")))
                    ),
                    .binaryApp(
                        .equal,
                        .getAttr(.variable(.principal), "nickname"),
                        .lit(.prim(.string("ally")))
                    )
                )
            )]
        )

        let result = validatePolicies(.make([(key: policy.id, value: policy)]), schema: schema)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.diagnostics.elements.contains(where: { $0.code == "validation.unsafeOptionalAttributeAccess" }))
    }

    func testValidatePoliciesAllowsOptionalAttributeAccessBehindMatchingHasGuards() {
        let user = Name(id: "User")
        let photo = Name(id: "Photo")
        let view = EntityUID(ty: Name(id: "Action"), eid: "view")
        let schema = Schema(
            entityTypes: CedarMap.make([
                (key: user, value: Schema.EntityTypeDefinition(name: user, attributes: CedarMap.make([
                    (key: "nickname", value: .optional(.string))
                ]))),
                (key: photo, value: Schema.EntityTypeDefinition(name: photo)),
            ]),
            actions: CedarMap.make([
                (key: view, value: Schema.ActionDefinition(
                    uid: view,
                    principalTypes: CedarSet.make([user]),
                    resourceTypes: CedarSet.make([photo]),
                    context: CedarMap.make([
                        (key: "department", value: .optional(.string))
                    ])
                ))
            ])
        )
        let policy = Policy(
            id: "guarded-optional-access",
            effect: .permit,
            principalScope: .any,
            actionScope: .eq(entity: view),
            resourceScope: .any,
            conditions: [Condition(
                kind: .when,
                body: .binaryApp(
                    .and,
                    .hasAttr(.variable(.context), "department"),
                    .binaryApp(
                        .and,
                        .hasAttr(.variable(.principal), "nickname"),
                        .binaryApp(
                            .equal,
                            .getAttr(.variable(.principal), "nickname"),
                            .getAttr(.variable(.context), "department")
                        )
                    )
                )
            )]
        )

        let result = validatePolicies(.make([(key: policy.id, value: policy)]), schema: schema)

        XCTAssertTrue(result.isValid)
    }

    func testValidatePoliciesStrictRequiresLiteralExtensionConstructorArguments() {
        let user = Name(id: "User")
        let photo = Name(id: "Photo")
        let view = EntityUID(ty: Name(id: "Action"), eid: "view")
        let schema = Schema(
            entityTypes: CedarMap.make([
                (key: user, value: Schema.EntityTypeDefinition(name: user)),
                (key: photo, value: Schema.EntityTypeDefinition(name: photo)),
            ]),
            actions: CedarMap.make([
                (key: view, value: Schema.ActionDefinition(
                    uid: view,
                    principalTypes: CedarSet.make([user]),
                    resourceTypes: CedarSet.make([photo])
                ))
            ])
        )
        let constructorExpr = Expr.call(.decimal, [
            .ifThenElse(
                .lit(.prim(.bool(false))),
                .lit(.prim(.string("1.0"))),
                .lit(.prim(.string("1.0")))
            )
        ])
        let policy = Policy(
            id: "nonliteral-constructor",
            effect: .permit,
            principalScope: .any,
            actionScope: .eq(entity: view),
            resourceScope: .any,
            conditions: [Condition(
                kind: .when,
                body: .binaryApp(.equal, constructorExpr, constructorExpr)
            )]
        )
        let policies: Policies = .make([(key: policy.id, value: policy)])

        XCTAssertFalse(validatePolicies(policies, schema: schema, mode: .strict).isValid)
        XCTAssertTrue(validatePolicies(policies, schema: schema, mode: .permissive).isValid)
    }

    func testValidatePoliciesAllowsInvalidConstructorLiteralInDeadBranch() {
        let user = Name(id: "User")
        let photo = Name(id: "Photo")
        let view = EntityUID(ty: Name(id: "Action"), eid: "view")
        let schema = Schema(
            entityTypes: CedarMap.make([
                (key: user, value: Schema.EntityTypeDefinition(name: user)),
                (key: photo, value: Schema.EntityTypeDefinition(name: photo)),
            ]),
            actions: CedarMap.make([
                (key: view, value: Schema.ActionDefinition(
                    uid: view,
                    principalTypes: CedarSet.make([user]),
                    resourceTypes: CedarSet.make([photo])
                ))
            ])
        )
        let policy = Policy(
            id: "dead-invalid-constructor",
            effect: .permit,
            principalScope: .any,
            actionScope: .eq(entity: view),
            resourceScope: .any,
            conditions: [Condition(
                kind: .when,
                body: .binaryApp(
                    .and,
                    .lit(.prim(.bool(false))),
                    .call(.isIpv4, [
                        .ifThenElse(
                            .lit(.prim(.bool(false))),
                            .call(.ip, [.lit(.prim(.string("116699..45.214.32/4")))]),
                            .call(.ip, [.lit(.prim(.string("0.0.0.0")))])
                        )
                    ])
                )
            )]
        )

        let result = validatePolicies(.make([(key: policy.id, value: policy)]), schema: schema, mode: .strict)

        XCTAssertTrue(result.isValid)
    }

    func testValidatePoliciesRequiresHasTagBeforeGetTag() {
        let user = Name(id: "User")
        let photo = Name(id: "Photo")
        let view = EntityUID(ty: Name(id: "Action"), eid: "view")
        let schema = Schema(
            entityTypes: CedarMap.make([
                (key: user, value: Schema.EntityTypeDefinition(name: user, tags: .string)),
                (key: photo, value: Schema.EntityTypeDefinition(name: photo)),
            ]),
            actions: CedarMap.make([
                (key: view, value: Schema.ActionDefinition(
                    uid: view,
                    principalTypes: CedarSet.make([user]),
                    resourceTypes: CedarSet.make([photo])
                ))
            ])
        )
        let policy = Policy(
            id: "unsafe-tag-access",
            effect: .permit,
            principalScope: .any,
            actionScope: .eq(entity: view),
            resourceScope: .any,
            conditions: [Condition(
                kind: .when,
                body: .binaryApp(
                    .equal,
                    .binaryApp(.getTag, .variable(.principal), .lit(.prim(.string("role")))),
                    .lit(.prim(.string("admin")))
                )
            )]
        )

        let result = validatePolicies(.make([(key: policy.id, value: policy)]), schema: schema)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.diagnostics.elements.contains(where: { $0.code == "validation.unsafeTagAccess" }))
    }

    func testValidatePoliciesAllowsGuardedGetTagAndTreatsHasTagWithoutSchemaTagsAsImpossible() {
        let user = Name(id: "User")
        let photo = Name(id: "Photo")
        let view = EntityUID(ty: Name(id: "Action"), eid: "view")
        let taggedSchema = Schema(
            entityTypes: CedarMap.make([
                (key: user, value: Schema.EntityTypeDefinition(name: user, tags: .string)),
                (key: photo, value: Schema.EntityTypeDefinition(name: photo)),
            ]),
            actions: CedarMap.make([
                (key: view, value: Schema.ActionDefinition(
                    uid: view,
                    principalTypes: CedarSet.make([user]),
                    resourceTypes: CedarSet.make([photo])
                ))
            ])
        )
        let guardedPolicy = Policy(
            id: "guarded-tag-access",
            effect: .permit,
            principalScope: .any,
            actionScope: .eq(entity: view),
            resourceScope: .any,
            conditions: [Condition(
                kind: .when,
                body: .binaryApp(
                    .and,
                    .binaryApp(.hasTag, .variable(.principal), .lit(.prim(.string("role")))),
                    .binaryApp(
                        .equal,
                        .binaryApp(.getTag, .variable(.principal), .lit(.prim(.string("role")))),
                        .lit(.prim(.string("admin")))
                    )
                )
            )]
        )

        let guardedResult = validatePolicies(.make([(key: guardedPolicy.id, value: guardedPolicy)]), schema: taggedSchema)

        XCTAssertTrue(guardedResult.isValid)

        let untaggedSchema = Schema(
            entityTypes: CedarMap.make([
                (key: user, value: Schema.EntityTypeDefinition(name: user)),
                (key: photo, value: Schema.EntityTypeDefinition(name: photo)),
            ]),
            actions: CedarMap.make([
                (key: view, value: Schema.ActionDefinition(
                    uid: view,
                    principalTypes: CedarSet.make([user]),
                    resourceTypes: CedarSet.make([photo])
                ))
            ])
        )
        let impossiblePolicy = Policy(
            id: "has-tag-without-tags",
            effect: .permit,
            principalScope: .any,
            actionScope: .eq(entity: view),
            resourceScope: .any,
            conditions: [Condition(kind: .when, body: .binaryApp(.hasTag, .variable(.principal), .lit(.prim(.string("role")))))]
        )

        let impossibleResult = validatePolicies(.make([(key: impossiblePolicy.id, value: impossiblePolicy)]), schema: untaggedSchema)

        XCTAssertFalse(impossibleResult.isValid)
        XCTAssertTrue(impossibleResult.diagnostics.elements.contains(where: { $0.code == "validation.impossiblePolicy" }))
        XCTAssertFalse(impossibleResult.diagnostics.elements.contains(where: { $0.code == "validation.tagNotFound" }))
    }

    func testValidatePoliciesReportsIncompatibleTagTypesAcrossEntityUnions() {
        let typeA = Name(id: "TypeA")
        let typeB = Name(id: "TypeB")
        let view = EntityUID(ty: Name(id: "Action"), eid: "view")
        let schema = Schema(
            entityTypes: CedarMap.make([
                (key: typeA, value: Schema.EntityTypeDefinition(name: typeA, tags: .string)),
                (key: typeB, value: Schema.EntityTypeDefinition(name: typeB, tags: .int)),
            ]),
            actions: CedarMap.make([
                (key: view, value: Schema.ActionDefinition(
                    uid: view,
                    principalTypes: CedarSet.make([typeA]),
                    resourceTypes: CedarSet.make([typeB]),
                    context: CedarMap.make([
                        (key: "flag", value: .required(.bool))
                    ])
                ))
            ])
        )
        let unionExpr = Expr.ifThenElse(
            .getAttr(.variable(.context), "flag"),
            .variable(.principal),
            .variable(.resource)
        )
        let policy = Policy(
            id: "incompatible-tag-lub",
            effect: .permit,
            principalScope: .any,
            actionScope: .eq(entity: view),
            resourceScope: .any,
            conditions: [Condition(
                kind: .when,
                body: .binaryApp(
                    .equal,
                    .binaryApp(.getTag, unionExpr, .lit(.prim(.string("role")))),
                    .lit(.prim(.string("admin")))
                )
            )]
        )

        let result = validatePolicies(.make([(key: policy.id, value: policy)]), schema: schema)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.diagnostics.elements.contains(where: { $0.code == "validation.incompatibleTagTypes" }))
    }

    func testValidatePoliciesTypesDatetimeToTimeAsDuration() {
        let user = Name(id: "User")
        let photo = Name(id: "Photo")
        let view = EntityUID(ty: Name(id: "Action"), eid: "view")
        let schema = Schema(
            entityTypes: CedarMap.make([
                (key: user, value: Schema.EntityTypeDefinition(name: user)),
                (key: photo, value: Schema.EntityTypeDefinition(name: photo)),
            ]),
            actions: CedarMap.make([
                (key: view, value: Schema.ActionDefinition(
                    uid: view,
                    principalTypes: CedarSet.make([user]),
                    resourceTypes: CedarSet.make([photo])
                ))
            ])
        )
        let policy = Policy(
            id: "datetime-to-time",
            effect: .permit,
            principalScope: .any,
            actionScope: .eq(entity: view),
            resourceScope: .any,
            conditions: [Condition(
                kind: .when,
                body: .binaryApp(
                    .equal,
                    .call(.toDays, [
                        .call(.toTime, [
                            .call(.datetime, [
                                .lit(.prim(.string("0000-01-01")))
                            ])
                        ])
                    ]),
                    .lit(.prim(.int(0)))
                )
            )]
        )

        let result = validatePolicies(.make([(key: policy.id, value: policy)]), schema: schema, mode: .permissive)

        XCTAssertTrue(result.isValid)
    }

    func testValidateRequestAcceptsDescendantPrincipalAndResourceTypes() {
        let principal = Name(id: "Principal")
        let user = Name(id: "User")
        let asset = Name(id: "Asset")
        let photo = Name(id: "Photo")
        let view = EntityUID(ty: Name(id: "Action"), eid: "view")
        let schema = Schema(
            entityTypes: CedarMap.make([
                (key: principal, value: Schema.EntityTypeDefinition(name: principal)),
                (key: user, value: Schema.EntityTypeDefinition(name: user, memberOfTypes: CedarSet.make([principal]))),
                (key: asset, value: Schema.EntityTypeDefinition(name: asset)),
                (key: photo, value: Schema.EntityTypeDefinition(name: photo, memberOfTypes: CedarSet.make([asset]))),
            ]),
            actions: CedarMap.make([
                (key: view, value: Schema.ActionDefinition(
                    uid: view,
                    principalTypes: CedarSet.make([principal]),
                    resourceTypes: CedarSet.make([asset])
                ))
            ])
        )
        let request = Request(
            principal: EntityUID(ty: user, eid: "alice"),
            action: view,
            resource: EntityUID(ty: photo, eid: "vacation")
        )

        let result = validateRequest(request, schema: schema)

        XCTAssertTrue(result.isValid)
    }
}
