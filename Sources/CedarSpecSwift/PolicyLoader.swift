import Foundation

public func loadPolicies(_ text: String, source: String? = nil) -> LoadResult<Policies> {
    switch decodeJSONValue(text, source: source) {
    case let .success(root, diagnostics):
        switch parsePolicies(root) {
        case let .success(policies):
            return .success(policies, diagnostics: diagnostics)
        case let .failure(errors):
            return .failure(errors)
        }
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }
}

public func loadPolicies(_ data: Data, source: String? = nil) -> LoadResult<Policies> {
    switch decodeJSONValue(data, source: source) {
    case let .success(root, diagnostics):
        switch parsePolicies(root) {
        case let .success(policies):
            return .success(policies, diagnostics: diagnostics)
        case let .failure(errors):
            return .failure(errors)
        }
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }
}

public func loadTemplates(_ text: String, source: String? = nil) -> LoadResult<Templates> {
    switch decodeJSONValue(text, source: source) {
    case let .success(root, diagnostics):
        switch parseTemplates(root) {
        case let .success(templates):
            return .success(templates, diagnostics: diagnostics)
        case let .failure(errors):
            return .failure(errors)
        }
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }
}

public func loadTemplates(_ data: Data, source: String? = nil) -> LoadResult<Templates> {
    switch decodeJSONValue(data, source: source) {
    case let .success(root, diagnostics):
        switch parseTemplates(root) {
        case let .success(templates):
            return .success(templates, diagnostics: diagnostics)
        case let .failure(errors):
            return .failure(errors)
        }
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }
}

public func loadTemplateLinks(_ text: String, source: String? = nil) -> LoadResult<TemplateLinkedPolicies> {
    switch decodeJSONValue(text, source: source) {
    case let .success(root, diagnostics):
        switch parseTemplateLinks(root) {
        case let .success(links):
            return .success(links, diagnostics: diagnostics)
        case let .failure(errors):
            return .failure(errors)
        }
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }
}

public func loadTemplateLinks(_ data: Data, source: String? = nil) -> LoadResult<TemplateLinkedPolicies> {
    switch decodeJSONValue(data, source: source) {
    case let .success(root, diagnostics):
        switch parseTemplateLinks(root) {
        case let .success(links):
            return .success(links, diagnostics: diagnostics)
        case let .failure(errors):
            return .failure(errors)
        }
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }
}

internal func parsePolicies(_ value: JSONValue) -> Result<Policies, Diagnostics> {
    let values: [JSONValue]
    switch jsonArray(value, category: .policy, code: "policy.invalidRoot", expectation: "Policy input must be a JSON array") {
    case let .success(arrayValues):
        values = arrayValues
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }

    var policies: [(key: PolicyID, value: Policy)] = []
    var namespaceEntries: [PolicyNamespaceEntry] = []
    var diagnostics = Diagnostics.empty

    for element in values {
        switch parsePolicy(element) {
        case let .success(policy):
            policies.append((key: policy.id, value: policy))
            namespaceEntries.append(PolicyNamespaceEntry(id: policy.id, kind: .policy, sourceSpan: element.sourceSpan))
        case let .failure(errors):
            diagnostics = diagnostics.appending(contentsOf: errors)
        }
    }

    diagnostics = diagnostics.appending(contentsOf: duplicatePolicyNamespaceDiagnostics(namespaceEntries))

    if diagnostics.hasErrors {
        return .failure(diagnostics)
    }

    return .success(CedarMap.make(policies))
}

internal func parseTemplates(_ value: JSONValue) -> Result<Templates, Diagnostics> {
    let values: [JSONValue]
    switch jsonArray(value, category: .template, code: "template.invalidRoot", expectation: "Template input must be a JSON array") {
    case let .success(arrayValues):
        values = arrayValues
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }

    var templates: [(key: TemplateID, value: Template)] = []
    var namespaceEntries: [PolicyNamespaceEntry] = []
    var diagnostics = Diagnostics.empty

    for element in values {
        switch parseTemplate(element) {
        case let .success(template):
            templates.append((key: template.id, value: template))
            namespaceEntries.append(PolicyNamespaceEntry(id: template.id, kind: .template, sourceSpan: element.sourceSpan))
        case let .failure(errors):
            diagnostics = diagnostics.appending(contentsOf: errors)
        }
    }

    diagnostics = diagnostics.appending(contentsOf: duplicatePolicyNamespaceDiagnostics(namespaceEntries))

    if diagnostics.hasErrors {
        return .failure(diagnostics)
    }

    return .success(CedarMap.make(templates))
}

internal func parseTemplateLinks(_ value: JSONValue) -> Result<TemplateLinkedPolicies, Diagnostics> {
    let values: [JSONValue]
    switch jsonArray(value, category: .template, code: "template.invalidLinksRoot", expectation: "Template link input must be a JSON array") {
    case let .success(arrayValues):
        values = arrayValues
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }

    var links: [TemplateLinkedPolicy] = []
    var namespaceEntries: [PolicyNamespaceEntry] = []
    var diagnostics = Diagnostics.empty

    for element in values {
        switch parseTemplateLinkedPolicy(element) {
        case let .success(linkedPolicy):
            links.append(linkedPolicy)
            namespaceEntries.append(PolicyNamespaceEntry(id: linkedPolicy.id, kind: .templateLink, sourceSpan: element.sourceSpan))
        case let .failure(errors):
            diagnostics = diagnostics.appending(contentsOf: errors)
        }
    }

    diagnostics = diagnostics.appending(contentsOf: duplicatePolicyNamespaceDiagnostics(namespaceEntries))

    if diagnostics.hasErrors {
        return .failure(diagnostics)
    }

    return .success(links)
}

private func parsePolicy(_ value: JSONValue) -> Result<Policy, Diagnostics> {
    let entries: [JSONObjectEntry]
    switch jsonObject(value, category: .policy, code: "policy.invalidPolicy", expectation: "Each policy must be a JSON object") {
    case let .success(objectEntries):
        entries = objectEntries
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }

    let id = requirePolicyID(entries, owner: value.sourceSpan, category: .policy, missingCode: "policy.missingID", invalidCode: "policy.invalidID")
    let annotations = parseAnnotations(findJSONField(entries, "annotations")?.value, category: .policy, code: "policy.invalidAnnotations")
    let effect = parseEffect(entries, owner: value.sourceSpan, category: .policy)
    let principal = parsePrincipalScope(entries, owner: value.sourceSpan, category: .policy)
    let action = parseActionScope(entries, owner: value.sourceSpan, category: .policy)
    let resource = parseResourceScope(entries, owner: value.sourceSpan, category: .policy)
    let conditions = parseConditions(findJSONField(entries, "conditions")?.value, category: .policy)

    let diagnostics = id.diagnostics
        .appending(contentsOf: annotations.diagnostics)
        .appending(contentsOf: effect.diagnostics)
        .appending(contentsOf: principal.diagnostics)
        .appending(contentsOf: action.diagnostics)
        .appending(contentsOf: resource.diagnostics)
        .appending(contentsOf: conditions.diagnostics)

    guard !diagnostics.hasErrors,
          let policyID = id.value,
          let policyEffect = effect.value,
          let principalScope = principal.value,
          let actionScope = action.value,
          let resourceScope = resource.value,
          let policyConditions = conditions.value
    else {
        return .failure(diagnostics)
    }

    return .success(Policy(
        id: policyID,
        annotations: annotations.value ?? .empty,
        effect: policyEffect,
        principalScope: principalScope,
        actionScope: actionScope,
        resourceScope: resourceScope,
        conditions: policyConditions
    ))
}

