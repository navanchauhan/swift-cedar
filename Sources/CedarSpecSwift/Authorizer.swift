internal typealias PolicyEvaluation = (Policy, Request, Entities) -> CedarResult<CedarValue>

private func evaluatePolicy(_ policy: Policy, request: Request, entities: Entities) -> CedarResult<CedarValue> {
    evaluate(policy.toExpr(), request: request, entities: entities)
}

internal func satisfied(_ policy: Policy, _ request: Request, _ entities: Entities) -> Bool {
    satisfied(policy, request, entities, evaluatePolicy: evaluatePolicy)
}

internal func satisfied(
    _ policy: Policy,
    _ request: Request,
    _ entities: Entities,
    evaluatePolicy: PolicyEvaluation
) -> Bool {
    evaluatePolicy(policy, request, entities) == .success(.prim(.bool(true)))
}

internal func satisfiedWithEffect(
    _ effect: Effect,
    _ policy: Policy,
    _ request: Request,
    _ entities: Entities
) -> PolicyID? {
    satisfiedWithEffect(effect, policy, request, entities, evaluatePolicy: evaluatePolicy)
}

internal func satisfiedWithEffect(
    _ effect: Effect,
    _ policy: Policy,
    _ request: Request,
    _ entities: Entities,
    evaluatePolicy: PolicyEvaluation
) -> PolicyID? {
    if policy.effect == effect && satisfied(policy, request, entities, evaluatePolicy: evaluatePolicy) {
        return policy.id
    }

    return nil
}

internal func satisfiedPolicies(
    _ effect: Effect,
    _ policies: Policies,
    _ request: Request,
    _ entities: Entities
) -> CedarSet<PolicyID> {
    satisfiedPolicies(effect, policies, request, entities, evaluatePolicy: evaluatePolicy)
}

internal func satisfiedPolicies(
    _ effect: Effect,
    _ policies: Policies,
    _ request: Request,
    _ entities: Entities,
    evaluatePolicy: PolicyEvaluation
) -> CedarSet<PolicyID> {
    CedarSet.make(policies.compactMap { entry in
        satisfiedWithEffect(effect, entry.value, request, entities, evaluatePolicy: evaluatePolicy)
    })
}

internal func hasError(_ policy: Policy, _ request: Request, _ entities: Entities) -> Bool {
    hasError(policy, request, entities, evaluatePolicy: evaluatePolicy)
}

internal func hasError(
    _ policy: Policy,
    _ request: Request,
    _ entities: Entities,
    evaluatePolicy: PolicyEvaluation
) -> Bool {
    switch evaluatePolicy(policy, request, entities) {
    case .success:
        false
    case .failure:
        true
    }
}

internal func errored(_ policy: Policy, _ request: Request, _ entities: Entities) -> PolicyID? {
    errored(policy, request, entities, evaluatePolicy: evaluatePolicy)
}

internal func errored(
    _ policy: Policy,
    _ request: Request,
    _ entities: Entities,
    evaluatePolicy: PolicyEvaluation
) -> PolicyID? {
    if hasError(policy, request, entities, evaluatePolicy: evaluatePolicy) {
        return policy.id
    }

    return nil
}

internal func errorPolicies(_ policies: Policies, _ request: Request, _ entities: Entities) -> CedarSet<PolicyID> {
    errorPolicies(policies, request, entities, evaluatePolicy: evaluatePolicy)
}

internal func errorPolicies(
    _ policies: Policies,
    _ request: Request,
    _ entities: Entities,
    evaluatePolicy: PolicyEvaluation
) -> CedarSet<PolicyID> {
    CedarSet.make(policies.compactMap { entry in
        errored(entry.value, request, entities, evaluatePolicy: evaluatePolicy)
    })
}

public func isAuthorized(request: Request, entities: Entities, policies: Policies) -> Response {
    isAuthorizedCompiled(
        request: request,
        entities: entities,
        policies: policies
    )
}

public func isAuthorizedCompiled(request: Request, entities: Entities, policies: Policies) -> Response {
    isAuthorizedCompiled(
        request: request,
        entities: entities,
        compiledPolicies: compiledPolicies(for: policies)
    )
}

internal func isAuthorized(
    request: Request,
    entities: Entities,
    policies: Policies,
    maxStepsPerPolicy: Int
) -> Response {
    isAuthorizedCompiled(
        request: request,
        entities: entities,
        policies: policies,
        maxStepsPerPolicy: maxStepsPerPolicy
    )
}

internal func isAuthorizedCompiled(
    request: Request,
    entities: Entities,
    policies: Policies,
    maxStepsPerPolicy: Int
) -> Response {
    isAuthorizedCompiled(
        request: request,
        entities: entities,
        compiledPolicies: compiledPolicies(for: policies),
        maxStepsPerPolicy: maxStepsPerPolicy
    )
}

internal func isAuthorized(
    request: Request,
    entities: Entities,
    policies: Policies,
    evaluatePolicy: PolicyEvaluation
) -> Response {
    let forbids = satisfiedPolicies(.forbid, policies, request, entities, evaluatePolicy: evaluatePolicy)
    let permits = satisfiedPolicies(.permit, policies, request, entities, evaluatePolicy: evaluatePolicy)
    let erroring = errorPolicies(policies, request, entities, evaluatePolicy: evaluatePolicy)

    if forbids.isEmpty && !permits.isEmpty {
        return Response(decision: .allow, determining: permits, erroring: erroring)
    }

    return Response(decision: .deny, determining: forbids, erroring: erroring)
}
