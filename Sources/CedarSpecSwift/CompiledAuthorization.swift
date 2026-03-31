import Foundation

internal final class CompiledRequestState: @unchecked Sendable {
    let request: Request
    let entities: Entities
    let principalValue: CedarValue
    let actionValue: CedarValue
    let resourceValue: CedarValue

    private var materializedContext: Result<CedarMap<Attr, CedarValue>, RestrictedExprError>? = nil
    private var cachedContextValue: CedarValue? = nil
    private var cachedEntityData: [EntityUID: EntityData?] = [:]

    init(request: Request, entities: Entities) {
        self.request = request
        self.entities = entities
        principalValue = .prim(.entityUID(request.principal))
        actionValue = .prim(.entityUID(request.action))
        resourceValue = .prim(.entityUID(request.resource))
    }

    @inline(__always)
    func entityUID(for variable: Var) -> EntityUID? {
        switch variable {
        case .principal:
            return request.principal
        case .action:
            return request.action
        case .resource:
            return request.resource
        case .context:
            return nil
        }
    }

    @inline(__always)
    func cedarValue(for variable: Var) -> Result<CedarValue, RestrictedExprError> {
        switch variable {
        case .principal:
            return .success(principalValue)
        case .action:
            return .success(actionValue)
        case .resource:
            return .success(resourceValue)
        case .context:
            return materializeContextValue()
        }
    }

    @inline(__always)
    func materializedContextRecord() -> Result<CedarMap<Attr, CedarValue>, RestrictedExprError> {
        if let materializedContext {
            return materializedContext
        }

        let result = request.context.materializeRecord()
        materializedContext = result
        return result
    }

    @inline(__always)
    private func materializeContextValue() -> Result<CedarValue, RestrictedExprError> {
        if let cachedContextValue {
            return .success(cachedContextValue)
        }

        switch materializedContextRecord() {
        case let .success(contextRecord):
            let value = CedarValue.record(contextRecord)
            cachedContextValue = value
            return .success(value)
        case let .failure(error):
            return .failure(error)
        }
    }

    @inline(__always)
    func attrsOrEmpty(for uid: EntityUID) -> CedarMap<Attr, CedarValue> {
        entityData(for: uid)?.attrs ?? .empty
    }

    @inline(__always)
    func attrs(for uid: EntityUID) -> CedarResult<CedarMap<Attr, CedarValue>> {
        guard let entityData = entityData(for: uid) else {
            return .failure(.entityDoesNotExist)
        }

        return .success(entityData.attrs)
    }

    @inline(__always)
    func tagsOrEmpty(for uid: EntityUID) -> CedarMap<Tag, CedarValue> {
        entityData(for: uid)?.tags ?? .empty
    }

    @inline(__always)
    func tags(for uid: EntityUID) -> CedarResult<CedarMap<Tag, CedarValue>> {
        guard let entityData = entityData(for: uid) else {
            return .failure(.entityDoesNotExist)
        }

        return .success(entityData.tags)
    }

    private func entityData(for uid: EntityUID) -> EntityData? {
        if let cached = cachedEntityData[uid] {
            return cached
        }

        let resolved = entities.entries.find(uid)
        cachedEntityData[uid] = resolved
        return resolved
    }
}

internal struct CompiledEvalContext {
    let requestState: CompiledRequestState
    var remainingSteps: Int

    @inline(__always)
    mutating func consumeStep() -> CedarResult<Void> {
        guard remainingSteps > 0 else {
            return .failure(.evaluationLimitError)
        }

        remainingSteps -= 1
        return .success(())
    }

    @inline(__always)
    mutating func evaluate(_ variable: Var) -> CedarResult<CedarValue> {
        switch requestState.cedarValue(for: variable) {
        case let .success(value):
            return .success(value)
        case let .failure(error):
            return .failure(.restrictedExprError(error))
        }
    }

    @inline(__always)
    func entityUID(for variable: Var) -> EntityUID? {
        requestState.entityUID(for: variable)
    }

    @inline(__always)
    var entities: Entities {
        requestState.entities
    }