private func parseTemplate(_ value: JSONValue) -> Result<Template, Diagnostics> {
    let entries: [JSONObjectEntry]
    switch jsonObject(value, category: .template, code: "template.invalidTemplate", expectation: "Each template must be a JSON object") {
    case let .success(objectEntries):
        entries = objectEntries
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }

    let id = requirePolicyID(entries, owner: value.sourceSpan, category: .template, missingCode: "template.missingID", invalidCode: "template.invalidID")
    let annotations = parseAnnotations(findJSONField(entries, "annotations")?.value, category: .template, code: "template.invalidAnnotations")
    let effect = parseEffect(entries, owner: value.sourceSpan, category: .template)
    let principal = parsePrincipalTemplateScope(entries, owner: value.sourceSpan)
    let action = parseActionScope(entries, owner: value.sourceSpan, category: .template)
    let resource = parseResourceTemplateScope(entries, owner: value.sourceSpan)
    let conditions = parseConditions(findJSONField(entries, "conditions")?.value, category: .template)

    let diagnostics = id.diagnostics
        .appending(contentsOf: annotations.diagnostics)
        .appending(contentsOf: effect.diagnostics)
        .appending(contentsOf: principal.diagnostics)
        .appending(contentsOf: action.diagnostics)
        .appending(contentsOf: resource.diagnostics)
        .appending(contentsOf: conditions.diagnostics)

    guard !diagnostics.hasErrors,
          let templateID = id.value,
          let templateEffect = effect.value,
          let principalScope = principal.value,
          let actionScope = action.value,
          let resourceScope = resource.value,
          let templateConditions = conditions.value
    else {
        return .failure(diagnostics)
    }

    return .success(Template(
        id: templateID,
        annotations: annotations.value ?? .empty,
        effect: templateEffect,
        principalScope: principalScope,
        actionScope: actionScope,
        resourceScope: resourceScope,
        conditions: templateConditions
    ))
}

private func parseTemplateLinkedPolicy(_ value: JSONValue) -> Result<TemplateLinkedPolicy, Diagnostics> {
    let entries: [JSONObjectEntry]
    switch jsonObject(value, category: .template, code: "template.invalidLink", expectation: "Each template link must be a JSON object") {
    case let .success(objectEntries):
        entries = objectEntries
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }

    let id = requirePolicyID(entries, owner: value.sourceSpan, category: .template, missingCode: "template.missingLinkedID", invalidCode: "template.invalidLinkedID")
    let templateID = requireStringField(entries, key: "templateId", owner: value.sourceSpan, category: .template, missingCode: "template.missingTemplateID", invalidCode: "template.invalidTemplateID")
    let annotations = parseAnnotations(findJSONField(entries, "annotations")?.value, category: .template, code: "template.invalidLinkAnnotations")
    let slots = parseSlotEnv(findJSONField(entries, "slots")?.value)

    let diagnostics = id.diagnostics
        .appending(contentsOf: templateID.diagnostics)
        .appending(contentsOf: annotations.diagnostics)
        .appending(contentsOf: slots.diagnostics)

    guard !diagnostics.hasErrors,
          let linkedID = id.value,
          let templateIDValue = templateID.value,
          let slotEnv = slots.value
    else {
        return .failure(diagnostics)
    }

    return .success(TemplateLinkedPolicy(
        id: linkedID,
        templateID: templateIDValue,
        slotEnv: slotEnv,
        annotations: annotations.value ?? .empty
    ))
}

private struct Parsed<Value> {
    let value: Value?
    let diagnostics: Diagnostics
}

private func requirePolicyID(
    _ entries: [JSONObjectEntry],
    owner: SourceSpan,
    category: DiagnosticCategory,
    missingCode: String,
    invalidCode: String
) -> Parsed<PolicyID> {
    requireStringField(entries, key: "id", owner: owner, category: category, missingCode: missingCode, invalidCode: invalidCode)
}

private func requireStringField(
    _ entries: [JSONObjectEntry],
    key: String,
    owner: SourceSpan,
    category: DiagnosticCategory,
    missingCode: String,
    invalidCode: String
) -> Parsed<String> {
    let field: JSONObjectEntry
    switch requireJSONField(entries, key, category: category, code: missingCode, ownerSpan: owner) {
    case let .success(entry):
        field = entry
    case let .failure(diagnostics):
        return Parsed(value: nil, diagnostics: diagnostics)
    }

    switch jsonString(field.value, category: category, code: invalidCode, expectation: "Field '\(key)' must be a string") {
    case let .success(value):
        return Parsed(value: value, diagnostics: .empty)
    case let .failure(diagnostics):
        return Parsed(value: nil, diagnostics: diagnostics)
    }
}

private func parseAnnotations(_ value: JSONValue?, category: DiagnosticCategory, code: String) -> Parsed<CedarMap<String, String>> {
    guard let value else {
        return Parsed(value: .empty, diagnostics: .empty)
    }

    let entries: [JSONObjectEntry]
    switch jsonObject(value, category: category, code: code, expectation: "annotations must be a JSON object") {
    case let .success(objectEntries):
        entries = objectEntries
    case let .failure(diagnostics):
        return Parsed(value: nil, diagnostics: diagnostics)
    }

    var result: [(key: String, value: String)] = []
    var diagnostics = Diagnostics.empty

    for entry in entries {
        switch jsonString(entry.value, category: category, code: code, expectation: "annotation values must be strings") {
        case let .success(annotationValue):
            result.append((key: entry.key, value: annotationValue))
        case let .failure(errors):
            diagnostics = diagnostics.appending(contentsOf: errors)
        }
    }

    return Parsed(value: CedarMap.make(result), diagnostics: diagnostics)
}

private func parseEffect(
    _ entries: [JSONObjectEntry],
    owner: SourceSpan,
    category: DiagnosticCategory
) -> Parsed<Effect> {
    let rawEffect = requireStringField(entries, key: "effect", owner: owner, category: category, missingCode: "\(categoryCode(category)).missingEffect", invalidCode: "\(categoryCode(category)).invalidEffect")
    guard let rawValue = rawEffect.value else {
        return Parsed(value: nil, diagnostics: rawEffect.diagnostics)
    }

    switch rawValue {
    case "permit":
        return Parsed(value: .permit, diagnostics: rawEffect.diagnostics)
    case "forbid":
        return Parsed(value: .forbid, diagnostics: rawEffect.diagnostics)
    default:
        return Parsed(value: nil, diagnostics: rawEffect.diagnostics.appending(Diagnostic(
            code: "\(categoryCode(category)).invalidEffect",
            category: category,
            severity: .error,
            message: "Unknown effect '\(rawValue)'",
            sourceSpan: findJSONField(entries, "effect")?.value.sourceSpan
        )))
    }
}

private func parsePrincipalScope(
    _ entries: [JSONObjectEntry],
    owner: SourceSpan,
    category: DiagnosticCategory
) -> Parsed<PrincipalScope> {
    guard let field = findJSONField(entries, "principal") else {
        return Parsed(value: nil, diagnostics: failureDiagnostics(
            code: "\(categoryCode(category)).missingPrincipal",
            category: category,
            message: "Missing required field 'principal'",
            sourceSpan: owner
        ))
    }

    return parseStaticPrincipalScope(field.value, category: category)
}

