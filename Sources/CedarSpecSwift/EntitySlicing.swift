public func sliceEUIDs(_ value: CedarValue) -> CedarSet<EntityUID> {
    switch value {
    case let .prim(.entityUID(uid)):
        return .make([uid])
    case let .set(values):
        return CedarSet.make(values.elements.flatMap { sliceEUIDs($0).elements })
    case let .record(record):
        return CedarSet.make(record.values.flatMap { sliceEUIDs($0).elements })
    case .prim, .ext:
        return .empty
    }
}

public func sliceEUIDs(_ expr: Expr) -> CedarSet<EntityUID> {
    switch expr {
    case let .lit(value):
        return sliceEUIDs(value)
    case .variable:
        return .empty
    case let .unaryApp(_, operand):
        return sliceEUIDs(operand)
    case let .binaryApp(_, lhs, rhs):
        return CedarSet.make(sliceEUIDs(lhs).elements + sliceEUIDs(rhs).elements)
    case let .ifThenElse(condition, thenExpr, elseExpr):
        return CedarSet.make(
            sliceEUIDs(condition).elements
                + sliceEUIDs(thenExpr).elements
                + sliceEUIDs(elseExpr).elements
        )
    case let .set(values):
        return CedarSet.make(values.flatMap { sliceEUIDs($0).elements })
    case let .record(entries):
        return CedarSet.make(entries.flatMap { sliceEUIDs($0.value).elements })
    case let .hasAttr(value, _), let .getAttr(value, _), let .like(value, _), let .isEntityType(value, _):
        return sliceEUIDs(value)
    case let .call(_, arguments):
        return CedarSet.make(arguments.flatMap { sliceEUIDs($0).elements })
    }
}

public func sliceEUIDs(_ expr: Expr, request: Request) -> CedarSet<EntityUID> {
    switch expr {
    case let .lit(value):
        return sliceEUIDs(value)
    case let .variable(variable):
        switch variable {
        case .principal:
            return .make([request.principal])
        case .action:
            return .make([request.action])
        case .resource:
            return .make([request.resource])
        case .context:
            return sliceEUIDs(request.context)
        }
    case let .unaryApp(_, operand):
        return sliceEUIDs(operand, request: request)
    case let .binaryApp(_, lhs, rhs):
        return CedarSet.make(sliceEUIDs(lhs, request: request).elements + sliceEUIDs(rhs, request: request).elements)
    case let .ifThenElse(condition, thenExpr, elseExpr):
        return CedarSet.make(
            sliceEUIDs(condition, request: request).elements
                + sliceEUIDs(thenExpr, request: request).elements
                + sliceEUIDs(elseExpr, request: request).elements
        )
    case let .set(values):
        return CedarSet.make(values.flatMap { sliceEUIDs($0, request: request).elements })
    case let .record(entries):
        return CedarSet.make(entries.flatMap { sliceEUIDs($0.value, request: request).elements })
    case let .hasAttr(value, _), let .getAttr(value, _), let .like(value, _), let .isEntityType(value, _):
        return sliceEUIDs(value, request: request)
    case let .call(_, arguments):
        return CedarSet.make(arguments.flatMap { sliceEUIDs($0, request: request).elements })
    }
}

public func sliceEUIDs(_ expr: RestrictedExpr) -> CedarSet<EntityUID> {
    switch expr {
    case let .entityUID(uid):
        return .make([uid])
    case let .set(values):
        return CedarSet.make(values.elements.flatMap { sliceEUIDs($0).elements })
    case let .record(entries):
        return CedarSet.make(entries.values.flatMap { sliceEUIDs($0).elements })
    case let .call(_, arguments):
        return CedarSet.make(arguments.flatMap { sliceEUIDs($0).elements })
    case .bool, .int, .string:
        return .empty
    }
}

public func sliceEUIDs(_ request: Request) -> CedarSet<EntityUID> {
    CedarSet.make([request.principal, request.action, request.resource] + sliceEUIDs(request.context).elements)
}

public func sliceEUIDs(_ policy: Policy) -> CedarSet<EntityUID> {
    CedarSet.make(
        sliceEUIDs(policy.principalScope).elements
            + sliceEUIDs(policy.actionScope).elements
            + sliceEUIDs(policy.resourceScope).elements
            + policy.conditions.flatMap { sliceEUIDs($0.body).elements }
    )
}

