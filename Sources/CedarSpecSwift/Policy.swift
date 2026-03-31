public typealias PolicyID = String
public typealias Policies = CedarMap<PolicyID, Policy>

public enum Effect: Int, CaseIterable, Equatable, Hashable, Comparable, Sendable {
    case permit
    case forbid

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum ConditionKind: Int, CaseIterable, Equatable, Hashable, Comparable, Sendable {
    case `when`
    case unless

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

private enum Scope {
    case any
    case eq(EntityUID)
    case `in`(EntityUID)
    case isEntityType(EntityType)
    case isEntityTypeIn(EntityType, EntityUID)

    func toExpr(variable: Var) -> Expr {
        switch self {
        case .any:
            return .lit(.prim(.bool(true)))
        case let .eq(entity):
            return .binaryApp(.equal, .variable(variable), .lit(.prim(.entityUID(entity))))
        case let .in(entity):
            return .binaryApp(.in, .variable(variable), .lit(.prim(.entityUID(entity))))
        case let .isEntityType(entityType):
            return .isEntityType(.variable(variable), entityType)
        case let .isEntityTypeIn(entityType, entity):
            return .binaryApp(
                .and,
                .isEntityType(.variable(variable), entityType),
                .binaryApp(.in, .variable(variable), .lit(.prim(.entityUID(entity))))
            )
        }
    }
}

public enum PrincipalScope: Equatable, Hashable, Sendable {
    case any
    case eq(entity: EntityUID)
    case `in`(entity: EntityUID)
    case isEntityType(entityType: EntityType)
    case isEntityTypeIn(entityType: EntityType, entity: EntityUID)

    fileprivate var scope: Scope {
        switch self {
        case .any:
            return .any
        case let .eq(entity):
            return .eq(entity)
        case let .in(entity):
            return .in(entity)
        case let .isEntityType(entityType):
            return .isEntityType(entityType)
        case let .isEntityTypeIn(entityType, entity):
            return .isEntityTypeIn(entityType, entity)
        }
    }

    func toExpr() -> Expr {
        scope.toExpr(variable: .principal)
    }
}

public enum ResourceScope: Equatable, Hashable, Sendable {
    case any
    case eq(entity: EntityUID)
    case `in`(entity: EntityUID)
    case isEntityType(entityType: EntityType)
    case isEntityTypeIn(entityType: EntityType, entity: EntityUID)

    fileprivate var scope: Scope {
        switch self {
        case .any:
            return .any
        case let .eq(entity):
            return .eq(entity)
        case let .in(entity):
            return .in(entity)
        case let .isEntityType(entityType):
            return .isEntityType(entityType)
        case let .isEntityTypeIn(entityType, entity):
            return .isEntityTypeIn(entityType, entity)
        }
    }

    func toExpr() -> Expr {
        scope.toExpr(variable: .resource)
    }
}

public enum ActionScope: Equatable, Hashable, Sendable {
    case any
    case eq(entity: EntityUID)
    case `in`(entity: EntityUID)
    case isEntityType(entityType: EntityType)
    case isEntityTypeIn(entityType: EntityType, entity: EntityUID)
    case actionInAny(entities: CedarSet<EntityUID>)

    fileprivate var scope: Scope? {
        switch self {
        case .any:
            return .any
        case let .eq(entity):
            return .eq(entity)
        case let .in(entity):
            return .in(entity)
        case let .isEntityType(entityType):
            return .isEntityType(entityType)
        case let .isEntityTypeIn(entityType, entity):
            return .isEntityTypeIn(entityType, entity)
        case .actionInAny:
            return nil
        }
    }

    func toExpr() -> Expr {
        if let scope {
            return scope.toExpr(variable: .action)
        }

        switch self {
        case let .actionInAny(entities):
            return .binaryApp(
                .in,
                .variable(.action),
                .set(entities.elements.map { .lit(.prim(.entityUID($0))) })
            )
        default:
            return .lit(.prim(.bool(true)))
        }
    }
}

public struct Condition: Equatable, Hashable, Sendable {
    public let kind: ConditionKind
    public let body: Expr

    public init(kind: ConditionKind, body: Expr) {
        self.kind = kind
        self.body = body
    }

    func toExpr() -> Expr {
        switch kind {
        case .when:
            return body
        case .unless:
            return .unaryApp(.not, body)
        }
    }
}

public struct Policy: Sendable {
    public let id: PolicyID
    public let annotations: CedarMap<String, String>
    public let effect: Effect
    public let principalScope: PrincipalScope
    public let actionScope: ActionScope
    public let resourceScope: ResourceScope
    public let conditions: [Condition]

    public init(
        id: PolicyID,
        annotations: CedarMap<String, String> = .empty,
        effect: Effect,
        principalScope: PrincipalScope,
        actionScope: ActionScope,
        resourceScope: ResourceScope,
        conditions: [Condition] = []
    ) {
        self.id = id
        self.annotations = annotations
        self.effect = effect
        self.principalScope = principalScope
        self.actionScope = actionScope
        self.resourceScope = resourceScope
        self.conditions = conditions
    }

    public func toExpr() -> Expr {
        .binaryApp(
            .and,
            principalScope.toExpr(),
            .binaryApp(
                .and,
                actionScope.toExpr(),
                .binaryApp(
                    .and,
                    resourceScope.toExpr(),
                    conditionsToExpr(conditions)
                )
            )
        )
    }
}

extension Policy: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        cedarStringEqual(lhs.id, rhs.id)
            && lhs.annotations == rhs.annotations
            && lhs.effect == rhs.effect
            && lhs.principalScope == rhs.principalScope
            && lhs.actionScope == rhs.actionScope
            && lhs.resourceScope == rhs.resourceScope
            && lhs.conditions == rhs.conditions
    }
}

extension Policy: Hashable {
    public func hash(into hasher: inout Hasher) {
        cedarHashString(id, into: &hasher)
        hasher.combine(annotations)
        hasher.combine(effect)
        hasher.combine(principalScope)
        hasher.combine(actionScope)
        hasher.combine(resourceScope)
        hasher.combine(conditions)
    }
}

private func conditionsToExpr(_ conditions: [Condition]) -> Expr {
    guard let lastCondition = conditions.last else {
        return .lit(.prim(.bool(true)))
    }

    var expression = lastCondition.toExpr()

    for condition in conditions.dropLast().reversed() {
        expression = .binaryApp(.and, condition.toExpr(), expression)
    }

    return expression
}