private func parseResourceScope(
    _ entries: [JSONObjectEntry],
    owner: SourceSpan,
    category: DiagnosticCategory
) -> Parsed<ResourceScope> {
    guard let field = findJSONField(entries, "resource") else {
        return Parsed(value: nil, diagnostics: failureDiagnostics(
            code: "\(categoryCode(category)).missingResource",
            category: category,
            message: "Missing required field 'resource'",
            sourceSpan: owner
        ))
    }

    return parseStaticResourceScope(field.value, category: category)
}

private func parsePrincipalTemplateScope(_ entries: [JSONObjectEntry], owner: SourceSpan) -> Parsed<PrincipalScopeTemplate> {
    guard let field = findJSONField(entries, "principal") else {
        return Parsed(value: nil, diagnostics: failureDiagnostics(
            code: "template.missingPrincipal",
            category: .template,
            message: "Missing required field 'principal'",
            sourceSpan: owner
        ))
    }

    let scope = parseTemplateScope(field.value)
    return Parsed(value: scope.value.map(PrincipalScopeTemplate.init), diagnostics: scope.diagnostics)
}

private func parseResourceTemplateScope(_ entries: [JSONObjectEntry], owner: SourceSpan) -> Parsed<ResourceScopeTemplate> {
    guard let field = findJSONField(entries, "resource") else {
        return Parsed(value: nil, diagnostics: failureDiagnostics(
            code: "template.missingResource",
            category: .template,
            message: "Missing required field 'resource'",
            sourceSpan: owner
        ))
    }

    let scope = parseTemplateScope(field.value)
    return Parsed(value: scope.value.map(ResourceScopeTemplate.init), diagnostics: scope.diagnostics)
}

private func parseStaticPrincipalScope(_ value: JSONValue, category: DiagnosticCategory) -> Parsed<PrincipalScope> {
    let scope = parseStaticScope(value, category: category)
    switch scope.value {
    case .some(.any):
        return Parsed(value: .any, diagnostics: scope.diagnostics)
    case let .some(.eq(uid)):
        return Parsed(value: .eq(entity: uid), diagnostics: scope.diagnostics)
    case let .some(.member(uid)):
        return Parsed(value: .in(entity: uid), diagnostics: scope.diagnostics)
    case let .some(.isEntityType(entityType)):
        return Parsed(value: .isEntityType(entityType: entityType), diagnostics: scope.diagnostics)
    case let .some(.isEntityTypeIn(entityType, uid)):
        return Parsed(value: .isEntityTypeIn(entityType: entityType, entity: uid), diagnostics: scope.diagnostics)
    case .none:
        return Parsed(value: nil, diagnostics: scope.diagnostics)
    }
}

private func parseStaticResourceScope(_ value: JSONValue, category: DiagnosticCategory) -> Parsed<ResourceScope> {
    let scope = parseStaticScope(value, category: category)
    switch scope.value {
    case .some(.any):
        return Parsed(value: .any, diagnostics: scope.diagnostics)
    case let .some(.eq(uid)):
        return Parsed(value: .eq(entity: uid), diagnostics: scope.diagnostics)
    case let .some(.member(uid)):
        return Parsed(value: .in(entity: uid), diagnostics: scope.diagnostics)
    case let .some(.isEntityType(entityType)):
        return Parsed(value: .isEntityType(entityType: entityType), diagnostics: scope.diagnostics)
    case let .some(.isEntityTypeIn(entityType, uid)):
        return Parsed(value: .isEntityTypeIn(entityType: entityType, entity: uid), diagnostics: scope.diagnostics)
    case .none:
        return Parsed(value: nil, diagnostics: scope.diagnostics)
    }
}

private enum ParsedStaticScope {
    case any
    case eq(EntityUID)
    case member(EntityUID)
    case isEntityType(Name)
    case isEntityTypeIn(Name, EntityUID)
}

private func parseStaticScope(_ value: JSONValue, category: DiagnosticCategory) -> Parsed<ParsedStaticScope> {
    let entries: [JSONObjectEntry]
    switch jsonObject(value, category: category, code: "\(categoryCode(category)).invalidScope", expectation: "Scope must be a JSON object") {
    case let .success(objectEntries):
        entries = objectEntries
    case let .failure(diagnostics):
        return Parsed(value: nil, diagnostics: diagnostics)
    }

    let op = requireStringField(entries, key: "op", owner: value.sourceSpan, category: category, missingCode: "\(categoryCode(category)).missingScopeOp", invalidCode: "\(categoryCode(category)).invalidScopeOp")
    guard let operation = op.value else {
        return Parsed(value: nil, diagnostics: op.diagnostics)
    }

    switch operation {
    case "any":
        return Parsed(value: .any, diagnostics: op.diagnostics)
    case "eq":
        let entity = requireEntityField(entries, key: "entity", category: category, code: "\(categoryCode(category)).invalidScopeEntity")
        return Parsed(value: entity.value.map(ParsedStaticScope.eq), diagnostics: op.diagnostics.appending(contentsOf: entity.diagnostics))
    case "in":
        let entity = requireEntityField(entries, key: "entity", category: category, code: "\(categoryCode(category)).invalidScopeEntity")
        return Parsed(value: entity.value.map(ParsedStaticScope.member), diagnostics: op.diagnostics.appending(contentsOf: entity.diagnostics))
    case "is":
        let entityType = requireNameField(entries, key: "entityType", category: category, code: "\(categoryCode(category)).invalidScopeType", owner: value.sourceSpan)
        return Parsed(value: entityType.value.map(ParsedStaticScope.isEntityType), diagnostics: op.diagnostics.appending(contentsOf: entityType.diagnostics))
    case "isIn":
        let entityType = requireNameField(entries, key: "entityType", category: category, code: "\(categoryCode(category)).invalidScopeType", owner: value.sourceSpan)
        let entity = requireEntityField(entries, key: "entity", category: category, code: "\(categoryCode(category)).invalidScopeEntity")
        let diagnostics = op.diagnostics.appending(contentsOf: entityType.diagnostics).appending(contentsOf: entity.diagnostics)
        if let name = entityType.value, let uid = entity.value {
            return Parsed(value: .isEntityTypeIn(name, uid), diagnostics: diagnostics)
        }

        return Parsed(value: nil, diagnostics: diagnostics)
    default:
        return Parsed(value: nil, diagnostics: op.diagnostics.appending(Diagnostic(
            code: "\(categoryCode(category)).invalidScopeOp",
            category: category,
            severity: .error,
            message: "Unknown scope operator '\(operation)'",
            sourceSpan: findJSONField(entries, "op")?.value.sourceSpan
        )))
    }
}

