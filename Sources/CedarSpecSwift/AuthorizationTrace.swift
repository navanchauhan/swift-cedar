public enum AuthorizationPolicyOutcome: Int, CaseIterable, Equatable, Hashable, Comparable, Sendable {
    case notSatisfied
    case satisfied
    case error

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct AuthorizationPolicyTrace: Equatable, Hashable, Sendable {
    public let policyID: PolicyID
    public let effect: Effect
    public let outcome: AuthorizationPolicyOutcome
    public let error: CedarError?

    public init(
        policyID: PolicyID,
        effect: Effect,
        outcome: AuthorizationPolicyOutcome,
        error: CedarError? = nil
    ) {
        self.policyID = policyID
        self.effect = effect
        self.outcome = outcome
        self.error = error
    }
}

public struct AuthorizationTrace: Equatable, Hashable, Sendable {
    public let response: Response
    public let evaluations: [AuthorizationPolicyTrace]

    public init(response: Response, evaluations: [AuthorizationPolicyTrace]) {
        self.response = response
        self.evaluations = evaluations
    }

    public var matched: CedarSet<PolicyID> {
        CedarSet.make(evaluations.compactMap { trace in
            trace.outcome == .satisfied ? trace.policyID : nil
        })
    }

    public var satisfied: [AuthorizationPolicyTrace] {
        evaluations.filter { $0.outcome == .satisfied }
    }

    public var unsatisfied: [AuthorizationPolicyTrace] {
        evaluations.filter { $0.outcome == .notSatisfied }
    }

    public var errored: [AuthorizationPolicyTrace] {
        evaluations.filter { $0.outcome == .error }
    }

    public var determiningEvaluations: [AuthorizationPolicyTrace] {
        evaluations.filter { response.determining.contains($0.policyID) }
    }

    public var errors: CedarMap<PolicyID, CedarError> {
        CedarMap.make(evaluations.compactMap { trace in
            trace.error.map { (key: trace.policyID, value: $0) }
        })
    }
}

public func traceAuthorization(request: Request, entities: Entities, policies: Policies) -> AuthorizationTrace {
    traceAuthorization(request: request, entities: entities, policies: policies, evaluatePolicy: { policy, request, entities in
        evaluate(policy.toExpr(), request: request, entities: entities)
    })
}

public func traceAuthorization(
    request: Request,
    entities: Entities,
    policies: Policies,
    maxStepsPerPolicy: Int
) -> AuthorizationTrace {
    traceAuthorization(request: request, entities: entities, policies: policies, evaluatePolicy: { policy, request, entities in
        evaluate(policy.toExpr(), request: request, entities: entities, maxSteps: maxStepsPerPolicy)
    })
}

internal func traceAuthorization(
    request: Request,
    entities: Entities,
    policies: Policies,
    evaluatePolicy: PolicyEvaluation
) -> AuthorizationTrace {
    var permitMatches: [PolicyID] = []
    var forbidMatches: [PolicyID] = []
    var errors: [PolicyID] = []
    var evaluations: [AuthorizationPolicyTrace] = []
    evaluations.reserveCapacity(policies.count)

    for entry in policies {
        switch evaluatePolicy(entry.value, request, entities) {
        case let .success(result):
            if result == .prim(.bool(true)) {
                evaluations.append(AuthorizationPolicyTrace(
                    policyID: entry.value.id,
                    effect: entry.value.effect,
                    outcome: .satisfied
                ))
                if entry.value.effect == .permit {
                    permitMatches.append(entry.value.id)
                } else {
                    forbidMatches.append(entry.value.id)
                }
            } else {
                evaluations.append(AuthorizationPolicyTrace(
                    policyID: entry.value.id,
                    effect: entry.value.effect,
                    outcome: .notSatisfied
                ))
            }
        case let .failure(error):
            evaluations.append(AuthorizationPolicyTrace(
                policyID: entry.value.id,
                effect: entry.value.effect,
                outcome: .error,
                error: error
            ))
            errors.append(entry.value.id)
        }
    }

    let response: Response
    if forbidMatches.isEmpty && !permitMatches.isEmpty {
        response = Response(
            decision: .allow,
            determining: CedarSet.make(permitMatches),
            erroring: CedarSet.make(errors)
        )
    } else {
        response = Response(
            decision: .deny,
            determining: CedarSet.make(forbidMatches),
            erroring: CedarSet.make(errors)
        )
    }

    return AuthorizationTrace(response: response, evaluations: evaluations)
}
