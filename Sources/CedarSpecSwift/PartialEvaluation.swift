public struct EntitySlice: Equatable, Sendable {
    public let required: CedarSet<EntityUID>
    public let entities: Entities

    public init(required: CedarSet<EntityUID>, entities: Entities) {
        self.required = required
        self.entities = entities
    }
}

public func partialEvaluate(
    _ expr: Expr,
    request: Request,
    entities: Entities,
    unknowns: CedarSet<Var> = .empty,
    maxSteps: Int = 512
) -> CedarResult<Expr> {
    var residualizer = Residualizer(
        request: request,
        entities: entities,
        unknowns: unknowns,
        remainingSteps: maxSteps
    )
    return residualizer.residualize(expr)
}

public func partialEvaluate(
    _ policy: Policy,
    request: Request,
    entities: Entities,
    unknowns: CedarSet<Var> = .empty,
    maxSteps: Int = 512
) -> CedarResult<Policy?> {
    var residualizer = Residualizer(
        request: request,
        entities: entities,
        unknowns: unknowns,
        remainingSteps: maxSteps
    )
    return residualizer.residualize(policy)
}

public func partialEvaluate(
    _ policies: Policies,
    request: Request,
    entities: Entities,
    unknowns: CedarSet<Var> = .empty,
    maxSteps: Int = 512
) -> CedarResult<Policies> {
    var residualPolicies: [(key: PolicyID, value: Policy)] = []
    residualPolicies.reserveCapacity(policies.count)

    for entry in policies {
        switch partialEvaluate(entry.value, request: request, entities: entities, unknowns: unknowns, maxSteps: maxSteps) {
        case let .success(.some(policy)):
            residualPolicies.append((key: entry.key, value: policy))
        case .success(.none):
            continue
        case let .failure(error):
            return .failure(error)
        }
    }

    return .success(CedarMap.make(residualPolicies))
}

public func partialEvaluate(
    _ template: Template,
    request: Request,
    entities: Entities,
    unknowns: CedarSet<Var> = .empty,
    maxSteps: Int = 512
) -> CedarResult<Template?> {
    var residualizer = Residualizer(
        request: request,
        entities: entities,
        unknowns: unknowns,
        remainingSteps: maxSteps
    )
    return residualizer.residualize(template)
}

public func partialEvaluate(
    _ templates: Templates,
    request: Request,
    entities: Entities,
    unknowns: CedarSet<Var> = .empty,
    maxSteps: Int = 512
) -> CedarResult<Templates> {
    var residualTemplates: [(key: TemplateID, value: Template)] = []
    residualTemplates.reserveCapacity(templates.count)

    for entry in templates {
        switch partialEvaluate(entry.value, request: request, entities: entities, unknowns: unknowns, maxSteps: maxSteps) {
        case let .success(.some(template)):
            residualTemplates.append((key: entry.key, value: template))
        case .success(.none):
            continue
        case let .failure(error):
            return .failure(error)
        }
    }

    return .success(CedarMap.make(residualTemplates))
}

public func entityManifest(
    for expr: Expr,
    request: Request,
    entities: Entities,
    maxSteps: Int = 512
) -> CedarResult<CedarSet<EntityUID>> {
    switch sliceEntities(for: expr, request: request, entities: entities, maxSteps: maxSteps) {
    case let .success(slice):
        return .success(slice.required)
    case let .failure(error):
        return .failure(error)
    }
}

public func entityManifest(
    for policy: Policy,
    request: Request,
    entities: Entities,
    maxSteps: Int = 512
) -> CedarResult<CedarSet<EntityUID>> {
    entityManifest(for: policy.toExpr(), request: request, entities: entities, maxSteps: maxSteps)
}

public func entityManifest(
    for policies: Policies,
    request: Request,
    entities: Entities,
    maxSteps: Int = 512
) -> CedarResult<CedarSet<EntityUID>> {
    switch sliceEntities(for: policies, request: request, entities: entities, maxSteps: maxSteps) {
    case let .success(slice):
        return .success(slice.required)
    case let .failure(error):
        return .failure(error)
    }
}