private func parseTemplateScope(_ value: JSONValue) -> Parsed<ScopeTemplate> {
    let entries: [JSONObjectEntry]
    switch jsonObject(value, category: .template, code: "template.invalidScope", expectation: "Scope must be a JSON object") {
    case let .success(objectEntries):
        entries = objectEntries
    case let .failure(diagnostics):
        return Parsed(value: nil, diagnostics: diagnostics)
    }

    let op = requireStringField(entries, key: "op", owner: value.sourceSpan, category: .template, missingCode: "template.missingScopeOp", invalidCode: "template.invalidScopeOp")
    guard let operation = op.value else {
        return Parsed(value: nil, diagnostics: op.diagnostics)
    }

    switch operation {
    case "any":
        return Parsed(value: .any, diagnostics: op.diagnostics)
    case "eq":
        let target = parseEntityOrSlot(entries, key: "entity")
        return Parsed(value: target.value.map(ScopeTemplate.eq), diagnostics: op.diagnostics.appending(contentsOf: target.diagnostics))
    case "in":
        let target = parseEntityOrSlot(entries, key: "entity")
        return Parsed(value: target.value.map(ScopeTemplate.in), diagnostics: op.diagnostics.appending(contentsOf: target.diagnostics))
    case "is":
        let entityType = requireNameField(entries, key: "entityType", category: .template, code: "template.invalidScopeType", owner: value.sourceSpan)
        return Parsed(value: entityType.value.map(ScopeTemplate.isEntityType), diagnostics: op.diagnostics.appending(contentsOf: entityType.diagnostics))
    case "isIn":
        let entityType = requireNameField(entries, key: "entityType", category: .template, code: "template.invalidScopeType", owner: value.sourceSpan)
        let target = parseEntityOrSlot(entries, key: "entity")
        let diagnostics = op.diagnostics.appending(contentsOf: entityType.diagnostics).appending(contentsOf: target.diagnostics)
        if let name = entityType.value, let reference = target.value {
            return Parsed(value: .isEntityTypeIn(name, reference), diagnostics: diagnostics)
        }

        return Parsed(value: nil, diagnostics: diagnostics)
    default:
        return Parsed(value: nil, diagnostics: op.diagnostics.appending(Diagnostic(
            code: "template.invalidScopeOp",
            category: .template,
            severity: .error,
            message: "Unknown scope operator '\(operation)'",
            sourceSpan: findJSONField(entries, "op")?.value.sourceSpan
        )))
    }
}

private func parseActionScope(
    _ entries: [JSONObjectEntry],
    owner: SourceSpan,
    category: DiagnosticCategory
) -> Parsed<ActionScope> {
    guard let field = findJSONField(entries, "action") else {
        return Parsed(value: nil, diagnostics: failureDiagnostics(
            code: "\(categoryCode(category)).missingAction",
            category: category,
            message: "Missing required field 'action'",
            sourceSpan: owner
        ))
    }

    let objectEntries: [JSONObjectEntry]
    switch jsonObject(field.value, category: category, code: "\(categoryCode(category)).invalidActionScope", expectation: "Action scope must be a JSON object") {
    case let .success(parsedEntries):
        objectEntries = parsedEntries
    case let .failure(diagnostics):
        return Parsed(value: nil, diagnostics: diagnostics)
    }

    let op = requireStringField(objectEntries, key: "op", owner: field.value.sourceSpan, category: category, missingCode: "\(categoryCode(category)).missingActionOp", invalidCode: "\(categoryCode(category)).invalidActionOp")
    guard let operation = op.value else {
        return Parsed(value: nil, diagnostics: op.diagnostics)
    }

    switch operation {
    case "any":
        return Parsed(value: .any, diagnostics: op.diagnostics)
    case "eq":
        let entity = requireEntityField(objectEntries, key: "entity", category: category, code: "\(categoryCode(category)).invalidActionEntity")
        return Parsed(value: entity.value.map(ActionScope.eq), diagnostics: op.diagnostics.appending(contentsOf: entity.diagnostics))
    case "in":
        let entity = requireEntityField(objectEntries, key: "entity", category: category, code: "\(categoryCode(category)).invalidActionEntity")
        return Parsed(value: entity.value.map(ActionScope.in), diagnostics: op.diagnostics.appending(contentsOf: entity.diagnostics))
    case "is":
        let entityType = requireNameField(objectEntries, key: "entityType", category: category, code: "\(categoryCode(category)).invalidActionType", owner: field.value.sourceSpan)
        return Parsed(value: entityType.value.map(ActionScope.isEntityType), diagnostics: op.diagnostics.appending(contentsOf: entityType.diagnostics))
    case "isIn":
        let entityType = requireNameField(objectEntries, key: "entityType", category: category, code: "\(categoryCode(category)).invalidActionType", owner: field.value.sourceSpan)
        let entity = requireEntityField(objectEntries, key: "entity", category: category, code: "\(categoryCode(category)).invalidActionEntity")
        let diagnostics = op.diagnostics.appending(contentsOf: entityType.diagnostics).appending(contentsOf: entity.diagnostics)
        if let name = entityType.value, let uid = entity.value {
            return Parsed(value: .isEntityTypeIn(entityType: name, entity: uid), diagnostics: diagnostics)
        }

        return Parsed(value: nil, diagnostics: diagnostics)
    case "inAny":
        let entities = requireEntityArrayField(objectEntries, key: "entities", category: category, code: "\(categoryCode(category)).invalidActionEntities", owner: field.value.sourceSpan)
        return Parsed(value: entities.value.map(ActionScope.actionInAny), diagnostics: op.diagnostics.appending(contentsOf: entities.diagnostics))
    default:
        return Parsed(value: nil, diagnostics: op.diagnostics.appending(Diagnostic(
            code: "\(categoryCode(category)).invalidActionOp",
            category: category,
            severity: .error,
            message: "Unknown action scope operator '\(operation)'",
            sourceSpan: findJSONField(objectEntries, "op")?.value.sourceSpan
        )))
    }
}

private func parseConditions(_ value: JSONValue?, category: DiagnosticCategory) -> Parsed<[Condition]> {
    guard let value else {
        return Parsed(value: [], diagnostics: .empty)
    }

    let values: [JSONValue]
    switch jsonArray(value, category: category, code: "\(categoryCode(category)).invalidConditions", expectation: "conditions must be a JSON array") {
    case let .success(arrayValues):
        values = arrayValues
    case let .failure(diagnostics):
        return Parsed(value: nil, diagnostics: diagnostics)
    }

    var conditions: [Condition] = []
    var diagnostics = Diagnostics.empty

    for conditionValue in values {
        switch parseCondition(conditionValue, category: category) {
        case let .success(condition):
            conditions.append(condition)
        case let .failure(errors):
            diagnostics = diagnostics.appending(contentsOf: errors)
        }
    }

    return Parsed(value: conditions, diagnostics: diagnostics)
}

private func parseCondition(_ value: JSONValue, category: DiagnosticCategory) -> Result<Condition, Diagnostics> {
    let entries: [JSONObjectEntry]
    switch jsonObject(value, category: category, code: "\(categoryCode(category)).invalidCondition", expectation: "condition entries must be JSON objects") {
    case let .success(objectEntries):
        entries = objectEntries
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }

    let kind = requireStringField(entries, key: "kind", owner: value.sourceSpan, category: category, missingCode: "\(categoryCode(category)).missingConditionKind", invalidCode: "\(categoryCode(category)).invalidConditionKind")
    let bodyField = requireJSONField(entries, "body", category: category, code: "\(categoryCode(category)).missingConditionBody", ownerSpan: value.sourceSpan)

    var diagnostics = kind.diagnostics
    let bodyEntry: JSONObjectEntry
    switch bodyField {
    case let .success(entry):
        bodyEntry = entry
    case let .failure(errors):
        diagnostics = diagnostics.appending(contentsOf: errors)
        return .failure(diagnostics)
    }

    let expr = parseExpr(bodyEntry.value, category: category)
    diagnostics = diagnostics.appending(contentsOf: expr.diagnostics)

    guard let rawKind = kind.value, let body = expr.value else {
        return .failure(diagnostics)
    }

    let conditionKind: ConditionKind
    switch rawKind {
    case "when":
        conditionKind = .when
    case "unless":
        conditionKind = .unless
    default:
        return .failure(diagnostics.appending(Diagnostic(
            code: "\(categoryCode(category)).invalidConditionKind",
            category: category,
            severity: .error,
            message: "Unknown condition kind '\(rawKind)'",
            sourceSpan: findJSONField(entries, "kind")?.value.sourceSpan
        )))
    }

    return .success(Condition(kind: conditionKind, body: body))
}

