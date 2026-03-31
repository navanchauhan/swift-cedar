public enum ValidationMode: Int, CaseIterable, Equatable, Hashable, Comparable, Sendable {
    case strict
    case permissive

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public func validatePolicies(_ policies: Policies, schema: Schema) -> ValidationResult {
    validatePolicies(policies, schema: schema, mode: .strict, level: nil)
}

public func validatePolicies(_ policies: Policies, schema: Schema, level: Int?) -> ValidationResult {
    validatePolicies(policies, schema: schema, mode: .strict, level: level)
}

public func validatePolicies(
    _ policies: Policies,
    schema: Schema,
    mode: ValidationMode,
    level: Int? = nil
) -> ValidationResult {
    var diagnostics = validateSchemaStructure(schema)

    for policy in policies.values {
        diagnostics = diagnostics.appending(contentsOf: validatePolicy(policy, schema: schema, mode: mode, level: level))
    }

    return diagnostics.hasErrors ? .failure(diagnostics) : .success(diagnostics: diagnostics)
}

public func validateRequest(_ request: Request, schema: Schema) -> ValidationResult {
    validateRequest(request, schema: schema, mode: .strict)
}

public func validateRequest(_ request: Request, schema: Schema, mode: ValidationMode) -> ValidationResult {
    let diagnostics = validateSchemaStructure(schema)
        .appending(contentsOf: validateRequestAgainstSchema(request, schema: schema, mode: mode))
    return diagnostics.hasErrors ? .failure(diagnostics) : .success(diagnostics: diagnostics)
}

public func validateEntities(_ entities: Entities, schema: Schema) -> ValidationResult {
    validateEntities(entities, schema: schema, mode: .strict)
}

public func validateEntities(_ entities: Entities, schema: Schema, mode: ValidationMode) -> ValidationResult {
    let diagnostics = validateSchemaStructure(schema)
        .appending(contentsOf: validateEntitiesAgainstSchema(entities, schema: schema, mode: mode))
    return diagnostics.hasErrors ? .failure(diagnostics) : .success(diagnostics: diagnostics)
}

private enum ValidationBool: Equatable, Sendable {
    case any
    case tt
    case ff

    func logicalNot() -> Self {
        switch self {
        case .any:
            return .any
        case .tt:
            return .ff
        case .ff:
            return .tt
        }
    }
}

private struct ValidationQualifiedType: Equatable, Sendable {
    let type: ValidationType
    let required: Bool
}

private indirect enum ValidationType: Equatable, Sendable {
    case bool(ValidationBool)
    case int
    case string
    case entity(CedarSet<Name>)
    case set(ValidationType?)
    case record(CedarMap<Attr, ValidationQualifiedType>)
    case ext(Schema.ExtensionType)

    static func singleEntity(_ name: Name) -> Self {
        .entity(CedarSet.make([name]))
    }

    static func fromSchema(_ type: Schema.CedarType) -> Self {
        switch type {
        case .bool:
            return .bool(.any)
        case .int:
            return .int
        case .string:
            return .string
        case let .entity(name):
            return .singleEntity(name)
        case let .set(element):
            return .set(.fromSchema(element))
        case let .record(record):
            return .record(convertRecordType(record))
        case let .ext(extType):
            return .ext(extType)
        }
    }

    var erased: Self {
        switch self {
        case .bool:
            return .bool(.any)
        case let .set(element):
            return .set(element?.erased)
        case let .record(record):
            return .record(CedarMap.make(record.entries.map {
                (key: $0.key, value: ValidationQualifiedType(type: $0.value.type.erased, required: $0.value.required))
            }))
        default:
            return self
        }
    }

    var isAlwaysFalse: Bool {
        if case .bool(.ff) = self {
            return true
        }

        return false
    }
}

private indirect enum TypedExpr: Sendable {
    case lit(CedarValue, ValidationType)
    case variable(Var, ValidationType)
    case unaryApp(UnaryOp, TypedExpr, ValidationType)
    case binaryApp(BinaryOp, TypedExpr, TypedExpr, ValidationType)
    case ifThenElse(TypedExpr, TypedExpr, TypedExpr, ValidationType)
    case set([TypedExpr], ValidationType)
    case record([(key: Attr, value: TypedExpr)], ValidationType)
    case hasAttr(TypedExpr, Attr, ValidationType)
    case getAttr(TypedExpr, Attr, ValidationType)
    case like(TypedExpr, Pattern, ValidationType)
    case isEntityType(TypedExpr, Name, ValidationType)
    case call(ExtFun, [TypedExpr], ValidationType)

    var type: ValidationType {
        switch self {
        case let .lit(_, type),
             let .variable(_, type),
             let .unaryApp(_, _, type),
             let .binaryApp(_, _, _, type),
             let .ifThenElse(_, _, _, type),
             let .set(_, type),
             let .record(_, type),
             let .hasAttr(_, _, type),
             let .getAttr(_, _, type),
             let .like(_, _, type),
             let .isEntityType(_, _, type),
             let .call(_, _, type):
            return type
        }
    }
}

private struct RequestTypeInfo: Sendable {
    let principal: Name
    let action: EntityUID
    let resource: Name
    let context: CedarMap<Attr, ValidationQualifiedType>
}

private struct TypeEnvironment: Sendable {
    let schema: Schema
    let mode: ValidationMode
    let requestType: RequestTypeInfo
}

private enum ValidationCapability: Hashable, Sendable {
    case attribute(base: Expr, attr: Attr)
    case tag(base: Expr, key: String)
}

private struct TypecheckContext: Sendable {
    let environment: TypeEnvironment
    let capabilities: Set<ValidationCapability>

    init(environment: TypeEnvironment, capabilities: Set<ValidationCapability> = []) {
        self.environment = environment
        self.capabilities = capabilities
    }

    func appending(_ additional: Set<ValidationCapability>) -> Self {
        guard !additional.isEmpty else {
            return self
        }

        return Self(environment: environment, capabilities: capabilities.union(additional))
    }
}

private enum TypecheckFailure: Error {
    case unknownEntity(EntityUID)
    case unknownEntityType(Name)
    case impossiblePolicy
    case unexpectedType(ValidationType, expected: String)
    case attrNotFound(ValidationType, Attr)
    case tagNotAllowed(CedarSet<Name>)
    case incompatibleTagTypes(CedarSet<Name>)
    case unsafeOptionalAttributeAccess(ValidationType, Attr)
    case unsafeTagAccess(CedarSet<Name>, String)
    case emptySet
    case incompatibleSetTypes([ValidationType])
    case invalidExtensionCall(ExtFun)
}

private func validateSchemaStructure(_ schema: Schema) -> Diagnostics {
    var diagnostics = Diagnostics.empty

    for definition in schema.entityTypes.values {
        for memberOfType in definition.memberOfTypes.elements where schema.entityType(memberOfType) == nil {
            diagnostics = diagnostics.appending(contentsOf: validationDiagnostic(
                code: "validation.schemaUnknownEntityType",
                message: "Entity type \(definition.name) references unknown parent type \(memberOfType)"
            ))
        }

        diagnostics = diagnostics.appending(contentsOf: validateSchemaRecord(definition.attributes, schema: schema, owner: "Entity type \(definition.name)"))

        if let tags = definition.tags {
            diagnostics = diagnostics.appending(contentsOf: validateSchemaType(tags, schema: schema, owner: "Entity type \(definition.name) tags"))
        }
    }

    for action in schema.actions.values {
        for principalType in action.principalTypes.elements where schema.entityType(principalType) == nil {
            diagnostics = diagnostics.appending(contentsOf: validationDiagnostic(
                code: "validation.schemaUnknownPrincipalType",
                message: "Action \(action.uid) references unknown principal type \(principalType)"
            ))
        }

        for resourceType in action.resourceTypes.elements where schema.entityType(resourceType) == nil {
            diagnostics = diagnostics.appending(contentsOf: validationDiagnostic(
                code: "validation.schemaUnknownResourceType",
                message: "Action \(action.uid) references unknown resource type \(resourceType)"
            ))
        }

        for parent in action.memberOf.elements where schema.action(parent) == nil {
            diagnostics = diagnostics.appending(contentsOf: validationDiagnostic(
                code: "validation.schemaUnknownActionAncestor",
                message: "Action \(action.uid) references unknown ancestor \(parent)"
            ))
        }

        diagnostics = diagnostics.appending(contentsOf: validateSchemaRecord(action.context, schema: schema, owner: "Action \(action.uid) context"))
    }

    return diagnostics
}

private func validateSchemaRecord(
    _ record: CedarMap<Attr, Schema.QualifiedType>,
    schema: Schema,
    owner: String
) -> Diagnostics {
    var diagnostics = Diagnostics.empty

    for entry in record {
        diagnostics = diagnostics.appending(contentsOf: validateSchemaType(entry.value.type, schema: schema, owner: "\(owner).\(entry.key)"))
    }

    return diagnostics
}

private func validateSchemaType(_ type: Schema.CedarType, schema: Schema, owner: String) -> Diagnostics {
    switch type {
    case let .entity(name):
        if name == Name(id: "Action") || schema.entityType(name) != nil {
            return .empty
        }

        return validationDiagnostic(
            code: "validation.schemaUnknownTypeReference",
            message: "\(owner) references unknown entity type \(name)"
        )
    case let .set(element):
        return validateSchemaType(element, schema: schema, owner: owner)
    case let .record(record):
        return validateSchemaRecord(record, schema: schema, owner: owner)
    case .bool, .int, .string, .ext:
        return .empty
    }
}

private func environments(for schema: Schema, mode: ValidationMode) -> [TypeEnvironment] {
    var result: [TypeEnvironment] = []

    for action in schema.actions.values {
        for principal in action.principalTypes.elements {
            for resource in action.resourceTypes.elements {
                result.append(TypeEnvironment(
                    schema: schema,
                    mode: mode,
                    requestType: RequestTypeInfo(
                        principal: principal,
                        action: action.uid,
                        resource: resource,
                        context: convertRecordType(action.context)
                    )
                ))
            }
        }
    }

    return result
}

private func validatePolicy(_ policy: Policy, schema: Schema, mode: ValidationMode, level: Int?) -> Diagnostics {
    var diagnostics = checkReferencedEntities(policy.toExpr(), schema: schema, policyID: policy.id)
    let candidateEnvironments = applicableEnvironments(for: policy, schema: schema, mode: mode)
    var typedExpressions: [TypedExpr] = []

    if candidateEnvironments.isEmpty {
        return diagnostics.appending(contentsOf: validationDiagnostic(
            code: "validation.actionNotApplicable",
            message: "Policy \(policy.id) does not apply to any schema action/principal/resource environment"
        ))
    }

    for environment in candidateEnvironments {
        let expression = substituteAction(environment.requestType.action, in: policy.toExpr())

        switch typecheck(expression, context: TypecheckContext(environment: environment)) {
        case let .success(typed):
            guard isBoolean(typed.type) else {
                diagnostics = diagnostics.appending(contentsOf: validationDiagnostic(
                    code: "validation.unexpectedType",
                    message: "Policy \(policy.id) does not typecheck to a boolean"
                ))
                continue
            }

            if let level, !checkLevel(typed, environment: environment, remainingLevel: level) {
                diagnostics = diagnostics.appending(contentsOf: validationDiagnostic(
                    code: "validation.levelError",
                    message: "Policy \(policy.id) exceeds validation level \(level)"
                ))
            }

            typedExpressions.append(typed)
        case let .failure(error):
            diagnostics = diagnostics.appending(contentsOf: typecheckDiagnostics(error, policyID: policy.id))
        }
    }

    return diagnostics
}

private func validateRequestAgainstSchema(_ request: Request, schema: Schema, mode _: ValidationMode) -> Diagnostics {
    let candidateEnvironments = environments(for: schema, mode: .strict).filter { $0.requestType.action == request.action }

    guard !candidateEnvironments.isEmpty else {
        return validationDiagnostic(
            code: "validation.requestUnknownAction",
            message: "Request action \(request.action) is not declared in the schema"
        )
    }

    let contextRecord: CedarMap<Attr, CedarValue>
    switch request.context.materializeRecord() {
    case let .success(record):
        contextRecord = record
    case let .failure(error):
        return validationDiagnostic(
            code: "validation.requestInvalidContext",
            message: "Request context is invalid: \(String(describing: error))"
        )
    }

    let matches = candidateEnvironments.contains { environment in
        valueConforms(.prim(.entityUID(request.principal)), to: .singleEntity(environment.requestType.principal), schema: schema)
            && request.action == environment.requestType.action
            && valueConforms(.prim(.entityUID(request.resource)), to: .singleEntity(environment.requestType.resource), schema: schema)
            && (
                valueConforms(.record(contextRecord), to: .record(environment.requestType.context), schema: schema)
                    || requestExprConforms(request.context, to: .record(environment.requestType.context), schema: schema)
            )
    }

    if matches {
        return .empty
    }

    return validationDiagnostic(
        code: "validation.requestNoMatchingEnvironment",
        message: "Request could not be validated in any schema environment"
    )
}

private func validateEntitiesAgainstSchema(_ entities: Entities, schema: Schema, mode _: ValidationMode) -> Diagnostics {
    var diagnostics = Diagnostics.empty

    for entry in entities.entries {
        let uid = entry.key
        let data = entry.value

        if schema.action(uid) != nil {
            if !data.attrs.isEmpty {
                diagnostics = diagnostics.appending(contentsOf: validationDiagnostic(
                    code: "validation.actionAttributesNotAllowed",
                    message: "Action entity \(uid) cannot carry attributes"
                ))
            }

            if !data.tags.isEmpty {
                diagnostics = diagnostics.appending(contentsOf: validationDiagnostic(
                    code: "validation.actionTagsNotAllowed",
                    message: "Action entity \(uid) cannot carry tags"
                ))
            }

            if data.ancestors.contains(where: { !actionEntityMatches(uid, ancestor: $0, schema: schema) }) {
                diagnostics = diagnostics.appending(contentsOf: validationDiagnostic(
                    code: "validation.actionAncestorsMismatch",
                    message: "Action entity \(uid) ancestors do not match the schema"
                ))
            }

            continue
        }

        guard let entityDefinition = schema.entityType(uid.ty) else {
            diagnostics = diagnostics.appending(contentsOf: validationDiagnostic(
                code: "validation.unknownEntityType",
                message: "Entity \(uid) uses undeclared type \(uid.ty)"
            ))
            continue
        }

        if let enumEntityIDs = entityDefinition.enumEntityIDs, !enumEntityIDs.contains(uid.eid) {
            diagnostics = diagnostics.appending(contentsOf: validationDiagnostic(
                code: "validation.invalidEnumEntityID",
                message: "Entity \(uid) is not a valid member of enum type \(uid.ty)"
            ))
        }

        if !valueConforms(.record(data.attrs), to: .record(convertRecordType(entityDefinition.attributes)), schema: schema) {
            diagnostics = diagnostics.appending(contentsOf: validationDiagnostic(
                code: "validation.entityAttributeTypeMismatch",
                message: "Entity \(uid) attributes do not match the schema"
            ))
        }

        if let tagType = entityDefinition.tags {
            let expected = ValidationType.fromSchema(tagType)
            for tag in data.tags.values where !valueConforms(tag, to: expected, schema: schema) {
                diagnostics = diagnostics.appending(contentsOf: validationDiagnostic(
                    code: "validation.entityTagTypeMismatch",
                    message: "Entity \(uid) tags do not match the schema"
                ))
                break
            }
        } else if !data.tags.isEmpty {
            diagnostics = diagnostics.appending(contentsOf: validationDiagnostic(
                code: "validation.entityTagsNotAllowed",
                message: "Entity \(uid) cannot carry tags under this schema"
            ))
        }

        for ancestor in data.ancestors.elements {
            if !entityTypeCanHaveAncestor(uid.ty, ancestor.ty, schema: schema) {
                diagnostics = diagnostics.appending(contentsOf: validationDiagnostic(
                    code: "validation.entityAncestorTypeMismatch",
                    message: "Entity \(uid) cannot be a member of \(ancestor.ty)"
                ))
            }

            if !entities.contains(ancestor) && schema.action(ancestor) == nil {
                diagnostics = diagnostics.appending(contentsOf: validationDiagnostic(
                    code: "validation.entityUnknownAncestor",
                    message: "Entity \(uid) references unknown ancestor \(ancestor)"
                ))
            }
        }
    }

    for action in schema.actions.keys where !entities.contains(action) {
        diagnostics = diagnostics.appending(contentsOf: validationDiagnostic(
            code: "validation.missingActionEntity",
            message: "Entity store is missing schema action \(action)"
        ))
    }

    return diagnostics
}

private func validationDiagnostic(code: String, message: String) -> Diagnostics {
    Diagnostics([
        Diagnostic(
            code: code,
            category: .validation,
            severity: .error,
            message: message,
            sourceSpan: nil
        )
    ])
}

private func convertRecordType(_ record: CedarMap<Attr, Schema.QualifiedType>) -> CedarMap<Attr, ValidationQualifiedType> {
    CedarMap.make(record.entries.map {
        (key: $0.key, value: ValidationQualifiedType(type: .fromSchema($0.value.type), required: $0.value.required))
    })
}

private func isEntityDescendant(_ child: Name, of ancestor: Name, schema: Schema) -> Bool {
    var visited: [Name] = []
    return isEntityDescendant(child, of: ancestor, schema: schema, visited: &visited)
}

private func isEntityDescendant(
    _ child: Name,
    of ancestor: Name,
    schema: Schema,
    visited: inout [Name]
) -> Bool {
    guard let definition = schema.entityType(child) else {
        return false
    }

    if visited.contains(where: { $0 == child }) {
        return false
    }

    var nextVisited = visited
    nextVisited.append(child)

    for parent in definition.memberOfTypes.elements {
        var branchVisited = nextVisited
        if parent == ancestor || isEntityDescendant(parent, of: ancestor, schema: schema, visited: &branchVisited) {
            return true
        }
    }

    return false
}

private func entityTypeCanHaveAncestor(_ child: Name, _ ancestor: Name, schema: Schema) -> Bool {
    child == ancestor || isEntityDescendant(child, of: ancestor, schema: schema)
}

private func possibleRuntimeEntityTypes(for declaredType: Name, schema: Schema) -> CedarSet<Name> {
    guard schema.entityType(declaredType) != nil else {
        return CedarSet.make([declaredType])
    }

    return CedarSet.make(schema.entityTypes.keys.filter {
        $0 == declaredType || isEntityDescendant($0, of: declaredType, schema: schema)
    })
}

private func possibleRuntimeEntityTypes(for declaredTypes: CedarSet<Name>, schema: Schema) -> CedarSet<Name> {
    CedarSet.make(declaredTypes.elements.flatMap { possibleRuntimeEntityTypes(for: $0, schema: schema).elements })
}

private func entityTypesCanOverlap(_ lhs: CedarSet<Name>, _ rhs: CedarSet<Name>, schema: Schema) -> Bool {
    possibleRuntimeEntityTypes(for: lhs, schema: schema).intersects(with: possibleRuntimeEntityTypes(for: rhs, schema: schema))
}

private func strictEntityTypesCompatible(_ lhs: ValidationType, _ rhs: ValidationType, schema: Schema) -> Bool {
    guard case let .entity(left) = lhs, case let .entity(right) = rhs else {
        return true
    }

    return entityTypesCanOverlap(left, right, schema: schema)
}

private func entityTypesCanBeMembers(_ lhs: CedarSet<Name>, of rhs: CedarSet<Name>, schema: Schema) -> Bool {
    let possibleChildren = possibleRuntimeEntityTypes(for: lhs, schema: schema)
    let possibleAncestors = possibleRuntimeEntityTypes(for: rhs, schema: schema)

    for child in possibleChildren.elements {
        for ancestor in possibleAncestors.elements {
            if child == ancestor || isEntityDescendant(child, of: ancestor, schema: schema) {
                return true
            }
        }
    }

    return false
}

private func combineEntityAttributes(
    _ entityTypes: CedarSet<Name>,
    schema: Schema,
    mode: ValidationMode
) -> Result<CedarMap<Attr, ValidationQualifiedType>, TypecheckFailure> {
    guard let first = entityTypes.elements.first, let firstDefinition = schema.entityType(first) else {
        return .failure(.unknownEntityType(entityTypes.elements.first ?? Name(id: "")))
    }

    var combined = convertRecordType(firstDefinition.attributes)

    for entityType in entityTypes.elements.dropFirst() {
        guard let definition = schema.entityType(entityType) else {
            return .failure(.unknownEntityType(entityType))
        }

        let otherRecord = convertRecordType(definition.attributes)
        var entries: [(key: Attr, value: ValidationQualifiedType)] = []

        for entry in combined.entries {
            guard let other = otherRecord.find(entry.key),
                  let lub = leastUpperBound(entry.value.type, other.type, mode: mode)
            else {
                return .failure(.attrNotFound(.entity(entityTypes), entry.key))
            }

            entries.append((
                key: entry.key,
                value: ValidationQualifiedType(type: lub, required: entry.value.required && other.required)
            ))
        }

        combined = CedarMap.make(entries)
    }

    return .success(combined)
}

private func entityTagType(
    _ entityTypes: CedarSet<Name>,
    schema: Schema,
    mode: ValidationMode
) -> Result<ValidationType, TypecheckFailure> {
    guard !entityTypes.isEmpty else {
        return .failure(.tagNotAllowed(entityTypes))
    }

    var result: ValidationType?

    for entityType in entityTypes.elements {
        guard let definition = schema.entityType(entityType), let tagType = definition.tags else {
            return .failure(.tagNotAllowed(entityTypes))
        }

        let resolved = ValidationType.fromSchema(tagType)
        if let current = result {
            guard let lub = leastUpperBound(current, resolved, mode: mode) else {
                return .failure(.incompatibleTagTypes(entityTypes))
            }
            result = lub
        } else {
            result = resolved
        }
    }

    return .success(result ?? .bool(.any))
}

private func entityTypesSupportTags(_ entityTypes: CedarSet<Name>, schema: Schema) -> Bool {
    guard !entityTypes.isEmpty else {
        return false
    }

    for entityType in entityTypes.elements {
        guard let definition = schema.entityType(entityType), definition.tags != nil else {
            return false
        }
    }

    return true
}

private func capabilityBaseExpr(_ expr: Expr) -> Expr? {
    switch expr {
    case .variable:
        return expr
    case let .getAttr(value, attr):
        guard let base = capabilityBaseExpr(value) else {
            return nil
        }

        return .getAttr(base, attr)
    default:
        return nil
    }
}

private func attributeCapability(for expr: Expr, attr: Attr) -> ValidationCapability? {
    guard let base = capabilityBaseExpr(expr) else {
        return nil
    }

    return .attribute(base: base, attr: attr)
}

private func tagCapability(for expr: Expr, keyExpr: Expr) -> ValidationCapability? {
    guard let base = capabilityBaseExpr(expr),
          case let .lit(.prim(.string(key))) = keyExpr
    else {
        return nil
    }

    return .tag(base: base, key: key)
}

private func capabilitiesAssumingTrue(_ expr: Expr) -> Set<ValidationCapability> {
    switch expr {
    case let .hasAttr(value, attr):
        guard let capability = attributeCapability(for: value, attr: attr) else {
            return []
        }

        return [capability]
    case let .binaryApp(.hasTag, lhs, rhs):
        guard let capability = tagCapability(for: lhs, keyExpr: rhs) else {
            return []
        }

        return [capability]
    case let .binaryApp(.and, lhs, rhs):
        return capabilitiesAssumingTrue(lhs).union(capabilitiesAssumingTrue(rhs))
    case let .binaryApp(.equal, lhs, .lit(.prim(.bool(true)))):
        return capabilitiesAssumingTrue(lhs)
    case let .binaryApp(.equal, .lit(.prim(.bool(true))), rhs):
        return capabilitiesAssumingTrue(rhs)
    default:
        return []
    }
}

private func hasAttributeCapability(_ context: TypecheckContext, value: Expr, attr: Attr) -> Bool {
    guard let capability = attributeCapability(for: value, attr: attr) else {
        return false
    }

    return context.capabilities.contains(capability)
}

private func hasTagCapability(_ context: TypecheckContext, value: Expr, keyExpr: Expr) -> Bool {
    guard let capability = tagCapability(for: value, keyExpr: keyExpr) else {
        return false
    }

    return context.capabilities.contains(capability)
}

private func actionUIDLiteral(_ expr: TypedExpr, schema: Schema) -> EntityUID? {
    guard case let .lit(.prim(.entityUID(uid)), _) = expr, schema.action(uid) != nil else {
        return nil
    }

    return uid
}

private func actionUIDLiterals(_ expr: TypedExpr, schema: Schema) -> [EntityUID]? {
    if let uid = actionUIDLiteral(expr, schema: schema) {
        return [uid]
    }

    guard case let .set(values, _) = expr else {
        return nil
    }

    var actions: [EntityUID] = []
    actions.reserveCapacity(values.count)

    for value in values {
        guard let uid = actionUIDLiteral(value, schema: schema) else {
            return nil
        }

        actions.append(uid)
    }

    return actions
}

private func valueConforms(_ value: CedarValue, to type: ValidationType, schema: Schema) -> Bool {
    switch (value, type) {
    case (.prim(.bool), .bool):
        return true
    case (.prim(.int), .int):
        return true
    case (.prim(.string), .string):
        return true
    case let (.prim(.entityUID(uid)), .entity(expectedTypes)):
        return entityUIDConforms(uid, to: expectedTypes, schema: schema)
    case let (.set(values), .set(expectedElement)):
        guard let expectedElement else {
            return values.isEmpty
        }

        for element in values.elements where !valueConforms(element, to: expectedElement, schema: schema) {
            return false
        }

        return true
    case let (.record(record), .record(expectedRecord)):
        for entry in record {
            guard let expected = expectedRecord.find(entry.key), valueConforms(entry.value, to: expected.type, schema: schema) else {
                return false
            }
        }

        for expected in expectedRecord where expected.value.required && !record.contains(expected.key) {
            return false
        }

        return true
    case (.ext(.decimal), .ext(.decimal)),
         (.ext(.ipaddr), .ext(.ipaddr)),
         (.ext(.datetime), .ext(.datetime)),
         (.ext(.duration), .ext(.duration)):
        return true
    default:
        return false
    }
}

private func entityUIDConforms(_ uid: EntityUID, to expectedTypes: CedarSet<Name>, schema: Schema) -> Bool {
    guard knownEntity(uid, schema: schema) else {
        return false
    }

    for expectedType in expectedTypes.elements {
        if uid.ty == expectedType || isEntityDescendant(uid.ty, of: expectedType, schema: schema) {
            return true
        }
    }

    return false
}

private func requestExprConforms(_ expr: RestrictedExpr, to type: ValidationType, schema: Schema) -> Bool {
    switch (expr, type) {
    case (.bool, .bool):
        return true
    case (.int, .int):
        return true
    case (.string, .string):
        return true
    case (.bool, .int):
        return true
    case let (.entityUID(uid), .entity(expectedTypes)):
        return entityUIDConforms(uid, to: expectedTypes, schema: schema)
    case let (.set(values), .set(expectedElement)):
        guard let expectedElement else {
            return values.isEmpty
        }

        for value in values.elements where !requestExprConforms(value, to: expectedElement, schema: schema) {
            return false
        }

        return true
    case let (.record(record), .record(expectedRecord)):
        for entry in record {
            guard let expected = expectedRecord.find(entry.key),
                  requestExprConforms(entry.value, to: expected.type, schema: schema)
            else {
                return false
            }
        }

        for expected in expectedRecord where expected.value.required && !record.contains(expected.key) {
            return false
        }

        return true
    case let (.call(function, arguments), expectedType):
        switch RestrictedExpr.call(function, arguments).materialize() {
        case let .success(value):
            return valueConforms(value, to: expectedType, schema: schema)
        case .failure:
            return false
        }
    default:
        return false
    }
}

private func applicableEnvironments(for policy: Policy, schema: Schema, mode: ValidationMode) -> [TypeEnvironment] {
    environments(for: schema, mode: mode).filter {
        policyCompatible(with: $0, policy: policy, schema: schema)
    }
}

private func policyCompatible(with environment: TypeEnvironment, policy: Policy, schema: Schema) -> Bool {
    principalScopeCompatible(policy.principalScope, with: environment.requestType.principal, schema: schema)
        && actionScopeCompatible(policy.actionScope, with: environment.requestType.action, schema: schema)
        && resourceScopeCompatible(policy.resourceScope, with: environment.requestType.resource, schema: schema)
}

private func principalScopeCompatible(_ scope: PrincipalScope, with principalType: Name, schema: Schema) -> Bool {
    switch scope {
    case .any:
        return true
    case let .in(entity):
        return entityTypeCanBeMember(principalType, of: entity.ty, schema: schema)
    case let .eq(entity):
        return entityTypesCanOverlap(CedarSet.make([entity.ty]), CedarSet.make([principalType]), schema: schema)
    case let .isEntityType(entityType):
        return entityTypesCanOverlap(CedarSet.make([entityType]), CedarSet.make([principalType]), schema: schema)
    case let .isEntityTypeIn(entityType, entity):
        return entityTypeCanSatisfyScope(principalType, requiredType: entityType, ancestorType: entity.ty, schema: schema)
    }
}

private func resourceScopeCompatible(_ scope: ResourceScope, with resourceType: Name, schema: Schema) -> Bool {
    switch scope {
    case .any:
        return true
    case let .in(entity):
        return entityTypeCanBeMember(resourceType, of: entity.ty, schema: schema)
    case let .eq(entity):
        return entityTypesCanOverlap(CedarSet.make([entity.ty]), CedarSet.make([resourceType]), schema: schema)
    case let .isEntityType(entityType):
        return entityTypesCanOverlap(CedarSet.make([entityType]), CedarSet.make([resourceType]), schema: schema)
    case let .isEntityTypeIn(entityType, entity):
        return entityTypeCanSatisfyScope(resourceType, requiredType: entityType, ancestorType: entity.ty, schema: schema)
    }
}

private func entityTypeCanBeMember(_ candidate: Name, of ancestor: Name, schema: Schema) -> Bool {
    possibleRuntimeEntityTypes(for: candidate, schema: schema).elements.contains {
        $0 == ancestor || isEntityDescendant($0, of: ancestor, schema: schema)
    }
}

private func entityTypeCanSatisfyScope(
    _ candidate: Name,
    requiredType: Name,
    ancestorType: Name,
    schema: Schema
) -> Bool {
    let candidateTypes = possibleRuntimeEntityTypes(for: candidate, schema: schema)
    let requiredTypes = possibleRuntimeEntityTypes(for: requiredType, schema: schema)

    for actualType in candidateTypes.elements where requiredTypes.contains(actualType) {
        if actualType == ancestorType || isEntityDescendant(actualType, of: ancestorType, schema: schema) {
            return true
        }
    }

    return false
}

private func actionScopeCompatible(_ scope: ActionScope, with action: EntityUID, schema: Schema) -> Bool {
    switch scope {
    case .any:
        return true
    case let .eq(entity):
        return entity == action
    case let .in(entity):
        return actionEntityMatches(action, ancestor: entity, schema: schema)
    case let .isEntityType(entityType):
        return entityType == action.ty
    case let .isEntityTypeIn(entityType, entity):
        return entityType == action.ty && actionEntityMatches(action, ancestor: entity, schema: schema)
    case let .actionInAny(entities):
        return entities.any { actionEntityMatches(action, ancestor: $0, schema: schema) }
    }
}

private func actionEntityMatches(_ action: EntityUID, ancestor: EntityUID, schema: Schema) -> Bool {
    var remainingSteps = defaultEvaluationStepLimit
    switch inE(action, ancestor, entities: schemaActionEntities(schema), remainingSteps: &remainingSteps) {
    case let .success(result):
        return result
    case .failure:
        return false
    }
}

private func schemaActionEntities(_ schema: Schema) -> Entities {
    Entities(CedarMap.make(schema.actions.entries.map {
        (key: $0.key, value: EntityData(ancestors: $0.value.memberOf))
    }))
}

private func knownEntity(_ uid: EntityUID, schema: Schema) -> Bool {
    if schema.action(uid) != nil {
        return true
    }

    guard let definition = schema.entityType(uid.ty) else {
        return false
    }

    if let enumEntityIDs = definition.enumEntityIDs {
        return enumEntityIDs.contains(uid.eid)
    }

    return true
}

private func attributePresence(
    of type: ValidationType,
    attr: Attr,
    schema: Schema
) -> Result<ValidationBool, TypecheckFailure> {
    switch type {
    case let .record(record):
        guard let qualifiedType = record.find(attr) else {
            return .success(.ff)
        }

        return .success(qualifiedType.required ? .tt : .any)
    case let .entity(entityTypes):
        let possibleTypes = possibleRuntimeEntityTypes(for: entityTypes, schema: schema)
        var sawPresent = false
        var sawAbsent = false
        var allPresentRequired = true

        for entityType in possibleTypes.elements {
            guard let definition = schema.entityType(entityType), let qualifiedType = definition.attributes.find(attr) else {
                sawAbsent = true
                allPresentRequired = false
                continue
            }

            sawPresent = true
            if !qualifiedType.required {
                allPresentRequired = false
            }
        }

        guard sawPresent else {
            return .success(.ff)
        }

        return .success(!sawAbsent && allPresentRequired ? .tt : .any)
    default:
        return .failure(.unexpectedType(type, expected: "record or entity"))
    }
}

private func substituteAction(_ action: EntityUID, in expr: Expr) -> Expr {
    switch expr {
    case .lit:
        return expr
    case let .variable(variable):
        return variable == .action ? .lit(.prim(.entityUID(action))) : expr
    case let .unaryApp(op, value):
        return .unaryApp(op, substituteAction(action, in: value))
    case let .binaryApp(op, lhs, rhs):
        return .binaryApp(op, substituteAction(action, in: lhs), substituteAction(action, in: rhs))
    case let .ifThenElse(condition, thenExpr, elseExpr):
        return .ifThenElse(
            substituteAction(action, in: condition),
            substituteAction(action, in: thenExpr),
            substituteAction(action, in: elseExpr)
        )
    case let .set(values):
        return .set(values.map { substituteAction(action, in: $0) })
    case let .record(entries):
        return .record(entries.map { (key: $0.key, value: substituteAction(action, in: $0.value)) })
    case let .hasAttr(value, attr):
        return .hasAttr(substituteAction(action, in: value), attr)
    case let .getAttr(value, attr):
        return .getAttr(substituteAction(action, in: value), attr)
    case let .like(value, pattern):
        return .like(substituteAction(action, in: value), pattern)
    case let .isEntityType(value, entityType):
        return .isEntityType(substituteAction(action, in: value), entityType)
    case let .call(function, arguments):
        return .call(function, arguments.map { substituteAction(action, in: $0) })
    }
}

private func checkReferencedEntities(_ expr: Expr, schema: Schema, policyID: PolicyID) -> Diagnostics {
    switch expr {
    case let .lit(.prim(.entityUID(uid))):
        return knownEntity(uid, schema: schema)
            ? .empty
            : validationDiagnostic(code: "validation.unknownEntity", message: "Policy \(policyID) references unknown entity \(uid)")
    case let .unaryApp(_, value),
         let .hasAttr(value, _),
         let .getAttr(value, _),
         let .like(value, _):
        return checkReferencedEntities(value, schema: schema, policyID: policyID)
    case let .binaryApp(_, lhs, rhs):
        return checkReferencedEntities(lhs, schema: schema, policyID: policyID)
            .appending(contentsOf: checkReferencedEntities(rhs, schema: schema, policyID: policyID))
    case let .ifThenElse(condition, thenExpr, elseExpr):
        return checkReferencedEntities(condition, schema: schema, policyID: policyID)
            .appending(contentsOf: checkReferencedEntities(thenExpr, schema: schema, policyID: policyID))
            .appending(contentsOf: checkReferencedEntities(elseExpr, schema: schema, policyID: policyID))
    case let .set(values):
        var diagnostics = Diagnostics.empty
        for value in values {
            diagnostics = diagnostics.appending(contentsOf: checkReferencedEntities(value, schema: schema, policyID: policyID))
        }
        return diagnostics
    case let .record(entries):
        var diagnostics = Diagnostics.empty
        for entry in entries {
            diagnostics = diagnostics.appending(contentsOf: checkReferencedEntities(entry.value, schema: schema, policyID: policyID))
        }
        return diagnostics
    case let .isEntityType(value, entityType):
        let nested = checkReferencedEntities(value, schema: schema, policyID: policyID)
        if entityType == Name(id: "Action") || schema.entityType(entityType) != nil {
            return nested
        }
        return nested.appending(contentsOf: validationDiagnostic(
            code: "validation.unknownEntityType",
            message: "Policy \(policyID) references unknown entity type \(entityType)"
        ))
    case let .call(_, arguments):
        var diagnostics = Diagnostics.empty
        for argument in arguments {
            diagnostics = diagnostics.appending(contentsOf: checkReferencedEntities(argument, schema: schema, policyID: policyID))
        }
        return diagnostics
    case .lit, .variable:
        return .empty
    }
}

private func typecheck(_ expr: Expr, context: TypecheckContext) -> Result<TypedExpr, TypecheckFailure> {
    switch expr {
    case let .lit(value):
        return typecheckLiteral(value, environment: context.environment)
    case let .variable(variable):
        return .success(.variable(variable, variableType(variable, environment: context.environment)))
    case let .unaryApp(op, operand):
        switch typecheck(operand, context: context) {
        case let .success(typedOperand):
            switch unaryType(op, operand: typedOperand) {
            case let .success(type):
                return .success(.unaryApp(op, typedOperand, type))
            case let .failure(error):
                return .failure(error)
            }
        case let .failure(error):
            return .failure(error)
        }
    case let .binaryApp(.getTag, lhs, rhs):
        return typecheckGetTag(lhsExpr: lhs, rhsExpr: rhs, context: context)
    case let .binaryApp(op, lhs, rhs):
        switch typecheck(lhs, context: context) {
        case let .success(typedLHS):
            if case let .bool(lhsBool) = typedLHS.type {
                switch (op, lhsBool) {
                case (.and, .ff):
                    return .success(.lit(.prim(.bool(false)), .bool(.ff)))
                case (.or, .tt):
                    return .success(.lit(.prim(.bool(true)), .bool(.tt)))
                default:
                    break
                }
            }

            let rhsContext: TypecheckContext
            switch op {
            case .and:
                rhsContext = context.appending(capabilitiesAssumingTrue(lhs))
            default:
                rhsContext = context
            }

            switch typecheck(rhs, context: rhsContext) {
            case let .success(typedRHS):
                switch binaryType(op, lhsExpr: lhs, rhsExpr: rhs, lhs: typedLHS, rhs: typedRHS, context: context) {
                case let .success(type):
                    return .success(.binaryApp(op, typedLHS, typedRHS, type))
                case let .failure(error):
                    return .failure(error)
                }
            case let .failure(error):
                return .failure(error)
            }
        case let .failure(error):
            return .failure(error)
        }
    case let .ifThenElse(condition, thenExpr, elseExpr):
        switch typecheck(condition, context: context) {
        case let .success(typedCondition):
            guard isBoolean(typedCondition.type) else {
                return .failure(.unexpectedType(typedCondition.type, expected: "bool"))
            }

            if case .bool(.tt) = typedCondition.type {
                return typecheck(thenExpr, context: context.appending(capabilitiesAssumingTrue(condition)))
            }

            if case .bool(.ff) = typedCondition.type {
                return typecheck(elseExpr, context: context)
            }

            switch typecheck(thenExpr, context: context.appending(capabilitiesAssumingTrue(condition))) {
            case let .success(typedThen):
                switch typecheck(elseExpr, context: context) {
                case let .success(typedElse):
                    if context.environment.mode == .strict,
                       bothEntities(typedThen.type, typedElse.type),
                       !strictEntityTypesCompatible(typedThen.type, typedElse.type, schema: context.environment.schema)
                    {
                        return .failure(.unexpectedType(typedElse.type, expected: typeDescription(typedThen.type)))
                    }

                    guard let type = leastUpperBound(typedThen.type, typedElse.type, mode: context.environment.mode) else {
                        return .failure(.unexpectedType(typedElse.type, expected: typeDescription(typedThen.type)))
                    }

                    return .success(.ifThenElse(typedCondition, typedThen, typedElse, type))
                case let .failure(error):
                    return .failure(error)
                }
            case let .failure(error):
                return .failure(error)
            }
        case let .failure(error):
            return .failure(error)
        }
    case let .set(values):
        var typedValues: [TypedExpr] = []
        for value in values {
            switch typecheck(value, context: context) {
            case let .success(typedValue):
                typedValues.append(typedValue)
            case let .failure(error):
                return .failure(error)
            }
        }

        guard !typedValues.isEmpty else {
            if context.environment.mode == .permissive {
                return .success(.set(typedValues, .set(nil)))
            }

            return .failure(.emptySet)
        }

        let elementTypes = typedValues.map { $0.type }
        guard let inferred = inferSetElementType(
            elementTypes,
            mode: context.environment.mode,
            schema: context.environment.schema
        ) else {
            if context.environment.mode == .permissive {
                return .success(.set(typedValues, .set(nil)))
            }

            return .failure(.incompatibleSetTypes(elementTypes))
        }

        return .success(.set(typedValues, .set(inferred)))
    case let .record(entries):
        var typedEntries: [(key: Attr, value: TypedExpr)] = []
        for entry in entries {
            switch typecheck(entry.value, context: context) {
            case let .success(typedValue):
                typedEntries.append((key: entry.key, value: typedValue))
            case let .failure(error):
                return .failure(error)
            }
        }

        return .success(.record(
            typedEntries,
            .record(CedarMap.make(typedEntries.map {
                (key: $0.key, value: ValidationQualifiedType(type: $0.value.type.erased, required: true))
            }))
        ))
    case let .hasAttr(value, attr):
        switch typecheck(value, context: context) {
        case let .success(typedValue):
            switch attributePresence(of: typedValue.type, attr: attr, schema: context.environment.schema) {
            case let .success(result):
                return .success(.hasAttr(typedValue, attr, .bool(result)))
            case let .failure(error):
                return .failure(error)
            }
        case let .failure(error):
            return .failure(error)
        }
    case let .getAttr(value, attr):
        switch typecheck(value, context: context) {
        case let .success(typedValue):
            switch attributeBase(of: typedValue, schema: context.environment.schema, mode: context.environment.mode) {
            case let .success(recordType):
                guard let qualifiedType = recordType.find(attr) else {
                    return .failure(.attrNotFound(typedValue.type, attr))
                }
                if !qualifiedType.required, !hasAttributeCapability(context, value: value, attr: attr) {
                    return .failure(.unsafeOptionalAttributeAccess(typedValue.type, attr))
                }
                return .success(.getAttr(typedValue, attr, qualifiedType.type))
            case let .failure(error):
                return .failure(error)
            }
        case let .failure(error):
            return .failure(error)
        }
    case let .like(value, pattern):
        switch typecheck(value, context: context) {
        case let .success(typedValue):
            guard typedValue.type == ValidationType.string else {
                return .failure(.unexpectedType(typedValue.type, expected: "string"))
            }
            return .success(.like(typedValue, pattern, .bool(.any)))
        case let .failure(error):
            return .failure(error)
        }
    case let .isEntityType(value, entityType):
        switch typecheck(value, context: context) {
        case let .success(typedValue):
            guard case let .entity(actualTypes) = typedValue.type else {
                return .failure(.unexpectedType(typedValue.type, expected: "entity"))
            }
            let possibleTypes = possibleRuntimeEntityTypes(for: actualTypes, schema: context.environment.schema)
            let matchingTypes = possibleTypes.elements.filter {
                $0 == entityType || isEntityDescendant($0, of: entityType, schema: context.environment.schema)
            }
            let result: ValidationBool
            if matchingTypes.isEmpty {
                result = .ff
            } else if matchingTypes.count == possibleTypes.count {
                result = .tt
            } else {
                result = .any
            }
            return .success(.isEntityType(typedValue, entityType, .bool(result)))
        case let .failure(error):
            return .failure(error)
        }
    case let .call(function, arguments):
        var typedArguments: [TypedExpr] = []
        for argument in arguments {
            switch typecheck(argument, context: context) {
            case let .success(typedArgument):
                typedArguments.append(typedArgument)
            case let .failure(error):
                return .failure(error)
            }
        }

        switch validateExtensionCall(
            function,
            originalArguments: arguments,
            mode: context.environment.mode
        ) {
        case .success:
            break
        case let .failure(error):
            return .failure(error)
        }

        switch callType(function, arguments: typedArguments.map { $0.type }, mode: context.environment.mode) {
        case let .success(type):
            return .success(.call(function, typedArguments, type))
        case let .failure(error):
            return .failure(error)
        }
    }
}

private func typecheckLiteral(_ value: CedarValue, environment: TypeEnvironment) -> Result<TypedExpr, TypecheckFailure> {
    switch value {
    case let .prim(.bool(booleanValue)):
        return .success(.lit(value, .bool(booleanValue ? .tt : .ff)))
    case .prim(.int):
        return .success(.lit(value, .int))
    case .prim(.string):
        return .success(.lit(value, .string))
    case let .prim(.entityUID(uid)):
        guard knownEntity(uid, schema: environment.schema) else {
            return .failure(.unknownEntity(uid))
        }
        return .success(.lit(value, .singleEntity(uid.ty)))
    case let .set(values):
        return typecheck(.set(values.elements.map { .lit($0) }), context: TypecheckContext(environment: environment))
    case let .record(record):
        return typecheck(.record(record.entries.map { (key: $0.key, value: .lit($0.value)) }), context: TypecheckContext(environment: environment))
    case let .ext(.decimal(payload)):
        guard decimalPayloadIsSupported(payload) else {
            return .failure(.invalidExtensionCall(.decimal))
        }
        return .success(.lit(value, .ext(.decimal)))
    case let .ext(.ipaddr(payload)):
        guard ipaddrPayloadIsSupported(payload) else {
            return .failure(.invalidExtensionCall(.ip))
        }
        return .success(.lit(value, .ext(.ipaddr)))
    case let .ext(.datetime(payload)):
        guard datetimePayloadIsSupported(payload) else {
            return .failure(.invalidExtensionCall(.datetime))
        }
        return .success(.lit(value, .ext(.datetime)))
    case let .ext(.duration(payload)):
        guard durationPayloadIsSupported(payload) else {
            return .failure(.invalidExtensionCall(.duration))
        }
        return .success(.lit(value, .ext(.duration)))
    }
}

private func variableType(_ variable: Var, environment: TypeEnvironment) -> ValidationType {
    switch variable {
    case .principal:
        return .singleEntity(environment.requestType.principal)
    case .action:
        return .singleEntity(environment.requestType.action.ty)
    case .resource:
        return .singleEntity(environment.requestType.resource)
    case .context:
        return .record(environment.requestType.context)
    }
}

private func unaryType(_ op: UnaryOp, operand: TypedExpr) -> Result<ValidationType, TypecheckFailure> {
    switch (op, operand.type) {
    case let (.not, .bool(booleanType)):
        return .success(.bool(booleanType.logicalNot()))
    case (.neg, .int):
        return .success(.int)
    case (.isEmpty, .set):
        return .success(.bool(.any))
    default:
        return .failure(.unexpectedType(operand.type, expected: "valid unary operand"))
    }
}

private func binaryType(
    _ op: BinaryOp,
    lhsExpr: Expr,
    rhsExpr: Expr,
    lhs: TypedExpr,
    rhs: TypedExpr,
    context: TypecheckContext
) -> Result<ValidationType, TypecheckFailure> {
    switch op {
    case .and:
        guard case let .bool(left) = lhs.type, case let .bool(right) = rhs.type else {
            return .failure(.unexpectedType(lhs.type, expected: "bool"))
        }
        if left == .ff || right == .ff { return .success(.bool(.ff)) }
        if left == .tt && right == .tt { return .success(.bool(.tt)) }
        return .success(.bool(.any))
    case .or:
        guard case let .bool(left) = lhs.type, case let .bool(right) = rhs.type else {
            return .failure(.unexpectedType(lhs.type, expected: "bool"))
        }
        if left == .tt || right == .tt { return .success(.bool(.tt)) }
        if left == .ff && right == .ff { return .success(.bool(.ff)) }
        return .success(.bool(.any))
    case .equal:
        if case let .lit(leftValue, _) = lhs, case let .lit(rightValue, _) = rhs {
            return .success(.bool(leftValue == rightValue ? .tt : .ff))
        }
        if case let .entity(left) = lhs.type,
           case let .entity(right) = rhs.type,
           !entityTypesCanOverlap(left, right, schema: context.environment.schema)
        {
            return .success(.bool(.ff))
        }
        if context.environment.mode == .permissive {
            return .success(.bool(.any))
        }
        guard leastUpperBound(lhs.type, rhs.type, mode: context.environment.mode) != nil else {
            return .failure(.unexpectedType(rhs.type, expected: typeDescription(lhs.type)))
        }
        return .success(.bool(.any))
    case .lessThan, .lessThanOrEqual:
        switch (lhs.type, rhs.type) {
        case (.int, .int), (.ext(.datetime), .ext(.datetime)), (.ext(.duration), .ext(.duration)):
            return .success(.bool(.any))
        default:
            return .failure(.unexpectedType(rhs.type, expected: typeDescription(lhs.type)))
        }
    case .add, .sub, .mul:
        guard lhs.type == .int, rhs.type == .int else {
            return .failure(.unexpectedType(rhs.type, expected: "int"))
        }
        return .success(.int)
    case .in:
        guard case let .entity(lhsEntityTypes) = lhs.type else {
            return .failure(.unexpectedType(lhs.type, expected: "entity"))
        }

        if let lhsAction = actionUIDLiteral(lhs, schema: context.environment.schema),
           let rhsActions = actionUIDLiterals(rhs, schema: context.environment.schema)
        {
            let matches = rhsActions.contains { actionEntityMatches(lhsAction, ancestor: $0, schema: context.environment.schema) }
            return .success(.bool(matches ? .tt : .ff))
        }

        switch rhs.type {
        case let .entity(rhsEntityTypes):
            guard entityTypesCanBeMembers(lhsEntityTypes, of: rhsEntityTypes, schema: context.environment.schema) else {
                return .failure(.impossiblePolicy)
            }
            return .success(.bool(.any))
        case let .set(elementType):
            guard let elementType else {
                return .success(.bool(.ff))
            }
            if case let .entity(rhsEntityTypes) = elementType {
                guard entityTypesCanBeMembers(lhsEntityTypes, of: rhsEntityTypes, schema: context.environment.schema) else {
                    return .failure(.impossiblePolicy)
                }
                return .success(.bool(.any))
            }
            return .failure(.unexpectedType(rhs.type, expected: "entity or set<entity>"))
        default:
            return .failure(.unexpectedType(rhs.type, expected: "entity or set<entity>"))
        }
    case .contains:
        guard case let .set(containerType) = lhs.type else {
            return .failure(.unexpectedType(lhs.type, expected: "set"))
        }
        if context.environment.mode == .strict,
           let containerType,
           !strictEntityTypesCompatible(containerType, rhs.type, schema: context.environment.schema)
        {
            return .failure(.unexpectedType(rhs.type, expected: typeDescription(containerType)))
        }
        if context.environment.mode == .permissive {
            return .success(.bool(.any))
        }
        if let containerType, leastUpperBound(containerType, rhs.type, mode: context.environment.mode) == nil {
            return .failure(.unexpectedType(rhs.type, expected: typeDescription(containerType)))
        }
        return .success(.bool(.any))
    case .containsAll, .containsAny:
        guard case let .set(leftType) = lhs.type, case let .set(rightType) = rhs.type else {
            return .failure(.unexpectedType(rhs.type, expected: "set"))
        }
        if context.environment.mode == .strict,
           let leftType,
           let rightType,
           !strictEntityTypesCompatible(leftType, rightType, schema: context.environment.schema)
        {
            return .failure(.incompatibleSetTypes([leftType, rightType]))
        }
        if context.environment.mode == .permissive {
            return .success(.bool(.any))
        }
        if let leftType, let rightType, leastUpperBound(leftType, rightType, mode: context.environment.mode) == nil {
            return .failure(.incompatibleSetTypes([leftType, rightType]))
        }
        return .success(.bool(.any))
    case .hasTag:
        guard case let .entity(entityTypes) = lhs.type, rhs.type == .string else {
            return .failure(.unexpectedType(lhs.type, expected: "entity and string"))
        }
        guard entityTypesSupportTags(entityTypes, schema: context.environment.schema) else {
            return .failure(.impossiblePolicy)
        }
        return .success(.bool(.any))
    case .getTag:
        guard case let .entity(entityTypes) = lhs.type, rhs.type == .string else {
            return .failure(.unexpectedType(lhs.type, expected: "entity and string"))
        }
        switch entityTagType(entityTypes, schema: context.environment.schema, mode: context.environment.mode) {
        case let .success(tagType):
            guard hasTagCapability(context, value: lhsExpr, keyExpr: rhsExpr) else {
                return .failure(.unsafeTagAccess(entityTypes, emitCedar(rhsExpr)))
            }
            return .success(tagType)
        case let .failure(error):
            return .failure(error)
        }
    }
}

private func typecheckGetTag(
    lhsExpr: Expr,
    rhsExpr: Expr,
    context: TypecheckContext
) -> Result<TypedExpr, TypecheckFailure> {
    let typedRHS: TypedExpr
    switch typecheck(rhsExpr, context: context) {
    case let .success(value):
        typedRHS = value
    case let .failure(error):
        return .failure(error)
    }

    let typedLHS: TypedExpr
    if case let .ifThenElse(condition, thenExpr, elseExpr) = lhsExpr {
        switch typecheck(condition, context: context) {
        case let .success(typedCondition):
            guard isBoolean(typedCondition.type) else {
                return .failure(.unexpectedType(typedCondition.type, expected: "bool"))
            }

            if case .bool(.tt) = typedCondition.type {
                switch typecheck(thenExpr, context: context.appending(capabilitiesAssumingTrue(condition))) {
                case let .success(value):
                    typedLHS = value
                case let .failure(error):
                    return .failure(error)
                }
            } else if case .bool(.ff) = typedCondition.type {
                switch typecheck(elseExpr, context: context) {
                case let .success(value):
                    typedLHS = value
                case let .failure(error):
                    return .failure(error)
                }
            } else {
                let typedThen: TypedExpr
                switch typecheck(thenExpr, context: context.appending(capabilitiesAssumingTrue(condition))) {
                case let .success(value):
                    typedThen = value
                case let .failure(error):
                    return .failure(error)
                }

                let typedElse: TypedExpr
                switch typecheck(elseExpr, context: context) {
                case let .success(value):
                    typedElse = value
                case let .failure(error):
                    return .failure(error)
                }

                if case let .entity(thenTypes) = typedThen.type,
                   case let .entity(elseTypes) = typedElse.type
                {
                    typedLHS = .ifThenElse(
                        typedCondition,
                        typedThen,
                        typedElse,
                        .entity(CedarSet.make(thenTypes.elements + elseTypes.elements))
                    )
                } else {
                    switch typecheck(lhsExpr, context: context) {
                    case let .success(value):
                        typedLHS = value
                    case let .failure(error):
                        return .failure(error)
                    }
                }
            }
        case let .failure(error):
            return .failure(error)
        }
    } else {
        switch typecheck(lhsExpr, context: context) {
        case let .success(value):
            typedLHS = value
        case let .failure(error):
            return .failure(error)
        }
    }

    switch binaryType(.getTag, lhsExpr: lhsExpr, rhsExpr: rhsExpr, lhs: typedLHS, rhs: typedRHS, context: context) {
    case let .success(type):
        return .success(.binaryApp(.getTag, typedLHS, typedRHS, type))
    case let .failure(error):
        return .failure(error)
    }
}

private func callType(_ function: ExtFun, arguments: [ValidationType], mode: ValidationMode) -> Result<ValidationType, TypecheckFailure> {
    func match(_ expected: [ValidationType], returning result: ValidationType) -> Result<ValidationType, TypecheckFailure> {
        guard arguments.count == expected.count else {
            return .failure(.invalidExtensionCall(function))
        }

        for (actual, required) in zip(arguments, expected) where !isSubtype(actual, of: required, mode: mode) {
            return .failure(.invalidExtensionCall(function))
        }

        return .success(result)
    }

    switch function {
    case .decimal:
        return match([.string], returning: .ext(.decimal))
    case .ip:
        return match([.string], returning: .ext(.ipaddr))
    case .datetime:
        return match([.string], returning: .ext(.datetime))
    case .duration:
        return match([.string], returning: .ext(.duration))
    case .lessThan, .lessThanOrEqual, .greaterThan, .greaterThanOrEqual:
        return match([.ext(.decimal), .ext(.decimal)], returning: .bool(.any))
    case .isIpv4, .isIpv6, .isLoopback, .isMulticast:
        return match([.ext(.ipaddr)], returning: .bool(.any))
    case .isInRange:
        return match([.ext(.ipaddr), .ext(.ipaddr)], returning: .bool(.any))
    case .offset:
        return match([.ext(.datetime), .ext(.duration)], returning: .ext(.datetime))
    case .durationSince:
        return match([.ext(.datetime), .ext(.datetime)], returning: .ext(.duration))
    case .toDate:
        return match([.ext(.datetime)], returning: .ext(.datetime))
    case .toTime:
        return match([.ext(.datetime)], returning: .ext(.duration))
    case .toMilliseconds, .toSeconds, .toMinutes, .toHours, .toDays:
        return match([.ext(.duration)], returning: .int)
    }
}

private func validateExtensionCall(
    _ function: ExtFun,
    originalArguments: [Expr],
    mode: ValidationMode
) -> Result<Void, TypecheckFailure> {
    func singleLiteralString() -> String? {
        guard originalArguments.count == 1,
              case let .lit(.prim(.string(rawValue))) = originalArguments[0]
        else {
            return nil
        }

        return rawValue
    }

    switch function {
    case .decimal:
        if mode == .strict, singleLiteralString() == nil {
            return .failure(.invalidExtensionCall(function))
        }
        guard let rawValue = singleLiteralString() else {
            return .success(())
        }
        return decimalParse(rawValue) != nil ? .success(()) : .failure(.invalidExtensionCall(function))
    case .ip:
        if mode == .strict, singleLiteralString() == nil {
            return .failure(.invalidExtensionCall(function))
        }
        guard let rawValue = singleLiteralString() else {
            return .success(())
        }
        return ipaddrParse(rawValue) != nil ? .success(()) : .failure(.invalidExtensionCall(function))
    case .datetime:
        if mode == .strict, singleLiteralString() == nil {
            return .failure(.invalidExtensionCall(function))
        }
        guard let rawValue = singleLiteralString() else {
            return .success(())
        }
        return datetimeParse(rawValue) != nil ? .success(()) : .failure(.invalidExtensionCall(function))
    case .duration:
        if mode == .strict, singleLiteralString() == nil {
            return .failure(.invalidExtensionCall(function))
        }
        guard let rawValue = singleLiteralString() else {
            return .success(())
        }
        return durationParse(rawValue) != nil ? .success(()) : .failure(.invalidExtensionCall(function))
    default:
        return .success(())
    }
}

private func attributeBase(
    of expr: TypedExpr,
    schema: Schema,
    mode: ValidationMode
) -> Result<CedarMap<Attr, ValidationQualifiedType>, TypecheckFailure> {
    switch expr.type {
    case let .record(record):
        return .success(record)
    case let .entity(entityTypes):
        return combineEntityAttributes(entityTypes, schema: schema, mode: mode)
    default:
        return .failure(.unexpectedType(expr.type, expected: "record or entity"))
    }
}

private func inferSetElementType(_ elementTypes: [ValidationType], mode: ValidationMode, schema: Schema) -> ValidationType? {
    guard var current = elementTypes.first else {
        return nil
    }

    for elementType in elementTypes.dropFirst() {
        if mode == .strict, !strictEntityTypesCompatible(current, elementType, schema: schema) {
            return nil
        }
        guard let lub = leastUpperBound(current, elementType, mode: mode) else {
            return nil
        }
        current = lub
    }

    return current
}

private func leastUpperBound(_ lhs: ValidationType, _ rhs: ValidationType, mode: ValidationMode) -> ValidationType? {
    switch (lhs, rhs) {
    case let (.bool(left), .bool(right)):
        return .bool(left == right ? left : .any)
    case (.int, .int):
        return .int
    case (.string, .string):
        return .string
    case let (.entity(left), .entity(right)):
        return .entity(CedarSet.make(left.elements + right.elements))
    case let (.set(left), .set(right)):
        switch (left, right) {
        case (.none, .none):
            return .set(nil)
        case let (.some(leftType), .some(rightType)):
            guard let lub = leastUpperBound(leftType, rightType, mode: mode) else {
                return nil
            }
            return .set(lub)
        case let (.some(type), .none), let (.none, .some(type)):
            return .set(type)
        }
    case let (.record(left), .record(right)):
        if mode == .strict {
            guard left.count == right.count else {
                return nil
            }

            var entries: [(key: Attr, value: ValidationQualifiedType)] = []
            for (leftEntry, rightEntry) in zip(left.entries, right.entries) {
                guard cedarStringEqual(leftEntry.key, rightEntry.key), leftEntry.value.required == rightEntry.value.required,
                      let lub = leastUpperBound(leftEntry.value.type, rightEntry.value.type, mode: mode)
                else {
                    return nil
                }

                entries.append((key: leftEntry.key, value: ValidationQualifiedType(type: lub, required: leftEntry.value.required)))
            }

            return .record(CedarMap.make(entries))
        }

        let keys = CedarSet.make(left.entries.map(\.key) + right.entries.map(\.key))
        var entries: [(key: Attr, value: ValidationQualifiedType)] = []

        for key in keys.elements {
            switch (left.find(key), right.find(key)) {
            case let (.some(leftValue), .some(rightValue)):
                guard let lub = leastUpperBound(leftValue.type, rightValue.type, mode: mode) else {
                    return nil
                }

                entries.append((
                    key: key,
                    value: ValidationQualifiedType(type: lub, required: leftValue.required && rightValue.required)
                ))
            case let (.some(value), .none), let (.none, .some(value)):
                entries.append((
                    key: key,
                    value: ValidationQualifiedType(type: value.type, required: false)
                ))
            case (.none, .none):
                break
            }
        }

        return .record(CedarMap.make(entries))
    case let (.ext(left), .ext(right)):
        return left == right ? .ext(left) : nil
    default:
        return nil
    }
}

private func isSubtype(_ lhs: ValidationType, of rhs: ValidationType, mode: ValidationMode) -> Bool {
    switch (lhs, rhs) {
    case (.bool, .bool(.any)):
        return true
    default:
        return leastUpperBound(lhs, rhs, mode: mode) == rhs
    }
}

private func bothEntities(_ lhs: ValidationType, _ rhs: ValidationType) -> Bool {
    if case .entity = lhs, case .entity = rhs {
        return true
    }

    return false
}

private func isBoolean(_ type: ValidationType) -> Bool {
    if case .bool = type {
        return true
    }

    return false
}

private func typeDescription(_ type: ValidationType) -> String {
    switch type {
    case .bool:
        return "bool"
    case .int:
        return "int"
    case .string:
        return "string"
    case let .entity(names):
        if let first = names.elements.first, names.count == 1 {
            return "entity<\(first)>"
        }
        return "entity<\(names.elements.map(String.init(describing:)).joined(separator: " | "))>"
    case .set:
        return "set"
    case .record:
        return "record"
    case let .ext(extType):
        switch extType {
        case .decimal: return "decimal"
        case .ipaddr: return "ipaddr"
        case .datetime: return "datetime"
        case .duration: return "duration"
        }
    }
}

private func typecheckDiagnostics(_ error: TypecheckFailure, policyID: PolicyID) -> Diagnostics {
    switch error {
    case .impossiblePolicy:
        return validationDiagnostic(code: "validation.impossiblePolicy", message: "Policy \(policyID) is impossible under the schema")
    case let .unknownEntity(uid):
        return validationDiagnostic(code: "validation.unknownEntity", message: "Policy \(policyID) references unknown entity \(uid)")
    case let .unknownEntityType(entityType):
        return validationDiagnostic(code: "validation.unknownEntityType", message: "Policy \(policyID) references unknown entity type \(entityType)")
    case let .unexpectedType(actual, expected):
        return validationDiagnostic(code: "validation.unexpectedType", message: "Policy \(policyID) uses type \(typeDescription(actual)) where \(expected) is required")
    case let .attrNotFound(type, attr):
        return validationDiagnostic(code: "validation.attrNotFound", message: "Policy \(policyID) cannot access attribute '\(attr)' on \(typeDescription(type))")
    case let .tagNotAllowed(entityTypes):
        return validationDiagnostic(
            code: "validation.tagNotFound",
            message: "Policy \(policyID) cannot access tags on entity type \(entityTypes.elements.map(String.init(describing:)).joined(separator: ", "))"
        )
    case let .incompatibleTagTypes(entityTypes):
        return validationDiagnostic(
            code: "validation.incompatibleTagTypes",
            message: "Policy \(policyID) mixes incompatible tag types across entity types \(entityTypes.elements.map(String.init(describing:)).joined(separator: ", "))"
        )
    case let .unsafeOptionalAttributeAccess(type, attr):
        return validationDiagnostic(
            code: "validation.unsafeOptionalAttributeAccess",
            message: "Policy \(policyID) cannot safely access optional attribute '\(attr)' on \(typeDescription(type)) without a matching has check"
        )
    case let .unsafeTagAccess(entityTypes, renderedTagExpr):
        let typeList = entityTypes.elements.map(String.init(describing:)).joined(separator: ", ")
        return validationDiagnostic(
            code: "validation.unsafeTagAccess",
            message: "Policy \(policyID) cannot safely access tag \(renderedTagExpr) on entity type \(typeList) without a matching hasTag check"
        )
    case .emptySet:
        return validationDiagnostic(code: "validation.emptySet", message: "Policy \(policyID) contains an empty set with no inferrable element type")
    case let .incompatibleSetTypes(types):
        return validationDiagnostic(code: "validation.incompatibleSetTypes", message: "Policy \(policyID) mixes incompatible set element types: \(types.map(typeDescription).joined(separator: ", "))")
    case let .invalidExtensionCall(function):
        return validationDiagnostic(code: "validation.extensionError", message: "Policy \(policyID) uses invalid arguments for extension function \(function)")
    }
}

private func checkLevel(_ expr: TypedExpr, environment: TypeEnvironment, remainingLevel: Int) -> Bool {
    switch expr {
    case .lit, .variable:
        return true
    case let .unaryApp(_, value, _),
         let .hasAttr(value, _, _),
         let .like(value, _, _),
         let .isEntityType(value, _, _):
        return checkLevel(value, environment: environment, remainingLevel: remainingLevel)
    case let .binaryApp(op, lhs, rhs, _):
        switch op {
        case .in, .hasTag, .getTag:
            return remainingLevel > 0
                && checkEntityAccessLevel(lhs, environment: environment, remainingLevel: remainingLevel - 1, maxLevel: remainingLevel, path: [])
                && checkLevel(rhs, environment: environment, remainingLevel: remainingLevel)
        default:
            return checkLevel(lhs, environment: environment, remainingLevel: remainingLevel)
                && checkLevel(rhs, environment: environment, remainingLevel: remainingLevel)
        }
    case let .ifThenElse(condition, thenExpr, elseExpr, _):
        return checkLevel(condition, environment: environment, remainingLevel: remainingLevel)
            && checkLevel(thenExpr, environment: environment, remainingLevel: remainingLevel)
            && checkLevel(elseExpr, environment: environment, remainingLevel: remainingLevel)
    case let .set(values, _):
        return values.allSatisfy { checkLevel($0, environment: environment, remainingLevel: remainingLevel) }
    case let .record(entries, _):
        return entries.allSatisfy { checkLevel($0.value, environment: environment, remainingLevel: remainingLevel) }
    case let .getAttr(value, _, _):
        if case .entity = value.type {
            return remainingLevel > 0
                && checkEntityAccessLevel(value, environment: environment, remainingLevel: remainingLevel - 1, maxLevel: remainingLevel, path: [])
        }

        return checkLevel(value, environment: environment, remainingLevel: remainingLevel)
    case let .call(_, arguments, _):
        return arguments.allSatisfy { checkLevel($0, environment: environment, remainingLevel: remainingLevel) }
    }
}

private func checkEntityAccessLevel(
    _ expr: TypedExpr,
    environment: TypeEnvironment,
    remainingLevel: Int,
    maxLevel: Int,
    path: [Attr]
) -> Bool {
    switch expr {
    case .variable:
        return true
    case let .lit(.prim(.entityUID(uid)), _):
        return uid == environment.requestType.action
    case let .ifThenElse(condition, thenExpr, elseExpr, _):
        return checkLevel(condition, environment: environment, remainingLevel: maxLevel)
            && checkEntityAccessLevel(thenExpr, environment: environment, remainingLevel: remainingLevel, maxLevel: maxLevel, path: path)
            && checkEntityAccessLevel(elseExpr, environment: environment, remainingLevel: remainingLevel, maxLevel: maxLevel, path: path)
    case let .getAttr(value, attr, _):
        if case .entity = value.type {
            return remainingLevel > 0
                && checkEntityAccessLevel(value, environment: environment, remainingLevel: remainingLevel - 1, maxLevel: maxLevel, path: [])
        }

        var nextPath = path
        nextPath.insert(attr, at: 0)
        return checkEntityAccessLevel(value, environment: environment, remainingLevel: remainingLevel, maxLevel: maxLevel, path: nextPath)
    case let .binaryApp(.getTag, value, tag, _):
        return remainingLevel > 0
            && checkEntityAccessLevel(value, environment: environment, remainingLevel: remainingLevel - 1, maxLevel: maxLevel, path: [])
            && checkLevel(tag, environment: environment, remainingLevel: maxLevel)
    case let .record(entries, _):
        guard let head = path.first else {
            return false
        }
        guard let target = entries.first(where: { cedarStringEqual($0.key, head) }) else {
            return false
        }

        return checkEntityAccessLevel(
            target.value,
            environment: environment,
            remainingLevel: remainingLevel,
            maxLevel: maxLevel,
            path: Array(path.dropFirst())
        ) && entries.allSatisfy { checkLevel($0.value, environment: environment, remainingLevel: maxLevel) }
    default:
        return false
    }
}