public func entityManifestForPartialEvaluation(
    _ expr: Expr,
    request: Request,
    entities: Entities,
    unknowns: CedarSet<Var> = .empty,
    maxSteps: Int = 512
) -> CedarResult<CedarSet<EntityUID>> {
    switch sliceEntitiesForPartialEvaluation(of: expr, request: request, entities: entities, unknowns: unknowns, maxSteps: maxSteps) {
    case let .success(slice):
        return .success(slice.required)
    case let .failure(error):
        return .failure(error)
    }
}

public func entityManifestForPartialEvaluation(
    _ policy: Policy,
    request: Request,
    entities: Entities,
    unknowns: CedarSet<Var> = .empty,
    maxSteps: Int = 512
) -> CedarResult<CedarSet<EntityUID>> {
    switch sliceEntitiesForPartialEvaluation(of: policy, request: request, entities: entities, unknowns: unknowns, maxSteps: maxSteps) {
    case let .success(slice):
        return .success(slice.required)
    case let .failure(error):
        return .failure(error)
    }
}

public func entityManifestForPartialEvaluation(
    _ policies: Policies,
    request: Request,
    entities: Entities,
    unknowns: CedarSet<Var> = .empty,
    maxSteps: Int = 512
) -> CedarResult<CedarSet<EntityUID>> {
    switch sliceEntitiesForPartialEvaluation(of: policies, request: request, entities: entities, unknowns: unknowns, maxSteps: maxSteps) {
    case let .success(slice):
        return .success(slice.required)
    case let .failure(error):
        return .failure(error)
    }
}

public func sliceEntities(
    for expr: Expr,
    request: Request,
    entities: Entities,
    maxSteps: Int = 512
) -> CedarResult<EntitySlice> {
    var residualizer = Residualizer(
        request: request,
        entities: entities,
        unknowns: .empty,
        remainingSteps: maxSteps
    )

    switch residualizer.residualize(expr) {
    case .success:
        return .success(makeEntitySlice(required: residualizer.accessedEntities, from: entities))
    case let .failure(error):
        return .failure(error)
    }
}

public func sliceEntities(
    for policy: Policy,
    request: Request,
    entities: Entities,
    maxSteps: Int = 512
) -> CedarResult<EntitySlice> {
    sliceEntities(for: policy.toExpr(), request: request, entities: entities, maxSteps: maxSteps)
}

public func sliceEntities(
    for policies: Policies,
    request: Request,
    entities: Entities,
    maxSteps: Int = 512
) -> CedarResult<EntitySlice> {
    var required: [EntityUID] = []

    for entry in policies {
        switch sliceEntities(for: entry.value, request: request, entities: entities, maxSteps: maxSteps) {
        case let .success(slice):
            required.append(contentsOf: slice.required.elements)
        case let .failure(error):
            return .failure(error)
        }
    }

    return .success(makeEntitySlice(required: CedarSet.make(required), from: entities))
}

public func sliceEntitiesForPartialEvaluation(
    of expr: Expr,
    request: Request,
    entities: Entities,
    unknowns: CedarSet<Var> = .empty,
    maxSteps: Int = 512
) -> CedarResult<EntitySlice> {
    var residualizer = Residualizer(
        request: request,
        entities: entities,
        unknowns: unknowns,
        remainingSteps: maxSteps
    )

    switch residualizer.residualize(expr) {
    case let .success(residualExpr):
        let required = CedarSet.make(residualizer.accessedEntities.elements + sliceEUIDs(residualExpr).elements)
        return .success(makeEntitySlice(required: required, from: entities))
    case let .failure(error):
        return .failure(error)
    }
}

public func sliceEntitiesForPartialEvaluation(
    of policy: Policy,
    request: Request,
    entities: Entities,
    unknowns: CedarSet<Var> = .empty,
    maxSteps: Int = 512
) -> CedarResult<EntitySlice> {
    var residualizer = Residualizer(
        request: request,
        entities: entities,
        unknowns: unknowns,
        remainingSteps: maxSteps
    )

    switch residualizer.residualize(policy) {
    case let .success(.some(residualPolicy)):
        let required = CedarSet.make(residualizer.accessedEntities.elements + sliceEUIDs(residualPolicy).elements)
        return .success(makeEntitySlice(required: required, from: entities))
    case .success(.none):
        return .success(makeEntitySlice(required: residualizer.accessedEntities, from: entities))
    case let .failure(error):
        return .failure(error)
    }
}

