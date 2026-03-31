import XCTest
import CedarSpecSwift

final class PublicAPITests: XCTestCase {
    func testSliceB1PublicSurfaceCompilesWithPlainImport() throws {
        XCTAssertEqual(CedarInt64.add(20, 22), 42)

        let name = Name(id: "User", path: ["App"])
        let uid = EntityUID(ty: name, eid: "alice")
        let prim = Prim.entityUID(uid)
        let ext = Ext.decimal(.init(rawValue: "1.23"))
        let record = CedarValue.record(CedarMap.make([
            (key: "department", value: .prim(.string("Engineering"))),
            (key: "level", value: .prim(.int(5))),
        ]))
        let values = CedarSet.make([
            CedarValue.prim(prim),
            CedarValue.ext(ext),
            record,
        ])
        let result: CedarResult<CedarValue> = .success(record)
        let error = CedarError.typeError

        XCTAssertEqual(name.description, "App::User")
        XCTAssertEqual(uid.description, "App::User::\"alice\"")
        XCTAssertEqual(values.elements.count, 3)
        XCTAssertEqual(try result.get(), record)
        XCTAssertEqual(error, .typeError)
        XCTAssertTrue(ExtFun.allCases.contains(.decimal))
    }

    func testValidationPublicSurfaceCompilesWithPlainImport() {
        let schema = unwrapLoad(loadSchema(LoaderFixtures.schemaJSON))
        let policies = unwrapLoad(loadPolicies(LoaderFixtures.policiesJSON))
        let request = unwrapLoad(loadRequest(LoaderFixtures.requestJSON, schema: schema))
        let entities = unwrapLoad(loadEntities(LoaderFixtures.entitiesJSON, schema: schema))

        let policyResult = validatePolicies(policies, schema: schema, level: 2)
        let requestResult = validateRequest(request, schema: schema)
        let entityResult = validateEntities(entities, schema: schema)

        XCTAssertTrue(policyResult.isValid)
        XCTAssertTrue(requestResult.isValid)
        XCTAssertTrue(entityResult.isValid)
    }

    func testResidualAndSlicingPublicSurfaceCompilesWithPlainImport() {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(
            principal: principal,
            action: action,
            resource: resource,
            context: .record(CedarMap.make([(key: "department", value: .string("Engineering"))]))
        )
        let policy = Policy(
            id: "public-residual",
            effect: .permit,
            principalScope: .any,
            actionScope: .eq(entity: action),
            resourceScope: .any,
            conditions: [Condition(
                kind: .when,
                body: .binaryApp(
                    .equal,
                    .getAttr(.variable(.context), "department"),
                    .lit(.prim(.string("Engineering")))
                )
            )]
        )
        let policies: Policies = .make([(key: policy.id, value: policy)])
        let entities = Entities()

        let policyValidation = validatePolicies(policies, schema: Schema(), mode: .permissive)
        let residual = partialEvaluate(policy, request: request, entities: entities, unknowns: CedarSet.make([.principal]))
        let slice = sliceEntitiesForPartialEvaluation(of: policies, request: request, entities: entities, unknowns: CedarSet.make([.principal]))
        let manifest = entityManifestForPartialEvaluation(policy, request: request, entities: entities, unknowns: CedarSet.make([.principal]))

        XCTAssertFalse(policyValidation.isValid)
        XCTAssertNotNil(try? residual.get())
        XCTAssertNotNil(try? slice.get())
        XCTAssertNotNil(try? manifest.get())
    }

    func testSliceB1bPublicSurfaceUsesScalarStrictStringSemantics() {
        let composed = "\u{00E9}"
        let decomposed = "e\u{0301}"

        let composedName = Name(id: composed)
        let decomposedName = Name(id: decomposed)
        let composedUID = EntityUID(ty: Name(id: "User"), eid: composed)
        let decomposedUID = EntityUID(ty: Name(id: "User"), eid: decomposed)
        let record = CedarValue.record(CedarMap.make([
            (key: composed, value: .prim(.string("composed"))),
            (key: decomposed, value: .prim(.string("decomposed"))),
        ]))

        XCTAssertNotEqual(composedName, decomposedName)
        XCTAssertLessThan(decomposedName, composedName)
        XCTAssertNotEqual(composedUID, decomposedUID)
        XCTAssertLessThan(decomposedUID, composedUID)

        guard case let .record(map) = record else {
            return XCTFail("Expected record value")
        }

        XCTAssertEqual(map.entries.map(\.key), [decomposed, composed])
    }

    func testSliceB2PublicSurfaceCompilesWithPlainImport() {
        let a = Array("a".unicodeScalars)[0]
        let z = Array("z".unicodeScalars)[0]
        let pattern = Pattern([.literal(a), .wildcard, .literal(z)])
        let literal = Expr.lit(.prim(.string("abz")))
        let variable = Expr.variable(.context)
        let unary = Expr.unaryApp(.not, .lit(.prim(.bool(false))))
        let isEmpty = Expr.unaryApp(.isEmpty, .set([]))
        let binary = Expr.binaryApp(.containsAny, .set([literal]), .set([literal]))
        let conditional = Expr.ifThenElse(unary, literal, variable)
        let record = Expr.record([
            (key: "department", value: Expr.getAttr(variable, "department")),
            (key: "match", value: Expr.like(literal, pattern)),
        ])
        let call = Expr.call(.decimal, [literal])

        XCTAssertTrue(wildcardMatch(pattern, value: Array("abz".unicodeScalars)))
        XCTAssertTrue(Var.allCases.contains(.principal))
        XCTAssertTrue(UnaryOp.allCases.contains(.not))
        XCTAssertTrue(UnaryOp.allCases.contains(.isEmpty))
        XCTAssertTrue(BinaryOp.allCases.contains(.containsAny))
        XCTAssertLessThan(Expr.variable(.principal), Expr.unaryApp(.not, literal))
        XCTAssertNotEqual(binary, conditional)
        XCTAssertNotEqual(record, call)
        XCTAssertEqual(isEmpty, Expr.unaryApp(.isEmpty, .set([])))
    }