private func parseExpr(_ value: JSONValue, category: DiagnosticCategory) -> Parsed<Expr> {
    let entries: [JSONObjectEntry]
    switch jsonObject(value, category: category, code: "\(categoryCode(category)).invalidExpr", expectation: "expression nodes must be JSON objects") {
    case let .success(objectEntries):
        entries = objectEntries
    case let .failure(diagnostics):
        return Parsed(value: nil, diagnostics: diagnostics)
    }

    let typeField = requireStringField(entries, key: "type", owner: value.sourceSpan, category: category, missingCode: "\(categoryCode(category)).missingExprType", invalidCode: "\(categoryCode(category)).invalidExprType")
    guard let expressionType = typeField.value else {
        return Parsed(value: nil, diagnostics: typeField.diagnostics)
    }

    switch expressionType {
    case "lit":
        guard let valueField = findJSONField(entries, "value") else {
            return Parsed(value: nil, diagnostics: typeField.diagnostics.appending(Diagnostic(
                code: "\(categoryCode(category)).missingLiteralValue",
                category: category,
                severity: .error,
                message: "Literal expression is missing its value",
                sourceSpan: value.sourceSpan
            )))
        }

        let literal = parseLiteral(valueField.value, category: category)
        return Parsed(value: literal.value.map(Expr.lit), diagnostics: typeField.diagnostics.appending(contentsOf: literal.diagnostics))
    case "var":
        let name = requireStringField(entries, key: "name", owner: value.sourceSpan, category: category, missingCode: "\(categoryCode(category)).missingVariableName", invalidCode: "\(categoryCode(category)).invalidVariableName")
        guard let variableName = name.value else {
            return Parsed(value: nil, diagnostics: typeField.diagnostics.appending(contentsOf: name.diagnostics))
        }

        let variable: Var?
        switch variableName {
        case "principal": variable = .principal
        case "action": variable = .action
        case "resource": variable = .resource
        case "context": variable = .context
        default: variable = nil
        }

        guard let variable else {
            return Parsed(value: nil, diagnostics: typeField.diagnostics.appending(contentsOf: name.diagnostics).appending(Diagnostic(
                code: "\(categoryCode(category)).invalidVariableName",
                category: category,
                severity: .error,
                message: "Unknown variable '\(variableName)'",
                sourceSpan: findJSONField(entries, "name")?.value.sourceSpan
            )))
        }

        return Parsed(value: .variable(variable), diagnostics: typeField.diagnostics.appending(contentsOf: name.diagnostics))
    case "unary":
        let op = requireStringField(entries, key: "op", owner: value.sourceSpan, category: category, missingCode: "\(categoryCode(category)).missingUnaryOp", invalidCode: "\(categoryCode(category)).invalidUnaryOp")
        let arg = findJSONField(entries, "arg")
        guard let arg else {
            return Parsed(value: nil, diagnostics: typeField.diagnostics.appending(contentsOf: op.diagnostics).appending(Diagnostic(
                code: "\(categoryCode(category)).missingUnaryArg",
                category: category,
                severity: .error,
                message: "Unary expression is missing its argument",
                sourceSpan: value.sourceSpan
            )))
        }

        let parsedArg = parseExpr(arg.value, category: category)
        let diagnostics = typeField.diagnostics.appending(contentsOf: op.diagnostics).appending(contentsOf: parsedArg.diagnostics)
        guard let rawOp = op.value, let operand = parsedArg.value else {
            return Parsed(value: nil, diagnostics: diagnostics)
        }

        let unary: UnaryOp?
        switch rawOp {
        case "not": unary = .not
        case "neg": unary = .neg
        case "isEmpty": unary = .isEmpty
        default: unary = nil
        }

        guard let unary else {
            return Parsed(value: nil, diagnostics: diagnostics.appending(Diagnostic(
                code: "\(categoryCode(category)).invalidUnaryOp",
                category: category,
                severity: .error,
                message: "Unknown unary operator '\(rawOp)'",
                sourceSpan: findJSONField(entries, "op")?.value.sourceSpan
            )))
        }

        return Parsed(value: .unaryApp(unary, operand), diagnostics: diagnostics)
    case "binary":
        let op = requireStringField(entries, key: "op", owner: value.sourceSpan, category: category, missingCode: "\(categoryCode(category)).missingBinaryOp", invalidCode: "\(categoryCode(category)).invalidBinaryOp")
        guard let leftField = findJSONField(entries, "left"), let rightField = findJSONField(entries, "right") else {
            return Parsed(value: nil, diagnostics: typeField.diagnostics.appending(contentsOf: op.diagnostics).appending(Diagnostic(
                code: "\(categoryCode(category)).missingBinaryOperand",
                category: category,
                severity: .error,
                message: "Binary expression is missing one of its operands",
                sourceSpan: value.sourceSpan
            )))
        }

        let left = parseExpr(leftField.value, category: category)
        let right = parseExpr(rightField.value, category: category)
        let diagnostics = typeField.diagnostics.appending(contentsOf: op.diagnostics).appending(contentsOf: left.diagnostics).appending(contentsOf: right.diagnostics)
        guard let rawOp = op.value, let lhs = left.value, let rhs = right.value else {
            return Parsed(value: nil, diagnostics: diagnostics)
        }

        guard let binary = parseBinaryOp(rawOp) else {
            return Parsed(value: nil, diagnostics: diagnostics.appending(Diagnostic(
                code: "\(categoryCode(category)).invalidBinaryOp",
                category: category,
                severity: .error,
                message: "Unknown binary operator '\(rawOp)'",
                sourceSpan: findJSONField(entries, "op")?.value.sourceSpan
            )))
        }

        return Parsed(value: .binaryApp(binary, lhs, rhs), diagnostics: diagnostics)
    case "if":
        guard let conditionField = findJSONField(entries, "condition"),
              let thenField = findJSONField(entries, "then"),
              let elseField = findJSONField(entries, "else")
        else {
            return Parsed(value: nil, diagnostics: typeField.diagnostics.appending(Diagnostic(
                code: "\(categoryCode(category)).missingIfField",
                category: category,
                severity: .error,
                message: "If expression requires condition, then, and else fields",
                sourceSpan: value.sourceSpan
            )))
        }

        let condition = parseExpr(conditionField.value, category: category)
        let thenExpr = parseExpr(thenField.value, category: category)
        let elseExpr = parseExpr(elseField.value, category: category)
        let diagnostics = typeField.diagnostics.appending(contentsOf: condition.diagnostics).appending(contentsOf: thenExpr.diagnostics).appending(contentsOf: elseExpr.diagnostics)
        if let condition = condition.value, let thenExpr = thenExpr.value, let elseExpr = elseExpr.value {
            return Parsed(value: .ifThenElse(condition, thenExpr, elseExpr), diagnostics: diagnostics)
        }

        return Parsed(value: nil, diagnostics: diagnostics)
    case "set":
        guard let elementsField = findJSONField(entries, "elements") else {
            return Parsed(value: nil, diagnostics: typeField.diagnostics.appending(Diagnostic(
                code: "\(categoryCode(category)).missingSetElements",
                category: category,
                severity: .error,
                message: "Set expression requires an elements array",
                sourceSpan: value.sourceSpan
            )))
        }

        let elements = parseExprArray(elementsField.value, category: category)
        return Parsed(value: elements.value.map(Expr.set), diagnostics: typeField.diagnostics.appending(contentsOf: elements.diagnostics))
    case "record":
        guard let entriesField = findJSONField(entries, "entries") else {
            return Parsed(value: nil, diagnostics: typeField.diagnostics.appending(Diagnostic(
                code: "\(categoryCode(category)).missingRecordEntries",
                category: category,
                severity: .error,
                message: "Record expression requires an entries array",
                sourceSpan: value.sourceSpan
            )))
        }

        let recordEntries = parseExprRecordEntries(entriesField.value, category: category)
        return Parsed(value: recordEntries.value.map(Expr.record), diagnostics: typeField.diagnostics.appending(contentsOf: recordEntries.diagnostics))
    case "hasAttr":
        return parseAttrExpr(entries, owner: value.sourceSpan, category: category, constructor: Expr.hasAttr, codePrefix: categoryCode(category), typeDiagnostics: typeField.diagnostics)
    case "getAttr":
        return parseAttrExpr(entries, owner: value.sourceSpan, category: category, constructor: Expr.getAttr, codePrefix: categoryCode(category), typeDiagnostics: typeField.diagnostics)
    case "like":
        let exprField = findJSONField(entries, "expr")
        let patternField = requireStringField(entries, key: "pattern", owner: value.sourceSpan, category: category, missingCode: "\(categoryCode(category)).missingPattern", invalidCode: "\(categoryCode(category)).invalidPattern")
        guard let exprField else {
            return Parsed(value: nil, diagnostics: typeField.diagnostics.appending(contentsOf: patternField.diagnostics).appending(Diagnostic(
                code: "\(categoryCode(category)).missingPatternExpr",
                category: category,
                severity: .error,
                message: "like expression requires an expr field",
                sourceSpan: value.sourceSpan
            )))
        }

        let expr = parseExpr(exprField.value, category: category)
        let diagnostics = typeField.diagnostics.appending(contentsOf: patternField.diagnostics).appending(contentsOf: expr.diagnostics)
        if let expression = expr.value, let pattern = patternField.value {
            return Parsed(value: .like(expression, parsePattern(pattern)), diagnostics: diagnostics)
        }

        return Parsed(value: nil, diagnostics: diagnostics)
    case "is":
        let exprField = findJSONField(entries, "expr")
        let entityType = requireNameField(entries, key: "entityType", category: category, code: "\(categoryCode(category)).invalidEntityType", owner: value.sourceSpan)
        guard let exprField else {
            return Parsed(value: nil, diagnostics: typeField.diagnostics.appending(contentsOf: entityType.diagnostics).appending(Diagnostic(
                code: "\(categoryCode(category)).missingIsExpr",
                category: category,
                severity: .error,
                message: "is expression requires an expr field",
                sourceSpan: value.sourceSpan
            )))
        }

        let expr = parseExpr(exprField.value, category: category)
        let diagnostics = typeField.diagnostics.appending(contentsOf: entityType.diagnostics).appending(contentsOf: expr.diagnostics)
        if let expression = expr.value, let entityType = entityType.value {
            return Parsed(value: .isEntityType(expression, entityType), diagnostics: diagnostics)
        }

        return Parsed(value: nil, diagnostics: diagnostics)
    case "call":
        let function = requireStringField(entries, key: "function", owner: value.sourceSpan, category: category, missingCode: "\(categoryCode(category)).missingFunction", invalidCode: "\(categoryCode(category)).invalidFunction")
        guard let argsField = findJSONField(entries, "args") else {
            return Parsed(value: nil, diagnostics: typeField.diagnostics.appending(contentsOf: function.diagnostics).appending(Diagnostic(
                code: "\(categoryCode(category)).missingCallArgs",
                category: category,
                severity: .error,
                message: "call expression requires an args array",
                sourceSpan: value.sourceSpan
            )))
        }

        let args = parseExprArray(argsField.value, category: category)
        let diagnostics = typeField.diagnostics.appending(contentsOf: function.diagnostics).appending(contentsOf: args.diagnostics)
        guard let rawFunction = function.value, let parsedFunction = parseExtFun(rawFunction), let arguments = args.value else {
            if function.value != nil, parseExtFun(function.value ?? "") == nil {
                return Parsed(value: nil, diagnostics: diagnostics.appending(Diagnostic(
                    code: "\(categoryCode(category)).invalidFunction",
                    category: category,
                    severity: .error,
                    message: "Unknown extension function '\(function.value ?? "")'",
                    sourceSpan: findJSONField(entries, "function")?.value.sourceSpan
                )))
            }

            return Parsed(value: nil, diagnostics: diagnostics)
        }

        return Parsed(value: .call(parsedFunction, arguments), diagnostics: diagnostics)
    default:
        return Parsed(value: nil, diagnostics: typeField.diagnostics.appending(Diagnostic(
            code: "\(categoryCode(category)).invalidExprType",
            category: category,
            severity: .error,
            message: "Unknown expression type '\(expressionType)'",
            sourceSpan: findJSONField(entries, "type")?.value.sourceSpan
        )))
    }
}