    @inline(__always)
    mutating func materializedRequestContext() -> Result<CedarMap<Attr, CedarValue>, RestrictedExprError> {
        requestState.materializedContextRecord()
    }

    @inline(__always)
    mutating func attrsOrEmpty(for uid: EntityUID) -> CedarMap<Attr, CedarValue> {
        requestState.attrsOrEmpty(for: uid)
    }

    @inline(__always)
    mutating func attrs(for uid: EntityUID) -> CedarResult<CedarMap<Attr, CedarValue>> {
        requestState.attrs(for: uid)
    }

    @inline(__always)
    mutating func tagsOrEmpty(for uid: EntityUID) -> CedarMap<Tag, CedarValue> {
        requestState.tagsOrEmpty(for: uid)
    }

    @inline(__always)
    mutating func tags(for uid: EntityUID) -> CedarResult<CedarMap<Tag, CedarValue>> {
        requestState.tags(for: uid)
    }

}

internal struct CompiledExpr: Sendable {
    private let evaluator: @Sendable (inout CompiledEvalContext) -> CedarResult<CedarValue>

    init(_ evaluator: @escaping @Sendable (inout CompiledEvalContext) -> CedarResult<CedarValue>) {
        self.evaluator = evaluator
    }

    @inline(__always)
    func callAsFunction(_ context: inout CompiledEvalContext) -> CedarResult<CedarValue> {
        evaluator(&context)
    }