    func testCoreUnaryIsEmptyPublicEvaluateSurface() throws {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let emptySetExpr = Expr.unaryApp(.isEmpty, .set([]))
        let recordExpr = Expr.unaryApp(.isEmpty, .record([]))

        XCTAssertEqual(
            try evaluate(emptySetExpr, request: request, entities: Entities()).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            failure(of: evaluate(recordExpr, request: request, entities: Entities())),
            .typeError
        )
    }

    func testSliceB3PublicSurfaceCompilesWithPlainImport() throws {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(
            principal: principal,
            action: action,
            resource: resource,
            context: .record(CedarMap.make([
                (key: "department", value: .string("Engineering")),
            ]))
        )
        let context: RestrictedExpr = request.context
        let entityData = EntityData(
            ancestors: CedarSet.make([EntityUID(ty: Name(id: "Group"), eid: "staff")]),
            attrs: CedarMap.make([
                (key: "title", value: .prim(.string("Engineer"))),
            ]),
            tags: CedarMap.make([
                (key: "active", value: .prim(.bool(true))),
            ])
        )
        let entities = Entities(CedarMap.make([
            (key: principal, value: entityData),
        ]))

        XCTAssertEqual(request.principal, principal)
        XCTAssertEqual(context, .record(CedarMap.make([(key: "department", value: .string("Engineering"))])))
        XCTAssertEqual(try entities.ancestors(principal).get(), entityData.ancestors)
        XCTAssertEqual(try entities.attrs(principal).get(), entityData.attrs)
        XCTAssertEqual(try entities.tags(principal).get(), entityData.tags)
        XCTAssertEqual(entities.attrsOrEmpty(resource), .empty)
        XCTAssertEqual(entities.tagsOrEmpty(resource), .empty)
    }

    func testRequestPublicInitializerUsesRestrictedExprContext() throws {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(
            principal: principal,
            action: action,
            resource: resource,
            context: .record(CedarMap.make([
                (key: "ttl", value: .call(.duration, [.string("1h")])),
            ]))
        )
        let context: RestrictedExpr = request.context

        XCTAssertEqual(context, .record(CedarMap.make([(key: "ttl", value: .call(.duration, [.string("1h")]))])))
        XCTAssertEqual(
            try evaluate(.variable(.context), request: request, entities: Entities()).get(),
            .record(CedarMap.make([(key: "ttl", value: .ext(.duration(.init(rawValue: "1h"))))]))
        )
    }

    func testRequestPublicInitializerDefaultsToEmptyRestrictedRecord() throws {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let context: RestrictedExpr = request.context

        XCTAssertEqual(context, .emptyRecord)
        XCTAssertEqual(
            try evaluate(.variable(.context), request: request, entities: Entities()).get(),
            .record(.empty)
        )
    }

    func testSliceB4PublicSurfaceCompilesWithPlainImport() {
        let userType = Name(id: "User")
        let actionType = Name(id: "Action")
        let photoType = Name(id: "Photo")
        let principal = EntityUID(ty: userType, eid: "alice")
        let readAction = EntityUID(ty: actionType, eid: "read")
        let writeAction = EntityUID(ty: actionType, eid: "write")
        let resource = EntityUID(ty: photoType, eid: "vacation")
        let condition = Condition(
            kind: .when,
            body: .binaryApp(.equal, .variable(.principal), .lit(.prim(.entityUID(principal))))
        )
        let policy = Policy(
            id: "permit-read",
            effect: .permit,
            principalScope: .eq(entity: principal),
            actionScope: .actionInAny(entities: CedarSet.make([writeAction, readAction])),
            resourceScope: .eq(entity: resource),
            conditions: [condition, Condition(kind: .unless, body: .lit(.prim(.bool(false))))]
        )
        let policies: Policies = .make([
            (key: policy.id, value: policy),
        ])

        XCTAssertLessThan(Effect.permit, .forbid)
        XCTAssertLessThan(ConditionKind.when, .unless)
        XCTAssertEqual(policy.conditions.count, 2)
        XCTAssertEqual(
            policy.toExpr(),
            .binaryApp(
                .and,
                .binaryApp(.equal, .variable(.principal), .lit(.prim(.entityUID(principal)))),
                .binaryApp(
                    .and,
                    .binaryApp(
                        .in,
                        .variable(.action),
                        .set([
                            .lit(.prim(.entityUID(readAction))),
                            .lit(.prim(.entityUID(writeAction))),
                        ])
                    ),
                    .binaryApp(
                        .and,
                        .binaryApp(.equal, .variable(.resource), .lit(.prim(.entityUID(resource)))),
                        .binaryApp(
                            .and,
                            .binaryApp(.equal, .variable(.principal), .lit(.prim(.entityUID(principal)))),
                            .unaryApp(.not, .lit(.prim(.bool(false))))
                        )
                    )
                )
            )
        )
        XCTAssertEqual(policies.find("permit-read"), policy)
    }

