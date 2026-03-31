internal func intOrErr(_ value: Int64?) -> CedarResult<CedarValue> {
    guard let value else {
        return .failure(.arithBoundsError)
    }

    return .success(.prim(.int(value)))
}

internal func apply1(_ op: UnaryOp, _ value: CedarValue) -> CedarResult<CedarValue> {
    switch (op, value) {
    case let (.not, .prim(.bool(booleanValue))):
        return .success(.prim(.bool(!booleanValue)))
    case let (.neg, .prim(.int(intValue))):
        return intOrErr(CedarInt64.neg(intValue))
    case let (.isEmpty, .set(setValue)):
        return .success(.prim(.bool(setValue.isEmpty)))
    default:
        return .failure(.typeError)
    }
}

internal func consumeTraversalStep(_ remainingSteps: inout Int) -> CedarResult<Void> {
    guard remainingSteps > 0 else {
        return .failure(.evaluationLimitError)
    }

    remainingSteps -= 1
    return .success(())
}

internal func inE(
    _ uid: EntityUID,
    _ ancestor: EntityUID,
    entities: Entities,
    remainingSteps: inout Int
) -> CedarResult<Bool> {
    var visited: [EntityUID] = []
    return inE(uid, ancestor, entities: entities, remainingSteps: &remainingSteps, visited: &visited)
}

internal func inS(
    _ uid: EntityUID,
    _ values: CedarSet<CedarValue>,
    entities: Entities,
    remainingSteps: inout Int
) -> CedarResult<CedarValue> {
    let candidateUIDs: CedarSet<EntityUID>
    switch values.mapOrErr({ $0.asEntityUID() }, error: .typeError) {
    case let .success(coercedUIDs):
        candidateUIDs = coercedUIDs
    case let .failure(error):
        return .failure(error)
    }

    for candidateUID in candidateUIDs.elements {
        switch inE(uid, candidateUID, entities: entities, remainingSteps: &remainingSteps) {
        case let .failure(error):
            return .failure(error)
        case .success(true):
            return .success(.prim(.bool(true)))
        case .success(false):
            continue
        }
    }

    return .success(.prim(.bool(false)))
}

internal func apply2(
    _ op: BinaryOp,
    _ lhs: CedarValue,
    _ rhs: CedarValue,
    entities: Entities,
    remainingSteps: inout Int
) -> CedarResult<CedarValue> {
    switch (op, lhs, rhs) {
    case (.equal, _, _):
        return applySharedComparison(.equal, lhs: lhs, rhs: rhs)
    case (.lessThan, _, _):
        return applySharedComparison(.lessThan, lhs: lhs, rhs: rhs)
    case (.lessThanOrEqual, _, _):
        return applySharedComparison(.lessThanOrEqual, lhs: lhs, rhs: rhs)
    case let (.add, .prim(.int(left)), .prim(.int(right))):
        return intOrErr(CedarInt64.add(left, right))
    case let (.sub, .prim(.int(left)), .prim(.int(right))):
        return intOrErr(CedarInt64.sub(left, right))
    case let (.mul, .prim(.int(left)), .prim(.int(right))):
        return intOrErr(CedarInt64.mul(left, right))
    case (.contains, _, _):
        guard case let .set(values) = lhs else {
            return .failure(.typeError)
        }

        return .success(.prim(.bool(values.contains(rhs))))
    case (.containsAll, _, _):
        guard case let .set(values) = lhs, case let .set(containedValues) = rhs else {
            return .failure(.typeError)
        }

        return .success(.prim(.bool(containedValues.subset(of: values))))
    case (.containsAny, _, _):
        guard case let .set(values) = lhs, case let .set(candidateValues) = rhs else {
            return .failure(.typeError)
        }

        return .success(.prim(.bool(values.intersects(with: candidateValues))))
    case let (.in, .prim(.entityUID(uid)), .prim(.entityUID(ancestor))):
        switch inE(uid, ancestor, entities: entities, remainingSteps: &remainingSteps) {
        case let .success(isMember):
            return .success(.prim(.bool(isMember)))
        case let .failure(error):
            return .failure(error)
        }
    case let (.in, .prim(.entityUID(uid)), .set(values)):
        return inS(uid, values, entities: entities, remainingSteps: &remainingSteps)
    case let (.hasTag, .prim(.entityUID(uid)), .prim(.string(tag))):
        return hasTag(uid, tag, entities: entities)
    case let (.getTag, .prim(.entityUID(uid)), .prim(.string(tag))):
        return getTag(uid, tag, entities: entities)
    default:
        return .failure(.typeError)
    }
}