public func sliceEntitiesForPartialEvaluation(
    of policies: Policies,
    request: Request,
    entities: Entities,
    unknowns: CedarSet<Var> = .empty,
    maxSteps: Int = 512
) -> CedarResult<EntitySlice> {
    var required: [EntityUID] = []

    for entry in policies {
        switch sliceEntitiesForPartialEvaluation(of: entry.value, request: request, entities: entities, unknowns: unknowns, maxSteps: maxSteps) {
        case let .success(slice):
            required.append(contentsOf: slice.required.elements)
        case let .failure(error):
            return .failure(error)
        }
    }

    return .success(makeEntitySlice(required: CedarSet.make(required), from: entities))
}

private struct Residualizer {
    let request: Request
    let entities: Entities
    let unknowns: CedarSet<Var>
    var remainingSteps: Int
    var materializedContext: Result<CedarMap<Attr, CedarValue>, RestrictedExprError>? = nil
    private var accessed: [EntityUID] = []

    init(
        request: Request,
        entities: Entities,
        unknowns: CedarSet<Var>,
        remainingSteps: Int
    ) {
        self.request = request
        self.entities = entities
        self.unknowns = unknowns
        self.remainingSteps = remainingSteps
    }

    var accessedEntities: CedarSet<EntityUID> {
        CedarSet.make(accessed)
    }