private func parseLiteral(_ value: JSONValue, category: DiagnosticCategory) -> Parsed<CedarValue> {
    let entries: [JSONObjectEntry]
    switch jsonObject(value, category: category, code: "\(categoryCode(category)).invalidLiteral", expectation: "literal values must be JSON objects") {
    case let .success(objectEntries):
        entries = objectEntries
    case let .failure(diagnostics):
        return Parsed(value: nil, diagnostics: diagnostics)
    }

    let typeField = requireStringField(entries, key: "type", owner: value.sourceSpan, category: category, missingCode: "\(categoryCode(category)).missingLiteralType", invalidCode: "\(categoryCode(category)).invalidLiteralType")
    guard let literalType = typeField.value else {
        return Parsed(value: nil, diagnostics: typeField.diagnostics)
    }

    switch literalType {
    case "bool":
        guard let field = findJSONField(entries, "value") else {
            return Parsed(value: nil, diagnostics: typeField.diagnostics)
        }

        switch jsonBool(field.value, category: category, code: "\(categoryCode(category)).invalidLiteralValue", expectation: "bool literals require a boolean value") {
        case let .success(value):
            return Parsed(value: .prim(.bool(value)), diagnostics: typeField.diagnostics)
        case let .failure(diagnostics):
            return Parsed(value: nil, diagnostics: typeField.diagnostics.appending(contentsOf: diagnostics))
        }
    case "int":
        guard let field = findJSONField(entries, "value") else {
            return Parsed(value: nil, diagnostics: typeField.diagnostics)
        }

        switch jsonInt64(field.value, category: category, code: "\(categoryCode(category)).invalidLiteralValue", expectation: "int literals require an integer JSON number") {
        case let .success(value):
            return Parsed(value: .prim(.int(value)), diagnostics: typeField.diagnostics)
        case let .failure(diagnostics):
            return Parsed(value: nil, diagnostics: typeField.diagnostics.appending(contentsOf: diagnostics))
        }
    case "string":
        return parseStringLiteral(entries, category: category, diagnostics: typeField.diagnostics)
    case "entity":
        return parseEntityLiteral(entries, category: category, diagnostics: typeField.diagnostics)
    case "decimal", "ipaddr", "datetime", "duration":
        return parseExtensionLiteral(entries, literalType: literalType, category: category, diagnostics: typeField.diagnostics)
    default:
        return Parsed(value: nil, diagnostics: typeField.diagnostics.appending(Diagnostic(
            code: "\(categoryCode(category)).invalidLiteralType",
            category: category,
            severity: .error,
            message: "Unknown literal type '\(literalType)'",
            sourceSpan: findJSONField(entries, "type")?.value.sourceSpan
        )))
    }
}