internal func attrsOf(
    _ value: CedarValue,
    lookup: (EntityUID) -> CedarResult<CedarMap<Attr, CedarValue>>
) -> CedarResult<CedarMap<Attr, CedarValue>> {
    switch value {
    case let .record(recordValue):
        return .success(recordValue)
    case let .prim(.entityUID(uid)):
        return lookup(uid)
    default:
        return .failure(.typeError)
    }
}

internal func hasAttr(_ value: CedarValue, _ attr: Attr, entities: Entities) -> CedarResult<CedarValue> {
    switch attrsOf(value, lookup: { .success(entities.attrsOrEmpty($0)) }) {
    case let .success(recordValue):
        return .success(.prim(.bool(recordValue.contains(attr))))
    case let .failure(error):
        return .failure(error)
    }
}

internal func getAttr(_ value: CedarValue, _ attr: Attr, entities: Entities) -> CedarResult<CedarValue> {
    switch attrsOf(value, lookup: entities.attrs) {
    case let .success(recordValue):
        return recordValue.findOrErr(attr, error: .attrDoesNotExist)
    case let .failure(error):
        return .failure(error)
    }
}

internal func hasTag(_ uid: EntityUID, _ tag: Tag, entities: Entities) -> CedarResult<CedarValue> {
    .success(.prim(.bool(entities.tagsOrEmpty(uid).contains(tag))))
}

internal func getTag(_ uid: EntityUID, _ tag: Tag, entities: Entities) -> CedarResult<CedarValue> {
    switch entities.tags(uid) {
    case let .success(tags):
        return tags.findOrErr(tag, error: .tagDoesNotExist)
    case let .failure(error):
        return .failure(error)
    }
}

internal func bindAttr<T>(_ attr: Attr, _ result: CedarResult<T>) -> CedarResult<(Attr, T)> {
    switch result {
    case let .success(value):
        return .success((attr, value))
    case let .failure(error):
        return .failure(error)
    }
}

internal func isEntityType(_ value: CedarValue, _ entityType: Name) -> CedarResult<CedarValue> {
    guard case let .prim(.entityUID(uid)) = value else {
        return .failure(.typeError)
    }

    return .success(.prim(.bool(uid.ty == entityType)))
}

internal func evaluate(
    _ expr: Expr,
    request: Request,
    entities: Entities,
    maxSteps: Int
) -> CedarResult<CedarValue> {
    var evaluator = Evaluator(request: request, entities: entities, remainingSteps: maxSteps)
    return evaluator.evaluate(expr)
}

internal let defaultEvaluationStepLimit = 512

public func evaluate(_ expr: Expr, request: Request, entities: Entities) -> CedarResult<CedarValue> {
    evaluate(expr, request: request, entities: entities, maxSteps: defaultEvaluationStepLimit)
}

private struct Evaluator {
    let request: Request
    let entities: Entities
    var remainingSteps: Int
    var materializedContext: Result<CedarMap<Attr, CedarValue>, RestrictedExprError>? = nil

    mutating func evaluate(_ expr: Expr) -> CedarResult<CedarValue> {
        guard remainingSteps > 0 else {
            return .failure(.evaluationLimitError)
        }

        remainingSteps -= 1

        switch expr {
        case let .lit(value):
            if containsUnsupportedExtensionValue(value) {
                return .failure(.extensionError)
            }

            return .success(value)
        case let .variable(variable):
            return evaluate(variable)
        case let .unaryApp(op, operand):
            switch evaluate(operand) {
            case let .success(value):
                return apply1(op, value)
            case let .failure(error):
                return .failure(error)
            }
        case let .binaryApp(.and, lhs, rhs):
            return evaluateAnd(lhs: lhs, rhs: rhs)
        case let .binaryApp(.or, lhs, rhs):
            return evaluateOr(lhs: lhs, rhs: rhs)
        case let .binaryApp(op, lhs, rhs):
            switch evaluate(lhs) {
            case let .failure(error):
                return .failure(error)
            case let .success(leftValue):
                switch evaluate(rhs) {
                case let .failure(error):
                    return .failure(error)
                case let .success(rightValue):
                    return apply2(op, leftValue, rightValue, entities: entities, remainingSteps: &remainingSteps)
                }
            }
        case let .ifThenElse(condition, thenExpr, elseExpr):
            switch evaluate(condition) {
            case let .failure(error):
                return .failure(error)
            case let .success(value):
                switch value.asBool() {
                case let .failure(error):
                    return .failure(error)
                case let .success(conditionValue):
                    return conditionValue ? evaluate(thenExpr) : evaluate(elseExpr)
                }
            }
        case let .set(expressions):
            return evaluateSet(expressions)
        case let .record(entries):
            return evaluateRecord(entries)
        case let .hasAttr(valueExpr, attr):
            switch evaluate(valueExpr) {
            case let .success(value):
                return hasAttr(value, attr, entities: entities)
            case let .failure(error):
                return .failure(error)
            }
        case let .getAttr(valueExpr, attr):
            switch evaluate(valueExpr) {
            case let .success(value):
                return getAttr(value, attr, entities: entities)
            case let .failure(error):
                return .failure(error)
            }
        case let .like(valueExpr, pattern):
            switch evaluate(valueExpr) {
            case let .failure(error):
                return .failure(error)
            case let .success(value):
                switch value.asString() {
                case let .failure(error):
                    return .failure(error)
                case let .success(stringValue):
                    return .success(.prim(.bool(wildcardMatch(pattern, value: Array(stringValue.unicodeScalars)))))
                }
            }
        case let .isEntityType(valueExpr, entityType):
            switch evaluate(valueExpr) {
            case let .success(value):
                return isEntityType(value, entityType)
            case let .failure(error):
                return .failure(error)
            }
        case let .call(function, arguments):
            var evaluatedArguments: [CedarValue] = []
            evaluatedArguments.reserveCapacity(arguments.count)

            for argument in arguments {
                switch evaluate(argument) {
                case let .failure(error):
                    return .failure(error)
                case let .success(value):
                    evaluatedArguments.append(value)
                }
            }

            return dispatchExtensionCall(function, arguments: evaluatedArguments)
        }
    }