public func sliceEUIDs(_ policy: Policy, request: Request) -> CedarSet<EntityUID> {
    sliceEUIDs(policy.toExpr(), request: request)
}

public func sliceEUIDs(_ policies: Policies) -> CedarSet<EntityUID> {
    CedarSet.make(policies.values.flatMap { sliceEUIDs($0).elements })
}

public func sliceEUIDs(_ policies: Policies, request: Request) -> CedarSet<EntityUID> {
    CedarSet.make(policies.values.flatMap { sliceEUIDs($0, request: request).elements })
}

public func sliceEUIDs(_ template: Template) -> CedarSet<EntityUID> {
    CedarSet.make(
        sliceEUIDs(template.principalScope).elements
            + sliceEUIDs(template.actionScope).elements
            + sliceEUIDs(template.resourceScope).elements
            + template.conditions.flatMap { sliceEUIDs($0.body).elements }
    )
}

public func sliceAtLevel(
    _ seeds: CedarSet<EntityUID>,
    entities: Entities,
    level: Int
) -> EntitySlice {
    let boundedLevel = max(level, 0)
    var required = seeds.elements
    var frontier = seeds.elements
    var currentLevel = 0

    while currentLevel < boundedLevel, !frontier.isEmpty {
        var nextFrontier: [EntityUID] = []

        for uid in frontier {
            guard let data = entities.entries.find(uid) else {
                continue
            }

            let adjacent = CedarSet.make(
                data.ancestors.elements
                    + sliceEUIDs(data.attrs.values).elements
                    + sliceEUIDs(data.tags.values).elements
            )

            for candidate in adjacent.elements where !required.contains(where: { $0 == candidate }) {
                required.append(candidate)
                nextFrontier.append(candidate)
            }
        }

        frontier = nextFrontier
        currentLevel += 1
    }

    let requiredSet = CedarSet.make(required)
    return EntitySlice(
        required: requiredSet,
        entities: Entities(CedarMap.make(requiredSet.elements.compactMap { uid in
            entities.entries.find(uid).map { (key: uid, value: $0) }
        }))
    )
}

private func sliceEUIDs(_ values: [CedarValue]) -> CedarSet<EntityUID> {
    CedarSet.make(values.flatMap { sliceEUIDs($0).elements })
}

private func sliceEUIDs(_ scope: PrincipalScope) -> CedarSet<EntityUID> {
    switch scope {
    case .any, .isEntityType:
        return .empty
    case let .eq(entity), let .in(entity), let .isEntityTypeIn(_, entity):
        return .make([entity])
    }
}

private func sliceEUIDs(_ scope: ActionScope) -> CedarSet<EntityUID> {
    switch scope {
    case .any, .isEntityType:
        return .empty
    case let .eq(entity), let .in(entity), let .isEntityTypeIn(_, entity):
        return .make([entity])
    case let .actionInAny(entities):
        return entities
    }
}

private func sliceEUIDs(_ scope: ResourceScope) -> CedarSet<EntityUID> {
    switch scope {
    case .any, .isEntityType:
        return .empty
    case let .eq(entity), let .in(entity), let .isEntityTypeIn(_, entity):
        return .make([entity])
    }
}

private func sliceEUIDs(_ scope: PrincipalScopeTemplate) -> CedarSet<EntityUID> {
    sliceEUIDs(scope.scope)
}

private func sliceEUIDs(_ scope: ResourceScopeTemplate) -> CedarSet<EntityUID> {
    sliceEUIDs(scope.scope)
}

private func sliceEUIDs(_ scope: ScopeTemplate) -> CedarSet<EntityUID> {
    switch scope {
    case .any, .isEntityType:
        return .empty
    case let .eq(value), let .in(value), let .isEntityTypeIn(_, value):
        return sliceEUIDs(value)
    }
}

private func sliceEUIDs(_ scopeValue: EntityUIDOrSlot) -> CedarSet<EntityUID> {
    switch scopeValue {
    case let .entityUID(uid):
        return .make([uid])
    case .slot:
        return .empty
    }
}