private func parseStringLiteral(_ entries: [JSONObjectEntry], category: DiagnosticCategory, diagnostics: Diagnostics) -> Parsed<CedarValue> {
    let value = requireStringField(entries, key: "value", owner: entries.first?.value.sourceSpan ?? SourceSpan(start: .init(line: 1, column: 1, offset: 0), end: .init(line: 1, column: 1, offset: 0)), category: category, missingCode: "\(categoryCode(category)).missingLiteralValue", invalidCode: "\(categoryCode(category)).invalidLiteralValue")
    return Parsed(value: value.value.map { .prim(.string($0)) }, diagnostics: diagnostics.appending(contentsOf: value.diagnostics))
}

private func parseEntityLiteral(_ entries: [JSONObjectEntry], category: DiagnosticCategory, diagnostics: Diagnostics) -> Parsed<CedarValue> {
    let value = requireStringField(entries, key: "value", owner: entries.first?.value.sourceSpan ?? SourceSpan(start: .init(line: 1, column: 1, offset: 0), end: .init(line: 1, column: 1, offset: 0)), category: category, missingCode: "\(categoryCode(category)).missingLiteralValue", invalidCode: "\(categoryCode(category)).invalidLiteralValue")
    guard let rawUID = value.value else {
        return Parsed(value: nil, diagnostics: diagnostics.appending(contentsOf: value.diagnostics))
    }

    switch parseEntityUID(rawUID, category: category, code: "\(categoryCode(category)).invalidLiteralValue", sourceSpan: findJSONField(entries, "value")?.value.sourceSpan) {
    case let .success(uid):
        return Parsed(value: .prim(.entityUID(uid)), diagnostics: diagnostics.appending(contentsOf: value.diagnostics))
    case let .failure(errors):
        return Parsed(value: nil, diagnostics: diagnostics.appending(contentsOf: value.diagnostics).appending(contentsOf: errors))
    }
}

private func parseExtensionLiteral(_ entries: [JSONObjectEntry], literalType: String, category: DiagnosticCategory, diagnostics: Diagnostics) -> Parsed<CedarValue> {
    let value = requireStringField(entries, key: "value", owner: entries.first?.value.sourceSpan ?? SourceSpan(start: .init(line: 1, column: 1, offset: 0), end: .init(line: 1, column: 1, offset: 0)), category: category, missingCode: "\(categoryCode(category)).missingLiteralValue", invalidCode: "\(categoryCode(category)).invalidLiteralValue")
    guard let rawValue = value.value else {
        return Parsed(value: nil, diagnostics: diagnostics.appending(contentsOf: value.diagnostics))
    }

    let ext: Ext
    switch literalType {
    case "decimal": ext = .decimal(.init(rawValue: rawValue))
    case "ipaddr": ext = .ipaddr(.init(rawValue: rawValue))
    case "datetime": ext = .datetime(.init(rawValue: rawValue))
    case "duration": ext = .duration(.init(rawValue: rawValue))
    default: return Parsed(value: nil, diagnostics: diagnostics.appending(contentsOf: value.diagnostics))
    }

    return Parsed(value: .ext(ext), diagnostics: diagnostics.appending(contentsOf: value.diagnostics))
}

private func parseExprArray(_ value: JSONValue, category: DiagnosticCategory) -> Parsed<[Expr]> {
    let values: [JSONValue]
    switch jsonArray(value, category: category, code: "\(categoryCode(category)).invalidExprArray", expectation: "Expected a JSON array of expressions") {
    case let .success(arrayValues):
        values = arrayValues
    case let .failure(diagnostics):
        return Parsed(value: nil, diagnostics: diagnostics)
    }

    var expressions: [Expr] = []
    var diagnostics = Diagnostics.empty

    for element in values {
        let parsed = parseExpr(element, category: category)
        diagnostics = diagnostics.appending(contentsOf: parsed.diagnostics)
        if let expression = parsed.value {
            expressions.append(expression)
        }
    }

    return Parsed(value: diagnostics.hasErrors ? nil : expressions, diagnostics: diagnostics)
}

private func parseExprRecordEntries(_ value: JSONValue, category: DiagnosticCategory) -> Parsed<[(key: Attr, value: Expr)]> {
    let values: [JSONValue]
    switch jsonArray(value, category: category, code: "\(categoryCode(category)).invalidRecordEntries", expectation: "Record entries must be a JSON array") {
    case let .success(arrayValues):
        values = arrayValues
    case let .failure(diagnostics):
        return Parsed(value: nil, diagnostics: diagnostics)
    }

    var entries: [(key: Attr, value: Expr)] = []
    var diagnostics = Diagnostics.empty

    for element in values {
        let objectEntries: [JSONObjectEntry]
        switch jsonObject(element, category: category, code: "\(categoryCode(category)).invalidRecordEntry", expectation: "Record entries must be JSON objects") {
        case let .success(parsedEntries):
            objectEntries = parsedEntries
        case let .failure(errors):
            diagnostics = diagnostics.appending(contentsOf: errors)
            continue
        }

        let key = requireStringField(objectEntries, key: "key", owner: element.sourceSpan, category: category, missingCode: "\(categoryCode(category)).missingRecordKey", invalidCode: "\(categoryCode(category)).invalidRecordKey")
        guard let valueField = findJSONField(objectEntries, "value") else {
            diagnostics = diagnostics.appending(Diagnostic(
                code: "\(categoryCode(category)).missingRecordValue",
                category: category,
                severity: .error,
                message: "Record entry is missing its value",
                sourceSpan: element.sourceSpan
            ))
            continue
        }

        let parsedValue = parseExpr(valueField.value, category: category)
        diagnostics = diagnostics.appending(contentsOf: key.diagnostics).appending(contentsOf: parsedValue.diagnostics)
        if let key = key.value, let parsedValue = parsedValue.value {
            entries.append((key: key, value: parsedValue))
        }
    }

    return Parsed(value: diagnostics.hasErrors ? nil : entries, diagnostics: diagnostics)
}