    private mutating func evaluate(_ variable: Var) -> CedarResult<CedarValue> {
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

    private mutating func evaluateAnd(lhs: Expr, rhs: Expr) -> CedarResult<CedarValue> {
        switch evaluate(lhs) {
        case let .failure(error):
            return .failure(error)
        case let .success(value):
            switch value.asBool() {
            case let .failure(error):
                return .failure(error)
            case let .success(booleanValue):
                if !booleanValue {
                    return .success(.prim(.bool(false)))
                }

                switch evaluate(rhs) {
                case let .failure(error):
                    return .failure(error)
                case let .success(rhsValue):
                    switch rhsValue.asBool() {
                    case let .failure(error):
                        return .failure(error)
                    case let .success(rhsBooleanValue):
                        return .success(.prim(.bool(rhsBooleanValue)))
                    }
                }
            }
        }
    }

    private mutating func evaluateOr(lhs: Expr, rhs: Expr) -> CedarResult<CedarValue> {
        switch evaluate(lhs) {
        case let .failure(error):
            return .failure(error)
        case let .success(value):
            switch value.asBool() {
            case let .failure(error):
                return .failure(error)
            case let .success(booleanValue):
                if booleanValue {
                    return .success(.prim(.bool(true)))
                }

                switch evaluate(rhs) {
                case let .failure(error):
                    return .failure(error)
                case let .success(rhsValue):
                    switch rhsValue.asBool() {
                    case let .failure(error):
                        return .failure(error)
                    case let .success(rhsBooleanValue):
                        return .success(.prim(.bool(rhsBooleanValue)))
                    }
                }
            }
        }
    }

    private mutating func evaluateSet(_ expressions: [Expr]) -> CedarResult<CedarValue> {
        var values: [CedarValue] = []
        values.reserveCapacity(expressions.count)

        for expression in expressions {
            switch evaluate(expression) {
            case let .success(value):
                if containsUnsupportedExtensionValue(value) {
                    return .failure(.extensionError)
                }

                values.append(value)
            case let .failure(error):
                return .failure(error)
            }
        }

        return .success(.set(CedarSet.make(values)))
    }

    private mutating func evaluateRecord(_ entries: [(key: Attr, value: Expr)]) -> CedarResult<CedarValue> {
        var evaluatedEntries: [(key: Attr, value: CedarValue)] = []
        evaluatedEntries.reserveCapacity(entries.count)

        for entry in entries {
            switch bindAttr(entry.key, evaluate(entry.value)) {
            case let .success(boundEntry):
                if containsUnsupportedExtensionValue(boundEntry.1) {
                    return .failure(.extensionError)
                }

                evaluatedEntries.append(boundEntry)
            case let .failure(error):
                return .failure(error)
            }
        }

        return .success(.record(CedarMap.make(evaluatedEntries)))
    }
}

private func inE(
    _ current: EntityUID,
    _ target: EntityUID,
    entities: Entities,
    remainingSteps: inout Int,
    visited: inout [EntityUID]
) -> CedarResult<Bool> {
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
    case .failure(.entityDoesNotExist):
        return .success(false)
    case let .failure(error):
        return .failure(error)
    }

    if ancestors.contains(target) {
        return .success(true)
    }

    visited.append(current)

    for ancestor in ancestors.elements {
        switch inE(ancestor, target, entities: entities, remainingSteps: &remainingSteps, visited: &visited) {
        case let .failure(error):
            return .failure(error)
        case .success(true):
            return .success(true)
        case .success(false):
            continue
        }
    }

    return .success(false)
}