    static func compile(_ expr: Expr) -> Self {
        switch expr {
        case let .lit(value):
            let isSupported = !containsUnsupportedExtensionValue(value)
            return stepped { _ in
                isSupported ? .success(value) : .failure(.extensionError)
            }
        case let .variable(variable):
            return stepped { context in
                context.evaluate(variable)
            }
        case let .unaryApp(op, operand):
            let compiledOperand = compile(operand)
            return stepped { context in
                switch compiledOperand(&context) {
                case let .success(value):
                    return apply1(op, value)
                case let .failure(error):
                    return .failure(error)
                }
            }
        case let .binaryApp(.and, lhs, rhs):
            let compiledLHS = CompiledBoolExpr.compile(lhs)
            let compiledRHS = CompiledBoolExpr.compile(rhs)
            return stepped { context in
                switch compiledLHS(&context) {
                case let .failure(error):
                    return .failure(error)
                case let .success(booleanValue):
                    if !booleanValue {
                        return .success(.prim(.bool(false)))
                    }

                    switch compiledRHS(&context) {
                    case let .failure(error):
                        return .failure(error)
                    case let .success(rhsBooleanValue):
                        return .success(.prim(.bool(rhsBooleanValue)))
                    }
                }
            }
        case let .binaryApp(.or, lhs, rhs):
            let compiledLHS = CompiledBoolExpr.compile(lhs)
            let compiledRHS = CompiledBoolExpr.compile(rhs)
            return stepped { context in
                switch compiledLHS(&context) {
                case let .failure(error):
                    return .failure(error)
                case let .success(booleanValue):
                    if booleanValue {
                        return .success(.prim(.bool(true)))
                    }

                    switch compiledRHS(&context) {
                    case let .failure(error):
                        return .failure(error)
                    case let .success(rhsBooleanValue):
                        return .success(.prim(.bool(rhsBooleanValue)))
                    }
                }
            }
        case let .binaryApp(.getTag, .variable(variable), .lit(.prim(.string(tag)))) where variable != .context:
            return stepped { context in
                switch context.consumeStep() {
                case let .failure(error):
                    return .failure(error)
                case .success:
                    break
                }

                switch context.consumeStep() {
                case let .failure(error):
                    return .failure(error)
                case .success:
                    break
                }

                guard let uid = context.entityUID(for: variable) else {
                    return .failure(.typeError)
                }

                switch context.tags(for: uid) {
                case let .success(tags):
                    return tags.findOrErr(tag, error: .tagDoesNotExist)
                case let .failure(error):
                    return .failure(error)
                }
            }
        case let .binaryApp(op, lhs, rhs):
            let compiledLHS = compile(lhs)
            let compiledRHS = compile(rhs)
            return stepped { context in
                switch compiledLHS(&context) {
                case let .failure(error):
                    return .failure(error)
                case let .success(leftValue):
                    switch compiledRHS(&context) {
                    case let .failure(error):
                        return .failure(error)
                    case let .success(rightValue):
                        return apply2(op, leftValue, rightValue, entities: context.entities, remainingSteps: &context.remainingSteps)
                    }
                }
            }
        case let .ifThenElse(condition, thenExpr, elseExpr):
            let compiledCondition = CompiledBoolExpr.compile(condition)
            let compiledThen = compile(thenExpr)
            let compiledElse = compile(elseExpr)
            return stepped { context in
                switch compiledCondition(&context) {
                case let .failure(error):
                    return .failure(error)
                case let .success(conditionValue):
                    return conditionValue ? compiledThen(&context) : compiledElse(&context)
                }
            }
        case let .set(expressions):
            let compiledExpressions = expressions.map(compile)
            return stepped { context in
                var values: [CedarValue] = []
                values.reserveCapacity(compiledExpressions.count)

                for compiledExpression in compiledExpressions {
                    switch compiledExpression(&context) {
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
        case let .record(entries):
            let compiledEntries = entries.map { (key: $0.key, value: compile($0.value)) }
            return stepped { context in
                var evaluatedEntries: [(key: Attr, value: CedarValue)] = []
                evaluatedEntries.reserveCapacity(compiledEntries.count)

                for entry in compiledEntries {
                    switch bindAttr(entry.key, entry.value(&context)) {
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
        case let .hasAttr(valueExpr, attr):
            if case .variable(.context) = valueExpr {
                return stepped { context in
                    switch context.consumeStep() {
                    case let .failure(error):
                        return .failure(error)
                    case .success:
                        break
                    }

                    switch context.materializedRequestContext() {
                    case let .success(requestContext):
                        return .success(.prim(.bool(requestContext.contains(attr))))
                    case let .failure(error):
                        return .failure(.restrictedExprError(error))
                    }
                }
            }

            if case let .variable(variable) = valueExpr, variable != .context {
                return stepped { context in
                    switch context.consumeStep() {
                    case let .failure(error):
                        return .failure(error)
                    case .success:
                        break
                    }

                    guard let uid = context.entityUID(for: variable) else {
                        return .failure(.typeError)
                    }

                    return .success(.prim(.bool(context.attrsOrEmpty(for: uid).contains(attr))))
                }
            }

            let compiledValue = compile(valueExpr)
            return stepped { context in
                switch compiledValue(&context) {
                case let .success(value):
                    return hasAttr(value, attr, entities: context.entities)
                case let .failure(error):
                    return .failure(error)
                }
            }
        case let .getAttr(valueExpr, attr):
            if case .variable(.context) = valueExpr {
                return stepped { context in
                    switch context.consumeStep() {
                    case let .failure(error):
                        return .failure(error)
                    case .success:
                        break
                    }

                    switch context.materializedRequestContext() {
                    case let .success(requestContext):
                        return requestContext.findOrErr(attr, error: .attrDoesNotExist)
                    case let .failure(error):
                        return .failure(.restrictedExprError(error))
                    }
                }
            }

            if case let .variable(variable) = valueExpr, variable != .context {
                return stepped { context in
                    switch context.consumeStep() {
                    case let .failure(error):
                        return .failure(error)
                    case .success:
                        break
                    }

                    guard let uid = context.entityUID(for: variable) else {
                        return .failure(.typeError)
                    }

                    switch context.attrs(for: uid) {
                    case let .success(recordValue):
                        return recordValue.findOrErr(attr, error: .attrDoesNotExist)
                    case let .failure(error):
                        return .failure(error)
                    }
                }
            }

            let compiledValue = compile(valueExpr)
            return stepped { context in
                switch compiledValue(&context) {
                case let .success(value):
                    return getAttr(value, attr, entities: context.entities)
                case let .failure(error):
                    return .failure(error)
                }
            }
        case let .like(valueExpr, pattern):
            let compiledValue = compile(valueExpr)
            return stepped { context in
                switch compiledValue(&context) {
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
            }
        case let .isEntityType(valueExpr, entityType):
            if case let .variable(variable) = valueExpr, variable != .context {
                return stepped { context in
                    switch context.consumeStep() {
                    case let .failure(error):
                        return .failure(error)
                    case .success:
                        break
                    }

                    guard let uid = context.entityUID(for: variable) else {
                        return .failure(.typeError)
                    }

                    return .success(.prim(.bool(uid.ty == entityType)))
                }
            }

            let compiledValue = compile(valueExpr)
            return stepped { context in
                switch compiledValue(&context) {
                case let .success(value):
                    return isEntityType(value, entityType)
                case let .failure(error):
                    return .failure(error)
                }
            }
        case let .call(function, arguments):
            let compiledArguments = arguments.map(compile)
            return stepped { context in
                var evaluatedArguments: [CedarValue] = []
                evaluatedArguments.reserveCapacity(compiledArguments.count)

                for compiledArgument in compiledArguments {
                    switch compiledArgument(&context) {
                    case let .failure(error):
                        return .failure(error)
                    case let .success(value):
                        evaluatedArguments.append(value)
                    }
                }

                return dispatchExtensionCall(function, arguments: evaluatedArguments)
            }
        }
    }

    private static func stepped(
        _ body: @escaping @Sendable (inout CompiledEvalContext) -> CedarResult<CedarValue>
    ) -> Self {
        Self { context in
            switch context.consumeStep() {
            case let .failure(error):
                return .failure(error)
            case .success:
                return body(&context)
            }
        }
    }
}

internal struct CompiledBoolExpr: Sendable {
    private let evaluator: @Sendable (inout CompiledEvalContext) -> CedarResult<Bool>

    init(_ evaluator: @escaping @Sendable (inout CompiledEvalContext) -> CedarResult<Bool>) {
        self.evaluator = evaluator
    }

    @inline(__always)
    func callAsFunction(_ context: inout CompiledEvalContext) -> CedarResult<Bool> {
        evaluator(&context)
    }

    static func compile(_ expr: Expr) -> Self {
        if case let .binaryApp(.in, .variable(variable), .set(expressions)) = expr,
           variable != .context,
           let candidates = entityUIDLiterals(expressions)
        {
            return entityInAny(variable: variable, candidates: candidates)
        }

        switch expr {
        case let .lit(.prim(.bool(value))):
            return literal(value)
        case let .unaryApp(.not, operand):
            return not(compile(operand))
        case let .binaryApp(.and, lhs, rhs):
            return and(compile(lhs), compile(rhs))
        case let .binaryApp(.or, lhs, rhs):
            return or(compile(lhs), compile(rhs))
        case let .ifThenElse(condition, thenExpr, elseExpr):
            let compiledCondition = compile(condition)
            let compiledThen = compile(thenExpr)
            let compiledElse = compile(elseExpr)
            return stepped { context in
                switch compiledCondition(&context) {
                case let .failure(error):
                    return .failure(error)
                case let .success(conditionValue):
                    return conditionValue ? compiledThen(&context) : compiledElse(&context)
                }
            }
        case let .hasAttr(.variable(.context), attr):
            return stepped { context in
                switch context.consumeStep() {
                case let .failure(error):
                    return .failure(error)
                case .success:
                    break
                }

                switch context.materializedRequestContext() {
                case let .success(requestContext):
                    return .success(requestContext.contains(attr))
                case let .failure(error):
                    return .failure(.restrictedExprError(error))
                }
            }
        case let .hasAttr(.variable(variable), attr) where variable != .context:
            return stepped { context in
                switch context.consumeStep() {
                case let .failure(error):
                    return .failure(error)
                case .success:
                    break
                }

                guard let uid = context.entityUID(for: variable) else {
                    return .failure(.typeError)
                }

                return .success(context.attrsOrEmpty(for: uid).contains(attr))
            }
        case let .hasAttr(valueExpr, attr):
            let compiledValue = CompiledExpr.compile(valueExpr)
            return stepped { context in
                switch compiledValue(&context) {
                case let .success(value):
                    switch attrsOf(value, lookup: { .success(context.entities.attrsOrEmpty($0)) }) {
                    case let .success(recordValue):
                        return .success(recordValue.contains(attr))
                    case let .failure(error):
                        return .failure(error)
                    }
                case let .failure(error):
                    return .failure(error)
                }
            }
        case let .like(valueExpr, pattern):
            let compiledValue = CompiledExpr.compile(valueExpr)
            return stepped { context in
                switch compiledValue(&context) {
                case let .failure(error):
                    return .failure(error)
                case let .success(value):
                    switch value.asString() {
                    case let .failure(error):
                        return .failure(error)
                    case let .success(stringValue):
                        return .success(wildcardMatch(pattern, value: Array(stringValue.unicodeScalars)))
                    }
                }
            }
        case let .isEntityType(.variable(variable), entityType) where variable != .context:
            return matchesEntityType(variable: variable, expectedType: entityType)
        case let .isEntityType(valueExpr, entityType):
            let compiledValue = CompiledExpr.compile(valueExpr)
            return stepped { context in
                switch compiledValue(&context) {
                case let .success(value):
                    guard case let .prim(.entityUID(uid)) = value else {
                        return .failure(.typeError)
                    }

                    return .success(uid.ty == entityType)
                case let .failure(error):
                    return .failure(error)
                }
            }
        case let .binaryApp(.equal, .variable(variable), .lit(.prim(.entityUID(expected)))) where variable != .context:
            return entityEquals(variable: variable, expected: expected)
        case let .binaryApp(.in, .variable(variable), .lit(.prim(.entityUID(ancestor)))) where variable != .context:
            return entityIn(variable: variable, ancestor: ancestor)
        case let .binaryApp(.hasTag, .variable(variable), .lit(.prim(.string(tag)))) where variable != .context:
            return entityHasTag(variable: variable, tag: tag)
        case let .binaryApp(op, lhs, rhs) where op.returnsBool:
            let compiledLHS = CompiledExpr.compile(lhs)
            let compiledRHS = CompiledExpr.compile(rhs)
            return stepped { context in
                switch compiledLHS(&context) {
                case let .failure(error):
                    return .failure(error)
                case let .success(leftValue):
                    switch compiledRHS(&context) {
                    case let .failure(error):
                        return .failure(error)
                    case let .success(rightValue):
                        switch apply2(op, leftValue, rightValue, entities: context.entities, remainingSteps: &context.remainingSteps) {
                        case let .success(value):
                            return value.asBool()
                        case let .failure(error):
                            return .failure(error)
                        }
                    }
                }
            }
        default:
            let compiledValue = CompiledExpr.compile(expr)
            return Self { context in
                switch compiledValue(&context) {
                case let .success(value):
                    return value.asBool()
                case let .failure(error):
                    return .failure(error)
                }
            }
        }
    }

    static func compile(_ condition: Condition) -> Self {
        switch condition.kind {
        case .when:
            return compile(condition.body)
        case .unless:
            return not(compile(condition.body))
        }
    }

    static func compile(policy: Policy) -> Self {
        and(
            compile(policy.principalScope),
            and(
                compile(policy.actionScope),
                and(
                    compile(policy.resourceScope),
                    compile(policy.conditions)
                )
            )
        )
    }

    static func compile(_ scope: PrincipalScope) -> Self {
        switch scope {
        case .any:
            return literal(true)
        case let .eq(entity):
            return entityEquals(variable: .principal, expected: entity)
        case let .in(entity):
            return entityIn(variable: .principal, ancestor: entity)
        case let .isEntityType(entityType):
            return matchesEntityType(variable: .principal, expectedType: entityType)
        case let .isEntityTypeIn(entityType, entity):
            return and(
                matchesEntityType(variable: .principal, expectedType: entityType),
                entityIn(variable: .principal, ancestor: entity)
            )
        }
    }

    static func compile(_ scope: ResourceScope) -> Self {
        switch scope {
        case .any:
            return literal(true)
        case let .eq(entity):
            return entityEquals(variable: .resource, expected: entity)
        case let .in(entity):
            return entityIn(variable: .resource, ancestor: entity)
        case let .isEntityType(entityType):
            return matchesEntityType(variable: .resource, expectedType: entityType)
        case let .isEntityTypeIn(entityType, entity):
            return and(
                matchesEntityType(variable: .resource, expectedType: entityType),
                entityIn(variable: .resource, ancestor: entity)
            )
        }
    }

    static func compile(_ scope: ActionScope) -> Self {
        switch scope {
        case .any:
            return literal(true)
        case let .eq(entity):
            return entityEquals(variable: .action, expected: entity)
        case let .in(entity):
            return entityIn(variable: .action, ancestor: entity)
        case let .isEntityType(entityType):
            return matchesEntityType(variable: .action, expectedType: entityType)
        case let .isEntityTypeIn(entityType, entity):
            return and(
                matchesEntityType(variable: .action, expectedType: entityType),
                entityIn(variable: .action, ancestor: entity)
            )
        case let .actionInAny(entities):
            return entityInAny(variable: .action, candidates: entities.elements)
        }
    }

    static func compile(_ conditions: [Condition]) -> Self {
        guard let lastCondition = conditions.last else {
            return literal(true)
        }

        var expression = compile(lastCondition)

        for condition in conditions.dropLast().reversed() {
            expression = and(compile(condition), expression)
        }

        return expression
    }

    private static func literal(_ value: Bool) -> Self {
        stepped { _ in .success(value) }
    }

    private static func and(_ lhs: Self, _ rhs: Self) -> Self {
        stepped { context in
            switch lhs(&context) {
            case let .failure(error):
                return .failure(error)
            case let .success(booleanValue):
                return booleanValue ? rhs(&context) : .success(false)
            }
        }
    }

    private static func or(_ lhs: Self, _ rhs: Self) -> Self {
        stepped { context in
            switch lhs(&context) {
            case let .failure(error):
                return .failure(error)
            case let .success(booleanValue):
                return booleanValue ? .success(true) : rhs(&context)
            }
        }
    }

    private static func not(_ operand: Self) -> Self {
        stepped { context in
            switch operand(&context) {
            case let .success(value):
                return .success(!value)
            case let .failure(error):
                return .failure(error)
            }
        }
    }

    private static func entityEquals(variable: Var, expected: EntityUID) -> Self {
        Self { context in
            switch context.consumeStep() {
            case let .failure(error):
                return .failure(error)
            case .success:
                break
            }

            switch context.consumeStep() {
            case let .failure(error):
                return .failure(error)
            case .success:
                break
            }

            guard let actual = context.entityUID(for: variable) else {
                return .failure(.typeError)
            }

            switch context.consumeStep() {
            case let .failure(error):
                return .failure(error)
            case .success:
                return .success(actual == expected)
            }
        }
    }

    private static func entityIn(variable: Var, ancestor: EntityUID) -> Self {
        Self { context in
            switch context.consumeStep() {
            case let .failure(error):
                return .failure(error)
            case .success:
                break
            }

            switch context.consumeStep() {
            case let .failure(error):
                return .failure(error)
            case .success:
                break
            }

            guard let actual = context.entityUID(for: variable) else {
                return .failure(.typeError)
            }

            switch context.consumeStep() {
            case let .failure(error):
                return .failure(error)
            case .success:
                return inE(actual, ancestor, entities: context.entities, remainingSteps: &context.remainingSteps)
            }
        }
    }

    private static func entityInAny(variable: Var, candidates: [EntityUID]) -> Self {
        Self { context in
            switch context.consumeStep() {
            case let .failure(error):
                return .failure(error)
            case .success:
                break
            }

            switch context.consumeStep() {
            case let .failure(error):
                return .failure(error)
            case .success:
                break
            }

            guard let actual = context.entityUID(for: variable) else {
                return .failure(.typeError)
            }

            switch context.consumeStep() {
            case let .failure(error):
                return .failure(error)
            case .success:
                break
            }

            for _ in candidates {
                switch context.consumeStep() {
                case let .failure(error):
                    return .failure(error)
                case .success:
                    continue
                }
            }

            return inAnyEntity(actual, candidates: candidates, entities: context.entities, remainingSteps: &context.remainingSteps)
        }
    }

    private static func matchesEntityType(variable: Var, expectedType: Name) -> Self {
        Self { context in
            switch context.consumeStep() {
            case let .failure(error):
                return .failure(error)
            case .success:
                break
            }

            switch context.consumeStep() {
            case let .failure(error):
                return .failure(error)
            case .success:
                break
            }

            guard let actual = context.entityUID(for: variable) else {
                return .failure(.typeError)
            }

            return .success(actual.ty == expectedType)
        }
    }

    private static func entityHasTag(variable: Var, tag: Tag) -> Self {
        Self { context in
            switch context.consumeStep() {
            case let .failure(error):
                return .failure(error)
            case .success:
                break
            }

            switch context.consumeStep() {
            case let .failure(error):
                return .failure(error)
            case .success:
                break
            }

            guard let actual = context.entityUID(for: variable) else {
                return .failure(.typeError)
            }

            return .success(context.tagsOrEmpty(for: actual).contains(tag))
        }
    }

    private static func stepped(
        _ body: @escaping @Sendable (inout CompiledEvalContext) -> CedarResult<Bool>
    ) -> Self {
        Self { context in
            switch context.consumeStep() {
            case let .failure(error):
                return .failure(error)
            case .success:
                return body(&context)
            }
        }
    }
}

private extension BinaryOp {
    var returnsBool: Bool {
        switch self {
        case .equal, .lessThan, .lessThanOrEqual, .in, .contains, .containsAll, .containsAny, .hasTag:
            return true
        case .and, .or, .add, .sub, .mul, .getTag:
            return false
        }
    }
}

private func entityUIDLiterals(_ expressions: [Expr]) -> [EntityUID]? {
    var values: [EntityUID] = []
    values.reserveCapacity(expressions.count)

    for expression in expressions {
        guard case let .lit(.prim(.entityUID(uid))) = expression else {
            return nil
        }

        values.append(uid)
    }

    return values
}

@inline(__always)
private func inAnyEntity(
    _ uid: EntityUID,
    candidates: [EntityUID],
    entities: Entities,
    remainingSteps: inout Int
) -> CedarResult<Bool> {
    for candidate in candidates {
        switch inE(uid, candidate, entities: entities, remainingSteps: &remainingSteps) {
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

public struct CompiledPolicy: Sendable {
    public let id: PolicyID
    public let effect: Effect

    internal let evaluator: CompiledBoolExpr
    internal let idSet: CedarSet<PolicyID>

    public init(_ policy: Policy) {
        id = policy.id
        effect = policy.effect
        evaluator = CompiledBoolExpr.compile(policy: policy)
        idSet = CedarSet.make([policy.id])
    }

    @inline(__always)
    internal func evaluate(requestState: CompiledRequestState, entities: Entities, maxSteps: Int) -> CedarResult<Bool> {
        var context = CompiledEvalContext(requestState: requestState, remainingSteps: maxSteps)
        return evaluator(&context)
    }
}

public struct CompiledPolicies: Sendable {
    public let permits: [CompiledPolicy]
    public let forbids: [CompiledPolicy]
    internal let all: [CompiledPolicy]

    public init(_ policies: Policies) {
        var permits: [CompiledPolicy] = []
        permits.reserveCapacity(policies.count)
        var forbids: [CompiledPolicy] = []
        forbids.reserveCapacity(policies.count)
        var all: [CompiledPolicy] = []
        all.reserveCapacity(policies.count)

        for entry in policies {
            let compiledPolicy = CompiledPolicy(entry.value)
            all.append(compiledPolicy)

            switch compiledPolicy.effect {
            case .permit:
                permits.append(compiledPolicy)
            case .forbid:
                forbids.append(compiledPolicy)
            }
        }

        self.permits = permits
        self.forbids = forbids
        self.all = all
    }
}

public struct LoadedPolicies: Sendable {
    public let policies: Policies
    public let compiledPolicies: CompiledPolicies?

    public init(policies: Policies, compiledPolicies: CompiledPolicies? = nil) {
        self.policies = policies
        self.compiledPolicies = compiledPolicies
    }
}

private final class CompiledPoliciesCache: @unchecked Sendable {
    static let shared = CompiledPoliciesCache()

    private let lock = NSLock()
    private var storage: [Policies: CompiledPolicies] = [:]

    private init() {}

    func resolve(_ policies: Policies) -> CompiledPolicies {
        lock.lock()
        if let compiled = storage[policies] {
            lock.unlock()
            return compiled
        }
        lock.unlock()

        let compiled = CompiledPolicies(policies)

        lock.lock()
        if let cached = storage[policies] {
            lock.unlock()
            return cached
        }

        storage[policies] = compiled
        lock.unlock()
        return compiled
    }

    func store(_ compiled: CompiledPolicies, for policies: Policies) {
        lock.lock()
        storage[policies] = compiled
        lock.unlock()
    }
}

@inline(__always)
internal func compiledPolicies(for policies: Policies) -> CompiledPolicies {
    CompiledPoliciesCache.shared.resolve(policies)
}

internal func warmCompiledPoliciesCache(_ compiled: CompiledPolicies, for policies: Policies) {
    CompiledPoliciesCache.shared.store(compiled, for: policies)
}

public func isAuthorizedCompiled(
    request: Request,
    entities: Entities,
    compiledPolicies: CompiledPolicies
) -> Response {
    isAuthorizedCompiled(
        request: request,
        entities: entities,
        compiledPolicies: compiledPolicies,
        maxStepsPerPolicy: defaultEvaluationStepLimit
    )
}

internal func isAuthorizedCompiled(
    request: Request,
    entities: Entities,
    compiledPolicies: CompiledPolicies,
    maxStepsPerPolicy: Int
) -> Response {
    let requestState = CompiledRequestState(request: request, entities: entities)

    var firstForbid: CompiledPolicy? = nil
    var additionalForbids: [PolicyID]? = nil
    var firstPermit: CompiledPolicy? = nil
    var additionalPermits: [PolicyID]? = nil
    var firstErroring: CompiledPolicy? = nil
    var additionalErroring: [PolicyID]? = nil

    for policy in compiledPolicies.all {
        switch policy.evaluate(requestState: requestState, entities: entities, maxSteps: maxStepsPerPolicy) {
        case .success(true):
            switch policy.effect {
            case .permit:
                appendMatchedPolicy(policy, first: &firstPermit, overflow: &additionalPermits)
            case .forbid:
                appendMatchedPolicy(policy, first: &firstForbid, overflow: &additionalForbids)
            }
        case .success(false):
            break
        case .failure:
            appendMatchedPolicy(policy, first: &firstErroring, overflow: &additionalErroring)
        }
    }

    let forbids = resolvedPolicyIDSet(first: firstForbid, overflow: additionalForbids)
    let permits = resolvedPolicyIDSet(first: firstPermit, overflow: additionalPermits)
    let erroring = resolvedPolicyIDSet(first: firstErroring, overflow: additionalErroring)

    if forbids.isEmpty && !permits.isEmpty {
        return Response(decision: .allow, determining: permits, erroring: erroring)
    }

    return Response(decision: .deny, determining: forbids, erroring: erroring)
}

@inline(__always)
private func appendMatchedPolicy(
    _ policy: CompiledPolicy,
    first: inout CompiledPolicy?,
    overflow: inout [PolicyID]?
) {
    if overflow != nil {
        overflow!.append(policy.id)
        return
    }

    if let first {
        overflow = [first.id, policy.id]
        return
    }

    first = policy
}

@inline(__always)
private func resolvedPolicyIDSet(first: CompiledPolicy?, overflow: [PolicyID]?) -> CedarSet<PolicyID> {
    if let overflow {
        return CedarSet.make(overflow)
    }

    if let first {
        return first.idSet
    }

    return .empty
}