    func testSliceC2aPublicSurfaceCompilesWithPlainImport() {
        let response = Response(
            decision: .allow,
            determining: CedarSet.make(["policy-b", "policy-a"]),
            erroring: CedarSet.make(["policy-error"])
        )

        XCTAssertLessThan(Decision.allow, .deny)
        XCTAssertEqual(response.decision, .allow)
        XCTAssertEqual(response.determining.elements, ["policy-a", "policy-b"])
        XCTAssertEqual(response.erroring.elements, ["policy-error"])
    }

    func testSliceTextFrontendPublicSurfaceCompilesWithPlainImport() {
        let policies = loadPoliciesCedar(#"""
@id("policy-a")
permit (
    principal,
    action,
    resource
)
when { true };
"""#)
        let templates = loadTemplatesCedar(#"""
@id("template-a")
permit (
    principal == ?principal,
    action,
    resource == ?resource
);
"""#)

        let parsedPolicies = unwrapLoad(policies)
        let parsedTemplates = unwrapLoad(templates)
        let policyText = emitCedar(parsedPolicies)
        let templateText = emitCedar(parsedTemplates)
        let exprText = emitCedar(.binaryApp(.and, .lit(.prim(.bool(true))), .lit(.prim(.bool(false)))))

        XCTAssertTrue(policyText.contains("permit"))
        XCTAssertTrue(templateText.contains("?principal"))
        XCTAssertEqual(exprText, "true && false")
    }

    func testCompiledAuthorizationPublicSurfaceCompilesWithPlainImport() {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let loaded = unwrapLoad(loadPoliciesCedar(#"""
@id("compiled-policy")
permit (
    principal == User::"alice",
    action == Action::"view",
    resource == Photo::"vacation"
);
"""#, compiling: true))
        let compiled = loaded.compiledPolicies ?? CompiledPolicies(loaded.policies)
        let response = isAuthorizedCompiled(request: request, entities: Entities(), compiledPolicies: compiled)
        let cachedResponse = isAuthorizedCompiled(request: request, entities: Entities(), policies: loaded.policies)

        XCTAssertEqual(compiled.permits.count, 1)
        XCTAssertTrue(compiled.forbids.isEmpty)
        XCTAssertEqual(response.decision, .allow)
        XCTAssertEqual(cachedResponse, response)
        XCTAssertEqual(response.determining, CedarSet.make(["compiled-policy"]))
    }

    func testSliceC1aPublicSurfaceExposesEvaluationLimitError() {
        let error = CedarError.evaluationLimitError

        XCTAssertEqual(error, .evaluationLimitError)
        XCTAssertNotEqual(error, .extensionError)
    }

    func testSliceC1bPublicEvaluateSupportsPureAndEntitySensitiveExpressions() throws {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let staff = EntityUID(ty: Name(id: "Group"), eid: "staff")
        let company = EntityUID(ty: Name(id: "Group"), eid: "company")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let entities = Entities(CedarMap.make([
            (key: principal, value: EntityData(
                ancestors: CedarSet.make([staff]),
                attrs: CedarMap.make([
                    (key: "department", value: .prim(.string("Engineering"))),
                ])
            )),
            (key: staff, value: EntityData(ancestors: CedarSet.make([company]))),
            (key: company, value: EntityData()),
            (key: action, value: EntityData()),
            (key: resource, value: EntityData()),
        ]))

        XCTAssertEqual(
            try evaluate(
                .binaryApp(.add, .lit(.prim(.int(20))), .lit(.prim(.int(22)))),
                request: request,
                entities: entities
            ).get(),
            .prim(.int(42))
        )
        XCTAssertEqual(
            try evaluate(.getAttr(.variable(.principal), "department"), request: request, entities: entities).get(),
            .prim(.string("Engineering"))
        )
        XCTAssertEqual(
            try evaluate(
                .binaryApp(.in, .variable(.principal), .lit(.prim(.entityUID(company)))),
                request: request,
                entities: entities
            ).get(),
            .prim(.bool(true))
        )
    }

    func testSliceC1bPublicEvaluateExposesBlackBoxErrorContracts() {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let missing = EntityUID(ty: Name(id: "User"), eid: "missing")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let entities = Entities(CedarMap.make([
            (key: principal, value: EntityData(tags: CedarMap.make([
                (key: "active", value: .prim(.bool(true))),
            ]))),
            (key: action, value: EntityData()),
            (key: resource, value: EntityData()),
        ]))

        XCTAssertEqual(
            failure(of: evaluate(.getAttr(.lit(.prim(.entityUID(missing))), "department"), request: request, entities: entities)),
            .entityDoesNotExist
        )
        XCTAssertEqual(
            failure(of: evaluate(.getAttr(.variable(.context), "department"), request: request, entities: entities)),
            .attrDoesNotExist
        )
        XCTAssertEqual(
            failure(of: evaluate(
                .binaryApp(.getTag, .variable(.principal), .lit(.prim(.string("missing")))),
                request: request,
                entities: entities
            )),
            .tagDoesNotExist
        )
        XCTAssertEqual(
            failure(of: evaluate(.call(.decimal, [.lit(.prim(.string("1.23456")))]), request: request, entities: entities)),
            .extensionError
        )
    }

    func testSliceC1bRepairPublicEvaluateSupportsExtensionSetMembership() throws {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let entities = Entities(CedarMap.make([
            (key: principal, value: EntityData()),
            (key: action, value: EntityData()),
            (key: resource, value: EntityData()),
        ]))

        XCTAssertEqual(
            try evaluate(
                .binaryApp(
                    .contains,
                    .set([
                        .lit(.ext(.decimal(.init(rawValue: "1.2300")))),
                        .lit(.ext(.ipaddr(.init(rawValue: "127.0.0.1/32")))),
                    ]),
                    .lit(.ext(.decimal(.init(rawValue: "1.23"))))
                ),
                request: request,
                entities: entities
            ).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            try evaluate(
                .binaryApp(
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
                entities: entities
            ).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            try evaluate(
                .binaryApp(
                    .containsAny,
                    .set([
                        .lit(.ext(.duration(.init(rawValue: "1h")))),
                    ]),
                    .set([
                        .lit(.ext(.duration(.init(rawValue: "60m")))),
                    ])
                ),
                request: request,
                entities: entities
            ).get(),
            .prim(.bool(true))
        )
    }

    func testSliceC1bRepairPublicEvaluateMapsUnsupportedDirectGenericExtensionComparisonsToTypeError() {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let entities = Entities()

        XCTAssertEqual(
            failure(of: evaluate(
                .binaryApp(
                    .lessThan,
                    .lit(.ext(.decimal(.init(rawValue: "1.23")))),
                    .lit(.ext(.decimal(.init(rawValue: "1.23"))))
                ),
                request: request,
                entities: entities
            )),
            .typeError
        )
        XCTAssertEqual(
            failure(of: evaluate(
                .binaryApp(
                    .lessThanOrEqual,
                    .lit(.ext(.ipaddr(.init(rawValue: "127.0.0.1")))),
                    .lit(.ext(.ipaddr(.init(rawValue: "127.0.0.1/32"))))
                ),
                request: request,
                entities: entities
            )),
            .typeError
        )
    }

    func testSliceC4aPublicEvaluateSupportsDecimalLiteralsAndPreservesInvalidTemporalPayloadBoundary() throws {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let entities = Entities(CedarMap.make([
            (key: principal, value: EntityData()),
            (key: action, value: EntityData()),
            (key: resource, value: EntityData()),
        ]))

        XCTAssertEqual(
            try evaluate(.lit(.ext(.decimal(.init(rawValue: "1.23")))), request: request, entities: entities).get(),
            .ext(.decimal(.init(rawValue: "1.23")))
        )
        XCTAssertEqual(
            try evaluate(
                .set([
                    .lit(.prim(.int(1))),
                    .record([
                        (key: "nested", value: .lit(.ext(.decimal(.init(rawValue: "1.23"))))),
                    ]),
                ]),
                request: request,
                entities: entities
            ).get(),
            .set(CedarSet.make([
                .prim(.int(1)),
                .record(CedarMap.make([
                    (key: "nested", value: .ext(.decimal(.init(rawValue: "1.23")))),
                ])),
            ]))
        )
        XCTAssertEqual(
            failure(of: evaluate(
                .record([
                    (key: "ok", value: .lit(.prim(.int(1)))),
                    (key: "nested", value: .set([
                        .lit(.ext(.duration(.init(rawValue: "PT1H")))),
                    ])),
                ]),
                request: request,
                entities: entities
            )),
            .extensionError
        )
    }

    func testSliceC4aPublicEvaluateSupportsWidenedDecimalLiteralContainersAndRejectsInvalidTemporalOnes() throws {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let entities = Entities(CedarMap.make([
            (key: principal, value: EntityData()),
            (key: action, value: EntityData()),
            (key: resource, value: EntityData()),
        ]))

        XCTAssertEqual(
            try evaluate(
                .lit(.set(CedarSet.make([
                    .ext(.decimal(.init(rawValue: "1.23"))),
                ]))),
                request: request,
                entities: entities
            ).get(),
            .set(CedarSet.make([
                .ext(.decimal(.init(rawValue: "1.23"))),
            ]))
        )
        XCTAssertEqual(
            failure(of: evaluate(
                .lit(.record(CedarMap.make([
                    (key: "nested", value: .ext(.duration(.init(rawValue: "PT1H")))),
                ]))),
                request: request,
                entities: entities
            )),
            .extensionError
        )
    }

    func testSliceC1bPublicEvaluateKeepsLazyExtensionSuppression() throws {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let entities = Entities(CedarMap.make([
            (key: principal, value: EntityData()),
            (key: action, value: EntityData()),
            (key: resource, value: EntityData()),
        ]))
        let extensionCall = Expr.call(.decimal, [.lit(.prim(.string("1.23456")))])
        let extensionCompare = Expr.binaryApp(
            .equal,
            .lit(.ext(.duration(.init(rawValue: "PT1H")))),
            .lit(.ext(.duration(.init(rawValue: "PT1H"))))
        )
        let extensionContainsAny = Expr.binaryApp(
            .containsAny,
            .set([.lit(.ext(.decimal(.init(rawValue: "1.23"))))]),
            .set([.lit(.prim(.int(1)))])
        )
        let extensionLiteral = Expr.lit(.ext(.ipaddr(.init(rawValue: "10.0.0.1"))))
        let extensionRecord = Expr.record([
            (key: "nested", value: .lit(.ext(.ipaddr(.init(rawValue: "10.0.0.1"))))),
        ])

        XCTAssertEqual(
            try evaluate(.binaryApp(.and, .lit(.prim(.bool(false))), extensionCall), request: request, entities: entities).get(),
            .prim(.bool(false))
        )
        XCTAssertEqual(
            try evaluate(.binaryApp(.or, .lit(.prim(.bool(true))), extensionCompare), request: request, entities: entities).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            try evaluate(.ifThenElse(.lit(.prim(.bool(false))), extensionCall, .lit(.prim(.int(1)))), request: request, entities: entities).get(),
            .prim(.int(1))
        )
        XCTAssertEqual(
            try evaluate(.binaryApp(.or, .lit(.prim(.bool(true))), extensionContainsAny), request: request, entities: entities).get(),
            .prim(.bool(true))
        )
        XCTAssertEqual(
            try evaluate(.binaryApp(.and, .lit(.prim(.bool(false))), extensionLiteral), request: request, entities: entities).get(),
            .prim(.bool(false))
        )
        XCTAssertEqual(
            try evaluate(.ifThenElse(.lit(.prim(.bool(false))), extensionRecord, .lit(.prim(.int(1)))), request: request, entities: entities).get(),
            .prim(.int(1))
        )
    }

    func testSliceC1bPublicEvaluateExecutesPolicyToExprThroughActionInAnyLowering() throws {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let actionReadFamily = EntityUID(ty: Name(id: "Action"), eid: "read-family")
        let actionAll = EntityUID(ty: Name(id: "Action"), eid: "all")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let entities = Entities(CedarMap.make([
            (key: principal, value: EntityData()),
            (key: action, value: EntityData(ancestors: CedarSet.make([actionReadFamily]))),
            (key: actionReadFamily, value: EntityData(ancestors: CedarSet.make([actionAll]))),
            (key: actionAll, value: EntityData()),
            (key: resource, value: EntityData()),
        ]))
        let policy = Policy(
            id: "permit-action-family",
            effect: .permit,
            principalScope: .eq(entity: principal),
            actionScope: .actionInAny(entities: CedarSet.make([actionAll])),
            resourceScope: .eq(entity: resource)
        )

        XCTAssertEqual(
            try evaluate(policy.toExpr(), request: request, entities: entities).get(),
            .prim(.bool(true))
        )
    }

    func testSliceC1bPublicEvaluatePropagatesMixedSetMembershipTypeErrorThroughPolicyToExpr() {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let staff = EntityUID(ty: Name(id: "Group"), eid: "staff")
        let company = EntityUID(ty: Name(id: "Group"), eid: "company")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let entities = Entities(CedarMap.make([
            (key: principal, value: EntityData(ancestors: CedarSet.make([staff]))),
            (key: staff, value: EntityData(ancestors: CedarSet.make([company]))),
            (key: company, value: EntityData()),
            (key: action, value: EntityData()),
            (key: resource, value: EntityData()),
        ]))
        let policy = Policy(
            id: "mixed-set-membership",
            effect: .permit,
            principalScope: .any,
            actionScope: .any,
            resourceScope: .any,
            conditions: [
                Condition(
                    kind: .when,
                    body: .binaryApp(
                        .in,
                        .variable(.principal),
                        .set([
                            .lit(.prim(.entityUID(company))),
                            .set([]),
                        ])
                    )
                ),
            ]
        )

        XCTAssertEqual(
            failure(of: evaluate(policy.toExpr(), request: request, entities: entities)),
            .typeError
        )
    }

    func testSliceC2bPublicIsAuthorizedAllowsSatisfiedPermit() {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let policy = Policy(
            id: "permit-public-allow",
            effect: .permit,
            principalScope: .eq(entity: principal),
            actionScope: .eq(entity: action),
            resourceScope: .eq(entity: resource)
        )
        let response = isAuthorized(
            request: request,
            entities: Entities(),
            policies: .make([(key: policy.id, value: policy)])
        )

        XCTAssertEqual(response.decision, .allow)
        XCTAssertEqual(response.determining, CedarSet.make([policy.id]))
        XCTAssertEqual(response.erroring, .empty)
    }

    func testSliceC2bPublicIsAuthorizedReturnsDenyAndErroringForErroredPolicy() {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(
            principal: principal,
            action: action,
            resource: resource,
            context: .record(CedarMap.make([
                (key: "active", value: .bool(true)),
            ]))
        )
        let policy = Policy(
            id: "permit-public-error",
            effect: .permit,
            principalScope: .eq(entity: principal),
            actionScope: .eq(entity: action),
            resourceScope: .eq(entity: resource),
            conditions: [
                Condition(kind: .when, body: .getAttr(.variable(.context), "missing")),
            ]
        )
        let response = isAuthorized(
            request: request,
            entities: Entities(),
            policies: .make([(key: policy.id, value: policy)])
        )

        XCTAssertEqual(response.decision, .deny)
        XCTAssertEqual(response.determining, .empty)
        XCTAssertEqual(response.erroring, CedarSet.make([policy.id]))
    }

    func testSliceC1bRepairPublicIsAuthorizedReflectsExtensionSetMembershipAndUnsupportedComparisonErrors() {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let allowPolicy = Policy(
            id: "permit-public-extension-membership",
            effect: .permit,
            principalScope: .eq(entity: principal),
            actionScope: .eq(entity: action),
            resourceScope: .eq(entity: resource),
            conditions: [Condition(
                kind: .when,
                body: .binaryApp(
                    .contains,
                    .set([
                        .lit(.ext(.decimal(.init(rawValue: "1.2300")))),
                    ]),
                    .lit(.ext(.decimal(.init(rawValue: "1.23"))))
                )
            )]
        )
        let errorPolicy = Policy(
            id: "permit-public-extension-type-error",
            effect: .permit,
            principalScope: .eq(entity: principal),
            actionScope: .eq(entity: action),
            resourceScope: .eq(entity: resource),
            conditions: [Condition(
                kind: .when,
                body: .binaryApp(
                    .lessThan,
                    .lit(.ext(.datetime(.init(rawValue: "2024-01-01T00:00:00Z")))),
                    .lit(.ext(.duration(.init(rawValue: "1h"))))
                )
            )]
        )

        let response = isAuthorized(
            request: request,
            entities: Entities(),
            policies: .make([
                (key: allowPolicy.id, value: allowPolicy),
                (key: errorPolicy.id, value: errorPolicy),
            ])
        )

        XCTAssertEqual(response.decision, .allow)
        XCTAssertEqual(response.determining, CedarSet.make([allowPolicy.id]))
        XCTAssertEqual(response.erroring, CedarSet.make([errorPolicy.id]))
    }

    func testSliceC4aPublicEvaluateConstructsDecimalAndReportsParseFailure() throws {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let entities = Entities()

        XCTAssertEqual(
            try evaluate(.call(.decimal, [.lit(.prim(.string("1.2300")))]), request: request, entities: entities).get(),
            .ext(.decimal(.init(rawValue: "1.2300")))
        )
        XCTAssertEqual(
            failure(of: evaluate(.call(.decimal, [.lit(.prim(.string("1.23456")))]), request: request, entities: entities)),
            .extensionError
        )
    }

    func testSliceC4aPublicIsAuthorizedAllowsSatisfiedDecimalPolicy() {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let policy = Policy(
            id: "permit-public-decimal-allow",
            effect: .permit,
            principalScope: .eq(entity: principal),
            actionScope: .eq(entity: action),
            resourceScope: .eq(entity: resource),
            conditions: [Condition(
                kind: .when,
                body: .call(
                    .greaterThanOrEqual,
                    [
                        .call(.decimal, [.lit(.prim(.string("1.2300")))]),
                        .lit(.ext(.decimal(.init(rawValue: "1.23")))),
                    ]
                )
            )]
        )

        let response = isAuthorized(
            request: request,
            entities: Entities(),
            policies: .make([(key: policy.id, value: policy)])
        )

        XCTAssertEqual(response.decision, .allow)
        XCTAssertEqual(response.determining, CedarSet.make([policy.id]))
        XCTAssertEqual(response.erroring, .empty)
    }

    func testSliceC4aPublicIsAuthorizedCollectsDecimalParseFailuresInErroring() {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let policy = Policy(
            id: "permit-public-decimal-error",
            effect: .permit,
            principalScope: .eq(entity: principal),
            actionScope: .eq(entity: action),
            resourceScope: .eq(entity: resource),
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
            entities: Entities(),
            policies: .make([(key: policy.id, value: policy)])
        )

        XCTAssertEqual(response.decision, .deny)
        XCTAssertEqual(response.determining, .empty)
        XCTAssertEqual(response.erroring, CedarSet.make([policy.id]))
    }

    func testSliceC4bPublicPayloadStructKeepsLexicalRawValueBehavior() {
        let direct = Ext.IPAddr(rawValue: "127.0.0.1")
        let withDefaultPrefix = Ext.IPAddr(rawValue: "127.0.0.1/32")

        XCTAssertNotEqual(direct, withDefaultPrefix)
        XCTAssertLessThan(direct, withDefaultPrefix)
        XCTAssertEqual(direct.rawValue, "127.0.0.1")
    }

    func testSliceC4bPublicEvaluateSupportsIPAddrAndPreservesInvalidDurationBoundary() throws {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let entities = Entities()

        XCTAssertEqual(
            try evaluate(
                .lit(.ext(.ipaddr(.init(rawValue: "127.0.0.1")))),
                request: request,
                entities: entities
            ).get(),
            .ext(.ipaddr(.init(rawValue: "127.0.0.1")))
        )
        XCTAssertEqual(
            failure(of: evaluate(
                .lit(.ext(.duration(.init(rawValue: "PT1H")))),
                request: request,
                entities: entities
            )),
            .extensionError
        )
    }

    func testSliceC5PublicPayloadStructKeepsLexicalTemporalRawValueBehavior() {
        let dateOnly = Ext.Datetime(rawValue: "2024-01-01")
        let utcMidnight = Ext.Datetime(rawValue: "2024-01-01T00:00:00Z")
        let sixtyMinutes = Ext.Duration(rawValue: "60m")
        let oneHour = Ext.Duration(rawValue: "1h")

        XCTAssertNotEqual(dateOnly, utcMidnight)
        XCTAssertLessThan(dateOnly, utcMidnight)
        XCTAssertEqual(dateOnly.rawValue, "2024-01-01")
        XCTAssertNotEqual(sixtyMinutes, oneHour)
        XCTAssertLessThan(oneHour, sixtyMinutes)
        XCTAssertEqual(sixtyMinutes.rawValue, "60m")
    }

    func testSliceC5PublicSemanticExtContrastForDatetimeAndDuration() {
        XCTAssertEqual(
            Ext.datetime(.init(rawValue: "2024-01-01")),
            Ext.datetime(.init(rawValue: "2024-01-01T00:00:00Z"))
        )
        XCTAssertEqual(
            Ext.duration(.init(rawValue: "60m")),
            Ext.duration(.init(rawValue: "1h"))
        )
    }

    func testSliceC5PublicEvaluateSupportsTemporalFamiliesAndMixedContainers() throws {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let entities = Entities()

        XCTAssertEqual(
            try evaluate(
                .record([
                    (key: "mixed", value: .set([
                        .lit(.ext(.decimal(.init(rawValue: "1.23")))),
                        .lit(.ext(.ipaddr(.init(rawValue: "127.0.0.1")))),
                        .lit(.ext(.datetime(.init(rawValue: "2024-01-01T00:00:00Z")))),
                        .lit(.ext(.duration(.init(rawValue: "1h")))),
                    ])),
                ]),
                request: request,
                entities: entities
            ).get(),
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

    func testSliceC5PublicEvaluateConstructsTemporalValuesAndReportsBoundaries() throws {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let entities = Entities()

        XCTAssertEqual(
            try evaluate(.call(.datetime, [.lit(.prim(.string("2024-01-01")))]), request: request, entities: entities).get(),
            .ext(.datetime(.init(rawValue: "2024-01-01")))
        )
        XCTAssertEqual(
            try evaluate(.call(.duration, [.lit(.prim(.string("90m")))]), request: request, entities: entities).get(),
            .ext(.duration(.init(rawValue: "90m")))
        )
        XCTAssertEqual(
            failure(of: evaluate(.call(.datetime, [.lit(.prim(.string("2024-01-01T00:00:60Z")))]), request: request, entities: entities)),
            .extensionError
        )
        XCTAssertEqual(
            failure(of: evaluate(.call(.duration, [.lit(.prim(.string("PT1H")))]), request: request, entities: entities)),
            .extensionError
        )
    }

    func testSliceC5PublicIsAuthorizedSupportsDatetimeConditions() {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let policy = Policy(
            id: "permit-public-datetime-allow",
            effect: .permit,
            principalScope: .eq(entity: principal),
            actionScope: .eq(entity: action),
            resourceScope: .eq(entity: resource),
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
            entities: Entities(),
            policies: .make([(key: policy.id, value: policy)])
        )

        XCTAssertEqual(response.decision, .allow)
        XCTAssertEqual(response.determining, CedarSet.make([policy.id]))
        XCTAssertEqual(response.erroring, .empty)
    }

    func testSliceC5PublicIsAuthorizedCollectsDatetimeParseFailuresInErroring() {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let policy = Policy(
            id: "permit-public-datetime-error",
            effect: .permit,
            principalScope: .eq(entity: principal),
            actionScope: .eq(entity: action),
            resourceScope: .eq(entity: resource),
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
            entities: Entities(),
            policies: .make([(key: policy.id, value: policy)])
        )

        XCTAssertEqual(response.decision, .deny)
        XCTAssertEqual(response.determining, .empty)
        XCTAssertEqual(response.erroring, CedarSet.make([policy.id]))
    }

    func testSliceC5PublicIsAuthorizedSupportsDurationConditions() {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let policy = Policy(
            id: "permit-public-duration-allow",
            effect: .permit,
            principalScope: .eq(entity: principal),
            actionScope: .eq(entity: action),
            resourceScope: .eq(entity: resource),
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
            entities: Entities(),
            policies: .make([(key: policy.id, value: policy)])
        )

        XCTAssertEqual(response.decision, .allow)
        XCTAssertEqual(response.determining, CedarSet.make([policy.id]))
        XCTAssertEqual(response.erroring, .empty)
    }

    func testSliceC5PublicIsAuthorizedCollectsDurationParseFailuresInErroring() {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let policy = Policy(
            id: "permit-public-duration-error",
            effect: .permit,
            principalScope: .eq(entity: principal),
            actionScope: .eq(entity: action),
            resourceScope: .eq(entity: resource),
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
            entities: Entities(),
            policies: .make([(key: policy.id, value: policy)])
        )

        XCTAssertEqual(response.decision, .deny)
        XCTAssertEqual(response.determining, .empty)
        XCTAssertEqual(response.erroring, CedarSet.make([policy.id]))
    }

    func testSliceC4bPublicEvaluateConstructsIPAddrAndReportsParseFailure() throws {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let entities = Entities()

        XCTAssertEqual(
            try evaluate(
                .call(.ip, [.lit(.prim(.string("127.0.0.1")))]),
                request: request,
                entities: entities
            ).get(),
            .ext(.ipaddr(.init(rawValue: "127.0.0.1")))
        )
        XCTAssertEqual(
            failure(of: evaluate(
                .call(.ip, [.lit(.prim(.string("::ffff:127.0.0.1")))]),
                request: request,
                entities: entities
            )),
            .extensionError
        )
    }

    func testSliceC4bPublicIsAuthorizedSupportsIPAddrConditions() {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let policy = Policy(
            id: "permit-public-ipaddr-allow",
            effect: .permit,
            principalScope: .eq(entity: principal),
            actionScope: .eq(entity: action),
            resourceScope: .eq(entity: resource),
            conditions: [Condition(
                kind: .when,
                body: .call(
                    .isLoopback,
                    [
                        .call(.ip, [.lit(.prim(.string("::1")))]),
                    ]
                )
            )]
        )

        let response = isAuthorized(
            request: request,
            entities: Entities(),
            policies: .make([(key: policy.id, value: policy)])
        )

        XCTAssertEqual(response.decision, .allow)
        XCTAssertEqual(response.determining, CedarSet.make([policy.id]))
        XCTAssertEqual(response.erroring, .empty)
    }

    func testSliceC4bPublicIsAuthorizedCollectsIPAddrParseFailuresInErroring() {
        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let policy = Policy(
            id: "permit-public-ipaddr-error",
            effect: .permit,
            principalScope: .eq(entity: principal),
            actionScope: .eq(entity: action),
            resourceScope: .eq(entity: resource),
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
            entities: Entities(),
            policies: .make([(key: policy.id, value: policy)])
        )

        XCTAssertEqual(response.decision, .deny)
        XCTAssertEqual(response.determining, .empty)
        XCTAssertEqual(response.erroring, CedarSet.make([policy.id]))
    }

    func testSourceSpansAndDiagnosticsPublicSurfaceCompilesWithPlainImport() {
        let span = SourceSpan(
            start: SourceLocation(line: 1, column: 1, offset: 0),
            end: SourceLocation(line: 1, column: 8, offset: 7),
            source: "policy.cedar"
        )
        let warning = Diagnostic(
            code: "request.warning",
            category: .request,
            severity: .warning,
            message: "request uses deprecated field",
            sourceSpan: span
        )
        let error = Diagnostic(
            code: "policy.error",
            category: .policy,
            severity: .error,
            message: "duplicate policy id",
            sourceSpan: span
        )
        let diagnostics = Diagnostics([error, warning])
        let success: LoadResult<String> = .success("loaded", diagnostics: Diagnostics([warning]))
        let failure: LoadResult<String> = .failure(Diagnostics([error]))
        let valid = ValidationResult(diagnostics: Diagnostics([warning]), isValid: true)
        let invalid = ValidationResult.failure(Diagnostics([error]))

        XCTAssertEqual(diagnostics.elements.map(\.code), ["request.warning", "policy.error"])
        XCTAssertTrue(DiagnosticSeverity.allCases.contains(.warning))
        XCTAssertTrue(DiagnosticCategory.allCases.contains(.policy))
        XCTAssertFalse(valid.diagnostics.hasErrors)
        XCTAssertFalse(diagnostics.isEmpty)
        XCTAssertTrue(invalid.diagnostics.hasErrors)
        XCTAssertTrue(valid.isValid)
        XCTAssertFalse(invalid.isValid)

        switch success {
        case let .success(value, successDiagnostics):
            XCTAssertEqual(value, "loaded")
            XCTAssertEqual(successDiagnostics.elements, [warning])
        case .failure:
            XCTFail("Expected load success")
        }

        switch failure {
        case .success:
            XCTFail("Expected load failure")
        case let .failure(failureDiagnostics):
            XCTAssertEqual(failureDiagnostics.elements, [error])
        }
    }

    func testLoadingAndLinkingPublicSurfaceCompilesWithPlainImport() {
        let schema = loadSchema(LoaderFixtures.schemaJSON)
        let templates = loadTemplates(LoaderFixtures.templatesJSON)
        let templateLinks = loadTemplateLinks(LoaderFixtures.templateLinksJSON)
        let policies = loadPolicies(LoaderFixtures.policiesJSON)
        let entities = loadEntities(LoaderFixtures.entitiesJSON)
        let request = loadRequest(LoaderFixtures.requestJSON)
        let corpus = loadCorpus(LoaderFixtures.corpusJSON)

        guard case let .success(loadedSchema, diagnostics: _) = schema,
              case let .success(loadedTemplates, diagnostics: _) = templates,
              case let .success(loadedLinks, diagnostics: _) = templateLinks,
              case let .success(loadedPolicies, diagnostics: _) = policies,
              case let .success(loadedEntities, diagnostics: _) = entities,
              case let .success(loadedRequest, diagnostics: _) = request,
              case let .success(loadedCorpus, diagnostics: _) = corpus,
              case let .success(linkedPolicy, diagnostics: _) = link(templateLinkedPolicy: loadedLinks[0], templates: loadedTemplates)
        else {
            return XCTFail("Expected public loading and linking surfaces to succeed")
        }

        XCTAssertNotNil(loadedSchema.entityType(Name(id: "User")))
        XCTAssertEqual(linkedPolicy.id, "linked-view")
        XCTAssertEqual(loadedPolicies.find("permit-view")?.id, "permit-view")
        XCTAssertTrue(loadedEntities.contains(EntityUID(ty: Name(id: "User"), eid: "alice")))
        XCTAssertEqual(loadedRequest.action, EntityUID(ty: Name(id: "Action"), eid: "view"))
        XCTAssertEqual(loadedCorpus.templateLinks.first?.id, "linked-view")
    }

    func testSchemaTextAndAuthorizationTracePublicSurfaceCompilesWithPlainImport() {
        let schemaResult = loadSchemaCedar(#"""
namespace Demo {
    entity User tags String;
    entity Photo;
    action "view" appliesTo {
        principal: [User],
        resource: [Photo],
        context: {}
    };
}
"""#)

        guard case let .success(schema, diagnostics: _) = schemaResult else {
            return XCTFail("Expected Cedar schema text load to succeed")
        }

        let principal = EntityUID(ty: Name(id: "User"), eid: "alice")
        let action = EntityUID(ty: Name(id: "Action"), eid: "view")
        let resource = EntityUID(ty: Name(id: "Photo"), eid: "vacation")
        let request = Request(principal: principal, action: action, resource: resource)
        let policy = Policy(
            id: "trace-public",
            effect: .permit,
            principalScope: .eq(entity: principal),
            actionScope: .eq(entity: action),
            resourceScope: .eq(entity: resource)
        )
        let trace = traceAuthorization(
            request: request,
            entities: Entities(),
            policies: .make([(key: policy.id, value: policy)])
        )

        XCTAssertNotNil(schema.entityType(Name(id: "User", path: ["Demo"])))
        XCTAssertNotNil(schema.action(EntityUID(ty: Name(id: "Action", path: ["Demo"]), eid: "view")))
        XCTAssertEqual(trace.matched, CedarSet.make([policy.id]))
        XCTAssertEqual(trace.satisfied.first?.policyID, policy.id)
        XCTAssertEqual(trace.determiningEvaluations.first?.policyID, policy.id)
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