private func parseAttrExpr(
    _ entries: [JSONObjectEntry],
    owner: SourceSpan,
    category: DiagnosticCategory,
    constructor: (Expr, Attr) -> Expr,
    codePrefix: String,
    typeDiagnostics: Diagnostics
) -> Parsed<Expr> {
    guard let exprField = findJSONField(entries, "expr") else {
        return Parsed(value: nil, diagnostics: typeDiagnostics.appending(Diagnostic(
            code: "\(codePrefix).missingAttrExpr",
            category: category,
            severity: .error,
            message: "Attribute expression requires an expr field",
            sourceSpan: owner
        )))
    }

    let attr = requireStringField(entries, key: "attr", owner: owner, category: category, missingCode: "\(codePrefix).missingAttrName", invalidCode: "\(codePrefix).invalidAttrName")
    let expr = parseExpr(exprField.value, category: category)
    let diagnostics = typeDiagnostics.appending(contentsOf: attr.diagnostics).appending(contentsOf: expr.diagnostics)
    if let attribute = attr.value, let expression = expr.value {
        return Parsed(value: constructor(expression, attribute), diagnostics: diagnostics)
    }

    return Parsed(value: nil, diagnostics: diagnostics)
}

private func requireNameField(
    _ entries: [JSONObjectEntry],
    key: String,
    category: DiagnosticCategory,
    code: String,
    owner: SourceSpan
) -> Parsed<Name> {
    let field = requireStringField(entries, key: key, owner: owner, category: category, missingCode: code, invalidCode: code)
    guard let rawName = field.value else {
        return Parsed(value: nil, diagnostics: field.diagnostics)
    }

    switch parseName(rawName, category: category, code: code, sourceSpan: findJSONField(entries, key)?.value.sourceSpan) {
    case let .success(name):
        return Parsed(value: name, diagnostics: field.diagnostics)
    case let .failure(errors):
        return Parsed(value: nil, diagnostics: field.diagnostics.appending(contentsOf: errors))
    }
}

private func requireEntityField(
    _ entries: [JSONObjectEntry],
    key: String,
    category: DiagnosticCategory,
    code: String
) -> Parsed<EntityUID> {
    let owner = findJSONField(entries, key)?.value.sourceSpan ?? SourceSpan(start: .init(line: 1, column: 1, offset: 0), end: .init(line: 1, column: 1, offset: 0))
    let field = requireStringField(entries, key: key, owner: owner, category: category, missingCode: code, invalidCode: code)
    guard let rawUID = field.value else {
        return Parsed(value: nil, diagnostics: field.diagnostics)
    }

    switch parseEntityUID(rawUID, category: category, code: code, sourceSpan: findJSONField(entries, key)?.value.sourceSpan) {
    case let .success(uid):
        return Parsed(value: uid, diagnostics: field.diagnostics)
    case let .failure(errors):
        return Parsed(value: nil, diagnostics: field.diagnostics.appending(contentsOf: errors))
    }
}

private func requireEntityArrayField(
    _ entries: [JSONObjectEntry],
    key: String,
    category: DiagnosticCategory,
    code: String,
    owner: SourceSpan
) -> Parsed<CedarSet<EntityUID>> {
    guard let field = findJSONField(entries, key) else {
        return Parsed(value: nil, diagnostics: failureDiagnostics(code: code, category: category, message: "Missing required field '\(key)'", sourceSpan: owner))
    }

    let values: [JSONValue]
    switch jsonArray(field.value, category: category, code: code, expectation: "Field '\(key)' must be an array of entity UIDs") {
    case let .success(arrayValues):
        values = arrayValues
    case let .failure(diagnostics):
        return Parsed(value: nil, diagnostics: diagnostics)
    }

    var entities: [EntityUID] = []
    var diagnostics = Diagnostics.empty

    for value in values {
        switch jsonString(value, category: category, code: code, expectation: "Entity UID entries must be strings") {
        case let .success(rawUID):
            switch parseEntityUID(rawUID, category: category, code: code, sourceSpan: value.sourceSpan) {
            case let .success(uid):
                entities.append(uid)
            case let .failure(errors):
                diagnostics = diagnostics.appending(contentsOf: errors)
            }
        case let .failure(errors):
            diagnostics = diagnostics.appending(contentsOf: errors)
        }
    }

    return Parsed(value: diagnostics.hasErrors ? nil : CedarSet.make(entities), diagnostics: diagnostics)
}

private func parseEntityOrSlot(_ entries: [JSONObjectEntry], key: String) -> Parsed<EntityUIDOrSlot> {
    guard let field = findJSONField(entries, key) else {
        return Parsed(value: nil, diagnostics: failureDiagnostics(code: "template.missingScopeEntity", category: .template, message: "Missing required field '\(key)'", sourceSpan: nil))
    }

    switch field.value {
    case let .string(rawUID, span):
        switch parseEntityUID(rawUID, category: .template, code: "template.invalidScopeEntity", sourceSpan: span) {
        case let .success(uid):
            return Parsed(value: .entityUID(uid), diagnostics: .empty)
        case let .failure(diagnostics):
            return Parsed(value: nil, diagnostics: diagnostics)
        }
    case let .object(slotEntries, _):
        let slot = requireStringField(slotEntries, key: "slot", owner: field.value.sourceSpan, category: .template, missingCode: "template.missingSlot", invalidCode: "template.invalidSlot")
        if let slotID = slot.value {
            return Parsed(value: .slot(Slot(slotID)), diagnostics: slot.diagnostics)
        }

        return Parsed(value: nil, diagnostics: slot.diagnostics)
    default:
        return Parsed(value: nil, diagnostics: failureDiagnostics(code: "template.invalidScopeEntity", category: .template, message: "Template scope entity must be an entity UID string or slot object", sourceSpan: field.value.sourceSpan))
    }
}

private func parseSlotEnv(_ value: JSONValue?) -> Parsed<SlotEnv> {
    guard let value else {
        return Parsed(value: .empty, diagnostics: .empty)
    }

    let values: [JSONValue]
    switch jsonArray(value, category: .template, code: "template.invalidSlots", expectation: "slots must be a JSON array") {
    case let .success(arrayValues):
        values = arrayValues
    case let .failure(diagnostics):
        return Parsed(value: nil, diagnostics: diagnostics)
    }

    var entries: [(key: Slot, value: EntityUID)] = []
    var diagnostics = Diagnostics.empty

    for value in values {
        let objectEntries: [JSONObjectEntry]
        switch jsonObject(value, category: .template, code: "template.invalidSlotBinding", expectation: "slot bindings must be JSON objects") {
        case let .success(parsedEntries):
            objectEntries = parsedEntries
        case let .failure(errors):
            diagnostics = diagnostics.appending(contentsOf: errors)
            continue
        }

        let slotID = requireStringField(objectEntries, key: "slot", owner: value.sourceSpan, category: .template, missingCode: "template.missingSlot", invalidCode: "template.invalidSlot")
        let entity = requireEntityField(objectEntries, key: "entity", category: .template, code: "template.invalidSlotEntity")
        diagnostics = diagnostics.appending(contentsOf: slotID.diagnostics).appending(contentsOf: entity.diagnostics)
        if let slotID = slotID.value, let entity = entity.value {
            entries.append((key: Slot(slotID), value: entity))
        }
    }

    return Parsed(value: diagnostics.hasErrors ? nil : CedarMap.make(entries), diagnostics: diagnostics)
}

private func parseBinaryOp(_ rawValue: String) -> BinaryOp? {
    switch rawValue {
    case "and": return .and
    case "or": return .or
    case "equal": return .equal
    case "lessThan": return .lessThan
    case "lessThanOrEqual": return .lessThanOrEqual
    case "add": return .add
    case "sub": return .sub
    case "mul": return .mul
    case "in": return .in
    case "contains": return .contains
    case "containsAll": return .containsAll
    case "containsAny": return .containsAny
    case "hasTag": return .hasTag
    case "getTag": return .getTag
    default: return nil
    }
}
