public func linkPolicy(template: Template, slotEnv: SlotEnv) -> LoadResult<Policy> {
    let diagnostics = Diagnostics(linkTemplateScopeDiagnostics(template: template, slotEnv: slotEnv))
    guard diagnostics.isEmpty else {
        return .failure(diagnostics)
    }

    guard let principalScope = linkPrincipalScope(template.principalScope.scope, slotEnv: slotEnv, sourceSpan: nil).value,
          let resourceScope = linkResourceScope(template.resourceScope.scope, slotEnv: slotEnv, sourceSpan: nil).value
    else {
        return .failure(diagnostics)
    }

    return .success(
        Policy(
            id: template.id,
            annotations: template.annotations,
            effect: template.effect,
            principalScope: principalScope,
            actionScope: template.actionScope,
            resourceScope: resourceScope,
            conditions: template.conditions
        ),
        diagnostics: .empty
    )
}

public func link(templateLinkedPolicy: TemplateLinkedPolicy, templates: Templates) -> LoadResult<Policy> {
    guard let template = templates.find(templateLinkedPolicy.templateID) else {
        return .failure(Diagnostics([
            Diagnostic(
                code: "template.unknownTemplate",
                category: .template,
                severity: .error,
                message: "Template \(templateLinkedPolicy.templateID) does not exist"
            )
        ]))
    }

    let linkedResult = linkPolicy(template: template, slotEnv: templateLinkedPolicy.slotEnv)
    switch linkedResult {
    case let .success(policy, diagnostics):
        let mergedAnnotations = template.annotations.appending(contentsOf: templateLinkedPolicy.annotations)
        return .success(
            Policy(
                id: templateLinkedPolicy.id,
                annotations: mergedAnnotations,
                effect: policy.effect,
                principalScope: policy.principalScope,
                actionScope: policy.actionScope,
                resourceScope: policy.resourceScope,
                conditions: policy.conditions
            ),
            diagnostics: diagnostics
        )
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }
}

private func linkTemplateScopeDiagnostics(template: Template, slotEnv: SlotEnv) -> [Diagnostic] {
    var diagnostics: [Diagnostic] = []

    if let diagnostic = linkPrincipalScope(template.principalScope.scope, slotEnv: slotEnv, sourceSpan: nil).diagnostics.first {
        diagnostics.append(diagnostic)
    }

    if let diagnostic = linkResourceScope(template.resourceScope.scope, slotEnv: slotEnv, sourceSpan: nil).diagnostics.first {
        diagnostics.append(diagnostic)
    }

    return diagnostics
}

private struct LinkedScope<ResultValue> {
    let value: ResultValue?
    let diagnostics: Diagnostics
}

private func linkPrincipalScope(
    _ scope: ScopeTemplate,
    slotEnv: SlotEnv,
    sourceSpan: SourceSpan?
) -> LinkedScope<PrincipalScope> {
    switch scope {
    case .any:
        return LinkedScope(value: .any, diagnostics: .empty)
    case let .eq(reference):
        switch resolve(reference, slotEnv: slotEnv, sourceSpan: sourceSpan) {
        case let .success(uid):
            return LinkedScope(value: .eq(entity: uid), diagnostics: .empty)
        case let .failure(diagnostics):
            return LinkedScope(value: nil, diagnostics: diagnostics)
        }
    case let .in(reference):
        switch resolve(reference, slotEnv: slotEnv, sourceSpan: sourceSpan) {
        case let .success(uid):
            return LinkedScope(value: .in(entity: uid), diagnostics: .empty)
        case let .failure(diagnostics):
            return LinkedScope(value: nil, diagnostics: diagnostics)
        }
    case let .isEntityType(entityType):
        return LinkedScope(value: .isEntityType(entityType: entityType), diagnostics: .empty)
    case let .isEntityTypeIn(entityType, reference):
        switch resolve(reference, slotEnv: slotEnv, sourceSpan: sourceSpan) {
        case let .success(uid):
            return LinkedScope(value: .isEntityTypeIn(entityType: entityType, entity: uid), diagnostics: .empty)
        case let .failure(diagnostics):
            return LinkedScope(value: nil, diagnostics: diagnostics)
        }
    }
}

private func linkResourceScope(
    _ scope: ScopeTemplate,
    slotEnv: SlotEnv,
    sourceSpan: SourceSpan?
) -> LinkedScope<ResourceScope> {
    switch scope {
    case .any:
        return LinkedScope(value: .any, diagnostics: .empty)
    case let .eq(reference):
        switch resolve(reference, slotEnv: slotEnv, sourceSpan: sourceSpan) {
        case let .success(uid):
            return LinkedScope(value: .eq(entity: uid), diagnostics: .empty)
        case let .failure(diagnostics):
            return LinkedScope(value: nil, diagnostics: diagnostics)
        }
    case let .in(reference):
        switch resolve(reference, slotEnv: slotEnv, sourceSpan: sourceSpan) {
        case let .success(uid):
            return LinkedScope(value: .in(entity: uid), diagnostics: .empty)
        case let .failure(diagnostics):
            return LinkedScope(value: nil, diagnostics: diagnostics)
        }
    case let .isEntityType(entityType):
        return LinkedScope(value: .isEntityType(entityType: entityType), diagnostics: .empty)
    case let .isEntityTypeIn(entityType, reference):
        switch resolve(reference, slotEnv: slotEnv, sourceSpan: sourceSpan) {
        case let .success(uid):
            return LinkedScope(value: .isEntityTypeIn(entityType: entityType, entity: uid), diagnostics: .empty)
        case let .failure(diagnostics):
            return LinkedScope(value: nil, diagnostics: diagnostics)
        }
    }
}

private func resolve(
    _ reference: EntityUIDOrSlot,
    slotEnv: SlotEnv,
    sourceSpan: SourceSpan?
) -> Result<EntityUID, Diagnostics> {
    switch reference {
    case let .entityUID(uid):
        return .success(uid)
    case let .slot(slot):
        guard let uid = slotEnv.find(slot) else {
            return .failure(Diagnostics([
                Diagnostic(
                    code: "template.missingSlotBinding",
                    category: .template,
                    severity: .error,
                    message: "Missing binding for slot \(slot.id)",
                    sourceSpan: sourceSpan
                )
            ]))
        }

        return .success(uid)
    }
}

private extension CedarMap where Key == String, Value == String {
    func appending(contentsOf other: Self) -> Self {
        Self.make(entries + other.entries)
    }
}
