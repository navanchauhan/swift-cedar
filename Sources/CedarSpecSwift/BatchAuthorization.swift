public enum BatchVariableKind: Int, CaseIterable, Equatable, Comparable, Sendable {
    case entityUID
    case context

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum BatchVariableValue: Equatable, Sendable {
    case entityUID(EntityUID)
    case context(RestrictedExpr)

    public var kind: BatchVariableKind {
        switch self {
        case .entityUID:
            return .entityUID
        case .context:
            return .context
        }
    }
}

public enum BatchEntitySlot: Equatable, Hashable, Sendable {
    case value(EntityUID)
    case variable(String)
}

public enum BatchContextSlot: Equatable, Sendable {
    case value(RestrictedExpr)
    case variable(String)
}

public typealias BatchBindings = CedarMap<String, BatchVariableValue>
public typealias BatchVariableDomains = CedarMap<String, [BatchVariableValue]>

public struct BatchRequestTemplate: Equatable, Sendable {
    public let principal: BatchEntitySlot
    public let action: BatchEntitySlot
    public let resource: BatchEntitySlot
    public let context: BatchContextSlot

    public init(
        principal: BatchEntitySlot,
        action: BatchEntitySlot,
        resource: BatchEntitySlot,
        context: BatchContextSlot = .value(.emptyRecord)
    ) {
        self.principal = principal
        self.action = action
        self.resource = resource
        self.context = context
    }

    public init(
        principal: EntityUID,
        action: EntityUID,
        resource: EntityUID,
        context: RestrictedExpr = .emptyRecord
    ) {
        self.init(
            principal: .value(principal),
            action: .value(action),
            resource: .value(resource),
            context: .value(context)
        )
    }

    public var variables: CedarSet<String> {
        CedarSet.make(entityVariableNames + contextVariableNames)
    }

    public func bind(_ bindings: BatchBindings) -> Result<Request, BatchAuthorizationError> {
        let principalResult = bindEntitySlot(principal, bindings: bindings)
        let actionResult = bindEntitySlot(action, bindings: bindings)
        let resourceResult = bindEntitySlot(resource, bindings: bindings)
        let contextResult = bindContextSlot(context, bindings: bindings)

        guard case let .success(principalUID) = principalResult else {
            return .failure(principalResult.failureValue!)
        }
        guard case let .success(actionUID) = actionResult else {
            return .failure(actionResult.failureValue!)
        }
        guard case let .success(resourceUID) = resourceResult else {
            return .failure(resourceResult.failureValue!)
        }
        guard case let .success(contextValue) = contextResult else {
            return .failure(contextResult.failureValue!)
        }

        return .success(Request(
            principal: principalUID,
            action: actionUID,
            resource: resourceUID,
            context: contextValue
        ))
    }

    fileprivate var variableKinds: Result<[String: BatchVariableKind], BatchAuthorizationError> {
        var result: [String: BatchVariableKind] = [:]

        for (name, kind) in entityVariables {
            if let existing = result[name], existing != kind {
                return .failure(.conflictingVariableKinds(name))
            }
            result[name] = kind
        }

        for (name, kind) in contextVariables {
            if let existing = result[name], existing != kind {
                return .failure(.conflictingVariableKinds(name))
            }
            result[name] = kind
        }

        return .success(result)
    }

    private var entityVariables: [(String, BatchVariableKind)] {
        entityVariableNames.map { ($0, .entityUID) }
    }

    private var contextVariables: [(String, BatchVariableKind)] {
        contextVariableNames.map { ($0, .context) }
    }

    private var entityVariableNames: [String] {
        [principal, action, resource].compactMap {
            if case let .variable(name) = $0 {
                return name
            }
            return nil
        }
    }

    private var contextVariableNames: [String] {
        if case let .variable(name) = context {
            return [name]
        }
        return []
    }
}

public struct BatchAuthorizationEntry: Equatable, Sendable {
    public let bindings: BatchBindings
    public let request: Request
    public let response: Response

    public init(bindings: BatchBindings, request: Request, response: Response) {
        self.bindings = bindings
        self.request = request
        self.response = response
    }
}

public enum BatchAuthorizationError: Error, Equatable, Sendable {
    case unboundVariables(CedarSet<String>)
    case unusedVariables(CedarSet<String>)
    case emptyDomain(String)
    case conflictingVariableKinds(String)
    case invalidBinding(variable: String, expected: BatchVariableKind, actual: BatchVariableKind)
}

extension BatchAuthorizationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .unboundVariables(variables):
            return "Unbound batch variables: \(variables.elements.joined(separator: ", "))"
        case let .unusedVariables(variables):
            return "Unused batch variables: \(variables.elements.joined(separator: ", "))"
        case let .emptyDomain(variable):
            return "Batch variable '\(variable)' has an empty domain"
        case let .conflictingVariableKinds(variable):
            return "Batch variable '\(variable)' is used with incompatible slot kinds"
        case let .invalidBinding(variable, expected, actual):
            return "Batch variable '\(variable)' expected \(expected) but received \(actual)"
        }
    }
}