    mutating func residualize(_ expr: Expr) -> CedarResult<Expr> {
        switch expr {
        case let .lit(value):
            if containsUnsupportedExtensionValue(value) {
                return .failure(.extensionError)
            }

            return .success(.lit(value))
        case let .variable(variable):
            guard !unknowns.contains(variable) else {
                return .success(expr)
            }

            switch evaluateKnown(variable) {
            case let .success(value):
                return .success(.lit(value))
            case let .failure(error):
                return .failure(error)
            }
        case let .unaryApp(op, operand):
            switch residualize(operand) {
            case let .success(residualOperand):
                if op == .not, case let .unaryApp(.not, inner) = residualOperand {
                    return .success(inner)
                }

                guard let value = literalValue(residualOperand) else {
                    return .success(.unaryApp(op, residualOperand))
                }

                switch apply1(op, value) {
                case let .success(result):
                    return .success(.lit(result))
                case let .failure(error):
                    return .failure(error)
                }
            case let .failure(error):
                return .failure(error)
            }
        case let .binaryApp(.and, lhs, rhs):
            return residualizeAnd(lhs: lhs, rhs: rhs)
        case let .binaryApp(.or, lhs, rhs):
            return residualizeOr(lhs: lhs, rhs: rhs)
        case let .binaryApp(op, lhs, rhs):
            return residualizeBinary(op, lhs: lhs, rhs: rhs)
        case let .ifThenElse(condition, thenExpr, elseExpr):
            switch residualize(condition) {
            case let .success(residualCondition):
                if let conditionValue = literalBool(residualCondition) {
                    return residualize(conditionValue ? thenExpr : elseExpr)
                }

                switch residualize(thenExpr) {
                case let .success(residualThen):
                    switch residualize(elseExpr) {
                    case let .success(residualElse):
                        return .success(simplifyConditional(
                            condition: residualCondition,
                            thenExpr: residualThen,
                            elseExpr: residualElse
                        ))
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
            var residualValues: [Expr] = []
            residualValues.reserveCapacity(values.count)

            for value in values {
                switch residualize(value) {
                case let .success(residualValue):
                    residualValues.append(residualValue)
                case let .failure(error):
                    return .failure(error)
                }
            }

            if let literalSet = literalSetValue(residualValues) {
                return .success(.lit(.set(literalSet)))
            }

            return .success(.set(residualValues))
        case let .record(entries):
            var residualEntries: [(key: Attr, value: Expr)] = []
            residualEntries.reserveCapacity(entries.count)

            for entry in entries {
                switch residualize(entry.value) {
                case let .success(residualValue):
                    residualEntries.append((key: entry.key, value: residualValue))
                case let .failure(error):
                    return .failure(error)
                }
            }

            if let literalRecord = literalRecordValue(residualEntries) {
                return .success(.lit(.record(literalRecord)))
            }

            return .success(.record(residualEntries))
        case let .hasAttr(valueExpr, attr):
            switch residualize(valueExpr) {
            case let .success(residualValue):
                guard let value = literalValue(residualValue) else {
                    return .success(.hasAttr(residualValue, attr))
                }

                switch tracedHasAttr(value, attr) {
                case let .success(result):
                    return .success(.lit(result))
                case let .failure(error):
                    return .failure(error)
                }
            case let .failure(error):
                return .failure(error)
            }
        case let .getAttr(valueExpr, attr):
            switch residualize(valueExpr) {
            case let .success(residualValue):
                guard let value = literalValue(residualValue) else {
                    return .success(.getAttr(residualValue, attr))
                }

                switch tracedGetAttr(value, attr) {
                case let .success(result):
                    return .success(.lit(result))
                case let .failure(error):
                    return .failure(error)
                }
            case let .failure(error):
                return .failure(error)
            }
        case let .like(valueExpr, pattern):
            switch residualize(valueExpr) {
            case let .success(residualValue):
                guard let value = literalValue(residualValue) else {
                    return .success(.like(residualValue, pattern))
                }

                switch value.asString() {
                case let .success(stringValue):
                    return .success(.lit(.prim(.bool(wildcardMatch(pattern, value: Array(stringValue.unicodeScalars))))) )
                case let .failure(error):
                    return .failure(error)
                }
            case let .failure(error):
                return .failure(error)
            }
        case let .isEntityType(valueExpr, entityType):
            switch residualize(valueExpr) {
            case let .success(residualValue):
                guard let value = literalValue(residualValue) else {
                    return .success(.isEntityType(residualValue, entityType))
                }

                switch isEntityType(value, entityType) {
                case let .success(result):
                    return .success(.lit(result))
                case let .failure(error):
                    return .failure(error)
                }
            case let .failure(error):
                return .failure(error)
            }
        case let .call(function, arguments):
            var residualArguments: [Expr] = []
            residualArguments.reserveCapacity(arguments.count)

            for argument in arguments {
                switch residualize(argument) {
                case let .success(residualArgument):
                    residualArguments.append(residualArgument)
                case let .failure(error):
                    return .failure(error)
                }
            }

            guard let literalArguments = literalValues(residualArguments) else {
                return .success(.call(function, residualArguments))
            }

            switch dispatchExtensionCall(function, arguments: literalArguments) {
            case let .success(value):
                return .success(.lit(value))
            case let .failure(error):
                return .failure(error)
            }
        }
    }

    mutating func residualize(_ policy: Policy) -> CedarResult<Policy?> {
        let principalScope: PrincipalScope
        switch residualizePolicyScope(policy.principalScope, variable: .principal) {
        case let .success(.some(scope)):
            principalScope = scope
        case .success(.none):
            return .success(nil)
        case let .failure(error):
            return .failure(error)
        }

        let actionScope: ActionScope
        switch residualizePolicyScope(policy.actionScope, variable: .action) {
        case let .success(.some(scope)):
            actionScope = scope
        case .success(.none):
            return .success(nil)
        case let .failure(error):
            return .failure(error)
        }

        let resourceScope: ResourceScope
        switch residualizePolicyScope(policy.resourceScope, variable: .resource) {
        case let .success(.some(scope)):
            resourceScope = scope
        case .success(.none):
            return .success(nil)
        case let .failure(error):
            return .failure(error)
        }

        var residualConditions: [Condition] = []
        residualConditions.reserveCapacity(policy.conditions.count)

        for condition in policy.conditions {
            switch residualize(condition.body) {
            case let .success(residualBody):
                if let booleanValue = literalBool(residualBody) {
                    switch condition.kind {
                    case .when where booleanValue:
                        continue
                    case .unless where !booleanValue:
                        continue
                    default:
                        return .success(nil)
                    }
                }

                residualConditions.append(Condition(kind: condition.kind, body: residualBody))
            case let .failure(error):
                return .failure(error)
            }
        }

        return .success(Policy(
            id: policy.id,
            annotations: policy.annotations,
            effect: policy.effect,
            principalScope: principalScope,
            actionScope: actionScope,
            resourceScope: resourceScope,
            conditions: residualConditions
        ))
    }

    mutating func residualize(_ template: Template) -> CedarResult<Template?> {
        let principalScope: PrincipalScopeTemplate
        switch residualize(template.principalScope) {
        case let .success(.some(scope)):
            principalScope = scope
        case .success(.none):
            return .success(nil)
        case let .failure(error):
            return .failure(error)
        }

        let actionScope: ActionScope
        switch residualizePolicyScope(template.actionScope, variable: .action) {
        case let .success(.some(scope)):
            actionScope = scope
        case .success(.none):
            return .success(nil)
        case let .failure(error):
            return .failure(error)
        }

        let resourceScope: ResourceScopeTemplate
        switch residualize(template.resourceScope) {
        case let .success(.some(scope)):
            resourceScope = scope
        case .success(.none):
            return .success(nil)
        case let .failure(error):
            return .failure(error)
        }

        var residualConditions: [Condition] = []
        residualConditions.reserveCapacity(template.conditions.count)

        for condition in template.conditions {
            switch residualize(condition.body) {
            case let .success(residualBody):
                if let booleanValue = literalBool(residualBody) {
                    switch condition.kind {
                    case .when where booleanValue:
                        continue
                    case .unless where !booleanValue:
                        continue
                    default:
                        return .success(nil)
                    }
                }

                residualConditions.append(Condition(kind: condition.kind, body: residualBody))
            case let .failure(error):
                return .failure(error)
            }
        }

        return .success(Template(
            id: template.id,
            annotations: template.annotations,
            effect: template.effect,
            principalScope: principalScope,
            actionScope: actionScope,
            resourceScope: resourceScope,
            conditions: residualConditions
        ))
    }

    private mutating func residualizeAnd(lhs: Expr, rhs: Expr) -> CedarResult<Expr> {
        switch residualize(lhs) {
        case let .success(residualLHS):
            if let lhsValue = literalBool(residualLHS) {
                if !lhsValue {
                    return .success(.lit(.prim(.bool(false))))
                }

                return residualize(rhs)
            }

            switch residualize(rhs) {
            case let .success(residualRHS):
                if let rhsValue = literalBool(residualRHS) {
                    return rhsValue ? .success(residualLHS) : .success(.lit(.prim(.bool(false))))
                }

                return .success(.binaryApp(.and, residualLHS, residualRHS))
            case let .failure(error):
                return .failure(error)
            }
        case let .failure(error):
            return .failure(error)
        }
    }

    private mutating func residualizeOr(lhs: Expr, rhs: Expr) -> CedarResult<Expr> {
        switch residualize(lhs) {
        case let .success(residualLHS):
            if let lhsValue = literalBool(residualLHS) {
                if lhsValue {
                    return .success(.lit(.prim(.bool(true))))
                }

                return residualize(rhs)
            }

            switch residualize(rhs) {
            case let .success(residualRHS):
                if let rhsValue = literalBool(residualRHS) {
                    return rhsValue ? .success(.lit(.prim(.bool(true)))) : .success(residualLHS)
                }

                return .success(.binaryApp(.or, residualLHS, residualRHS))
            case let .failure(error):
                return .failure(error)
            }
        case let .failure(error):
            return .failure(error)
        }
    }

    private mutating func residualizeBinary(_ op: BinaryOp, lhs: Expr, rhs: Expr) -> CedarResult<Expr> {
        switch residualize(lhs) {
        case let .success(residualLHS):
            switch residualize(rhs) {
            case let .success(residualRHS):
                if op == .equal, residualLHS == residualRHS {
                    return .success(.lit(.prim(.bool(true))))
                }

                guard let lhsValue = literalValue(residualLHS), let rhsValue = literalValue(residualRHS) else {
                    return .success(.binaryApp(op, residualLHS, residualRHS))
                }

                switch tracedApplyBinary(op, lhs: lhsValue, rhs: rhsValue) {
                case let .success(result):
                    return .success(.lit(result))
                case let .failure(error):
                    return .failure(error)
                }
            case let .failure(error):
                return .failure(error)
            }
        case let .failure(error):
            return .failure(error)
        }
    }

    private mutating func evaluateKnown(_ variable: Var) -> CedarResult<CedarValue> {
        switch variable {
        case .principal:
            return .success(.prim(.entityUID(request.principal)))
        case .action:
            return .success(.prim(.entityUID(request.action)))
        case .resource:
            return .success(.prim(.entityUID(request.resource)))
        case .context:
            switch materializedRequestContext() {
            case let .success(context):
                return .success(.record(context))
            case let .failure(error):
                return .failure(.restrictedExprError(error))
            }
        }
    }

    private mutating func materializedRequestContext() -> Result<CedarMap<Attr, CedarValue>, RestrictedExprError> {
        if let materializedContext {
            return materializedContext
        }

        let result = request.context.materializeRecord()
        materializedContext = result
        return result
    }

    private mutating func tracedApplyBinary(_ op: BinaryOp, lhs: CedarValue, rhs: CedarValue) -> CedarResult<CedarValue> {
        switch op {
        case .equal:
            return applySharedComparison(.equal, lhs: lhs, rhs: rhs)
        case .lessThan:
            return applySharedComparison(.lessThan, lhs: lhs, rhs: rhs)
        case .lessThanOrEqual:
            return applySharedComparison(.lessThanOrEqual, lhs: lhs, rhs: rhs)
        case .add, .sub, .mul, .contains, .containsAll, .containsAny:
            return apply2(op, lhs, rhs, entities: entities, remainingSteps: &remainingSteps)
        case .in:
            switch (lhs, rhs) {
            case let (.prim(.entityUID(uid)), .prim(.entityUID(ancestor))):
                switch tracedInE(uid, ancestor) {
                case let .success(result):
                    return .success(.prim(.bool(result)))
                case let .failure(error):
                    return .failure(error)
                }
            case let (.prim(.entityUID(uid)), .set(values)):
                return tracedInSet(uid, values)
            default:
                return .failure(.typeError)
            }
        case .hasTag:
            guard case let .prim(.entityUID(uid)) = lhs, case let .prim(.string(tag)) = rhs else {
                return .failure(.typeError)
            }

            return tracedHasTag(uid, tag)
        case .getTag:
            guard case let .prim(.entityUID(uid)) = lhs, case let .prim(.string(tag)) = rhs else {
                return .failure(.typeError)
            }

            return tracedGetTag(uid, tag)
        case .and, .or:
            return .failure(.typeError)
        }
    }

    private mutating func tracedInSet(_ uid: EntityUID, _ values: CedarSet<CedarValue>) -> CedarResult<CedarValue> {
        let candidateUIDs: CedarSet<EntityUID>
        switch values.mapOrErr({ $0.asEntityUID() }, error: .typeError) {
        case let .success(coercedUIDs):
            candidateUIDs = coercedUIDs
        case let .failure(error):
            return .failure(error)
        }

        for candidateUID in candidateUIDs.elements {
            switch tracedInE(uid, candidateUID) {
            case let .success(result):
                if result {
                    return .success(.prim(.bool(true)))
                }
            case let .failure(error):
                return .failure(error)
            }
        }

        return .success(.prim(.bool(false)))
    }

    private mutating func tracedInE(_ current: EntityUID, _ target: EntityUID, visited: inout [EntityUID]) -> CedarResult<Bool> {
        markAccess(current)
        markAccess(target)

        if current == target {
            return .success(true)
        }

        if visited.contains(where: { $0 == current }) {
            return .success(false)
        }

        switch consumeTraversalStep(&remainingSteps) {
        case let .failure(error):
            return .failure(error)
        case .success:
            break
        }

        let ancestors: CedarSet<EntityUID>
        switch entities.ancestors(current) {
        case let .success(resolvedAncestors):
            ancestors = resolvedAncestors
        case let .failure(error):
            return .failure(error)
        }

        for ancestor in ancestors.elements {
            markAccess(ancestor)
        }

        if ancestors.contains(target) {
            return .success(true)
        }

        visited.append(current)

        for ancestor in ancestors.elements {
            switch tracedInE(ancestor, target, visited: &visited) {
            case let .success(result):
                if result {
                    return .success(true)
                }
            case let .failure(error):
                return .failure(error)
            }
        }

        return .success(false)
    }

    private mutating func tracedInE(_ current: EntityUID, _ target: EntityUID) -> CedarResult<Bool> {
        var visited: [EntityUID] = []
        return tracedInE(current, target, visited: &visited)
    }

    private mutating func tracedHasAttr(_ value: CedarValue, _ attr: Attr) -> CedarResult<CedarValue> {
        switch value {
        case let .record(record):
            return .success(.prim(.bool(record.contains(attr))))
        case let .prim(.entityUID(uid)):
            markAccess(uid)
            return .success(.prim(.bool(entities.attrsOrEmpty(uid).contains(attr))))
        default:
            return .failure(.typeError)
        }
    }

    private mutating func tracedGetAttr(_ value: CedarValue, _ attr: Attr) -> CedarResult<CedarValue> {
        switch value {
        case let .record(record):
            return record.findOrErr(attr, error: .attrDoesNotExist)
        case let .prim(.entityUID(uid)):
            markAccess(uid)
            switch entities.attrs(uid) {
            case let .success(record):
                return record.findOrErr(attr, error: .attrDoesNotExist)
            case let .failure(error):
                return .failure(error)
            }
        default:
            return .failure(.typeError)
        }
    }

    private mutating func tracedHasTag(_ uid: EntityUID, _ tag: Tag) -> CedarResult<CedarValue> {
        markAccess(uid)
        return .success(.prim(.bool(entities.tagsOrEmpty(uid).contains(tag))))
    }

    private mutating func tracedGetTag(_ uid: EntityUID, _ tag: Tag) -> CedarResult<CedarValue> {
        markAccess(uid)
        switch entities.tags(uid) {
        case let .success(tags):
            return tags.findOrErr(tag, error: .tagDoesNotExist)
        case let .failure(error):
            return .failure(error)
        }
    }

    private mutating func residualizePolicyScope(_ scope: PrincipalScope, variable: Var) -> CedarResult<PrincipalScope?> {
        switch residualize(scope.toExpr()) {
        case let .success(residualExpr):
            if let value = literalBool(residualExpr) {
                return .success(value ? .any : nil)
            }

            return .success(scope)
        case let .failure(error):
            return .failure(error)
        }
    }

    private mutating func residualizePolicyScope(_ scope: ActionScope, variable: Var) -> CedarResult<ActionScope?> {
        switch residualize(scope.toExpr()) {
        case let .success(residualExpr):
            if let value = literalBool(residualExpr) {
                return .success(value ? .any : nil)
            }

            return .success(scope)
        case let .failure(error):
            return .failure(error)
        }
    }

    private mutating func residualizePolicyScope(_ scope: ResourceScope, variable: Var) -> CedarResult<ResourceScope?> {
        switch residualize(scope.toExpr()) {
        case let .success(residualExpr):
            if let value = literalBool(residualExpr) {
                return .success(value ? .any : nil)
            }

            return .success(scope)
        case let .failure(error):
            return .failure(error)
        }
    }

    private mutating func residualize(_ scope: PrincipalScopeTemplate) -> CedarResult<PrincipalScopeTemplate?> {
        guard let concreteScope = concretePrincipalScope(scope) else {
            return .success(scope)
        }

        switch residualizePolicyScope(concreteScope, variable: .principal) {
        case .success(.some(.any)):
            return .success(PrincipalScopeTemplate(.any))
        case .success(.none):
            return .success(nil)
        case .success:
            return .success(scope)
        case let .failure(error):
            return .failure(error)
        }
    }

    private mutating func residualize(_ scope: ResourceScopeTemplate) -> CedarResult<ResourceScopeTemplate?> {
        guard let concreteScope = concreteResourceScope(scope) else {
            return .success(scope)
        }

        switch residualizePolicyScope(concreteScope, variable: .resource) {
        case .success(.some(.any)):
            return .success(ResourceScopeTemplate(.any))
        case .success(.none):
            return .success(nil)
        case .success:
            return .success(scope)
        case let .failure(error):
            return .failure(error)
        }
    }

    private mutating func markAccess(_ uid: EntityUID) {
        accessed.append(uid)
    }
}

private func literalValue(_ expr: Expr) -> CedarValue? {
    guard case let .lit(value) = expr else {
        return nil
    }

    return value
}

private func literalBool(_ expr: Expr) -> Bool? {
    guard case let .lit(.prim(.bool(value))) = expr else {
        return nil
    }

    return value
}

private func simplifyConditional(condition: Expr, thenExpr: Expr, elseExpr: Expr) -> Expr {
    if thenExpr == elseExpr {
        return thenExpr
    }

    if literalBool(thenExpr) == true, literalBool(elseExpr) == false {
        return condition
    }

    if literalBool(thenExpr) == false, literalBool(elseExpr) == true {
        return .unaryApp(.not, condition)
    }

    return .ifThenElse(condition, thenExpr, elseExpr)
}

private func literalValues(_ expressions: [Expr]) -> [CedarValue]? {
    var values: [CedarValue] = []
    values.reserveCapacity(expressions.count)

    for expression in expressions {
        guard let value = literalValue(expression) else {
            return nil
        }

        values.append(value)
    }

    return values
}

private func literalSetValue(_ expressions: [Expr]) -> CedarSet<CedarValue>? {
    guard let values = literalValues(expressions) else {
        return nil
    }

    return CedarSet.make(values)
}

private func literalRecordValue(_ entries: [(key: Attr, value: Expr)]) -> CedarMap<Attr, CedarValue>? {
    var recordEntries: [(key: Attr, value: CedarValue)] = []
    recordEntries.reserveCapacity(entries.count)

    for entry in entries {
        guard let value = literalValue(entry.value) else {
            return nil
        }

        recordEntries.append((key: entry.key, value: value))
    }

    return CedarMap.make(recordEntries)
}

private func concretePrincipalScope(_ scope: PrincipalScopeTemplate) -> PrincipalScope? {
    switch scope.scope {
    case .any:
        return .any
    case let .eq(.entityUID(entity)):
        return .eq(entity: entity)
    case let .in(.entityUID(entity)):
        return .in(entity: entity)
    case let .isEntityType(entityType):
        return .isEntityType(entityType: entityType)
    case let .isEntityTypeIn(entityType, .entityUID(entity)):
        return .isEntityTypeIn(entityType: entityType, entity: entity)
    case .eq(.slot), .in(.slot), .isEntityTypeIn(_, .slot):
        return nil
    }
}

private func concreteResourceScope(_ scope: ResourceScopeTemplate) -> ResourceScope? {
    switch scope.scope {
    case .any:
        return .any
    case let .eq(.entityUID(entity)):
        return .eq(entity: entity)
    case let .in(.entityUID(entity)):
        return .in(entity: entity)
    case let .isEntityType(entityType):
        return .isEntityType(entityType: entityType)
    case let .isEntityTypeIn(entityType, .entityUID(entity)):
        return .isEntityTypeIn(entityType: entityType, entity: entity)
    case .eq(.slot), .in(.slot), .isEntityTypeIn(_, .slot):
        return nil
    }
}

private func makeEntitySlice(required: CedarSet<EntityUID>, from entities: Entities) -> EntitySlice {
    sliceAtLevel(required, entities: entities, level: 0)
}