public func batchAuthorize(
    template: BatchRequestTemplate,
    domains: BatchVariableDomains,
    entities: Entities,
    policies: Policies
) -> Result<[BatchAuthorizationEntry], BatchAuthorizationError> {
    var entries: [BatchAuthorizationEntry] = []

    switch batchAuthorize(template: template, domains: domains, entities: entities, policies: policies, visit: { entry in
        entries.append(entry)
    }) {
    case .success:
        return .success(entries)
    case let .failure(error):
        return .failure(error)
    }
}

public func batchAuthorize(
    template: BatchRequestTemplate,
    domains: BatchVariableDomains,
    entities: Entities,
    policies: Policies,
    visit: (BatchAuthorizationEntry) -> Void
) -> Result<Int, BatchAuthorizationError> {
    let variableKinds: [String: BatchVariableKind]
    switch template.variableKinds {
    case let .success(kinds):
        variableKinds = kinds
    case let .failure(error):
        return .failure(error)
    }

    let templateVariables = CedarSet.make(Array(variableKinds.keys))
    let domainVariables = domains.keys
    let unboundVariables = CedarSet.make(templateVariables.elements.filter { !domainVariables.contains($0) })
    guard unboundVariables.isEmpty else {
        return .failure(.unboundVariables(unboundVariables))
    }

    let unusedVariables = CedarSet.make(domainVariables.elements.filter { !templateVariables.contains($0) })
    guard unusedVariables.isEmpty else {
        return .failure(.unusedVariables(unusedVariables))
    }

    let variableOrder = templateVariables.elements
    for variable in variableOrder {
        guard let domain = domains.find(variable) else {
            return .failure(.unboundVariables(.make([variable])))
        }
        guard !domain.isEmpty else {
            return .failure(.emptyDomain(variable))
        }
        guard let expectedKind = variableKinds[variable] else {
            continue
        }
        for value in domain where value.kind != expectedKind {
            return .failure(.invalidBinding(variable: variable, expected: expectedKind, actual: value.kind))
        }
    }

    var count = 0
    enumerateBindings(variableOrder: variableOrder, domains: domains, current: []) { entries in
        let bindings = CedarMap.make(entries)
        guard case let .success(request) = template.bind(bindings) else {
            return
        }
        let response = isAuthorized(request: request, entities: entities, policies: policies)
        visit(BatchAuthorizationEntry(bindings: bindings, request: request, response: response))
        count += 1
    }

    return .success(count)
}

private func enumerateBindings(
    variableOrder: [String],
    domains: BatchVariableDomains,
    current: [(key: String, value: BatchVariableValue)],
    visit: ([(key: String, value: BatchVariableValue)]) -> Void
) {
    guard let variable = variableOrder.first else {
        visit(current)
        return
    }

    let remainingVariables = Array(variableOrder.dropFirst())
    guard let domain = domains.find(variable) else {
        return
    }

    for value in domain {
        enumerateBindings(
            variableOrder: remainingVariables,
            domains: domains,
            current: current + [(key: variable, value: value)],
            visit: visit
        )
    }
}

private func bindEntitySlot(_ slot: BatchEntitySlot, bindings: BatchBindings) -> Result<EntityUID, BatchAuthorizationError> {
    switch slot {
    case let .value(uid):
        return .success(uid)
    case let .variable(name):
        guard let value = bindings.find(name) else {
            return .failure(.unboundVariables(.make([name])))
        }
        switch value {
        case let .entityUID(uid):
            return .success(uid)
        case let .context(context):
            return .failure(.invalidBinding(variable: name, expected: .entityUID, actual: BatchVariableValue.context(context).kind))
        }
    }
}

private func bindContextSlot(_ slot: BatchContextSlot, bindings: BatchBindings) -> Result<RestrictedExpr, BatchAuthorizationError> {
    switch slot {
    case let .value(context):
        return .success(context)
    case let .variable(name):
        guard let value = bindings.find(name) else {
            return .failure(.unboundVariables(.make([name])))
        }
        switch value {
        case let .context(context):
            return .success(context)
        case let .entityUID(uid):
            return .failure(.invalidBinding(variable: name, expected: .context, actual: BatchVariableValue.entityUID(uid).kind))
        }
    }
}

private extension Result {
    var failureValue: Failure? {
        switch self {
        case .success:
            return nil
        case let .failure(error):
            return error
        }
    }
}