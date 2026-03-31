import Foundation

public func loadRequest(_ text: String, schema: Schema? = nil, source: String? = nil) -> LoadResult<Request> {
    switch decodeJSONValue(text, source: source) {
    case let .success(root, diagnostics):
        switch parseRequest(root, schema: schema) {
        case let .success(request):
            return .success(request, diagnostics: diagnostics)
        case let .failure(errors):
            return .failure(errors)
        }
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }
}

public func loadRequest(_ data: Data, schema: Schema? = nil, source: String? = nil) -> LoadResult<Request> {
    switch decodeJSONValue(data, source: source) {
    case let .success(root, diagnostics):
        switch parseRequest(root, schema: schema) {
        case let .success(request):
            return .success(request, diagnostics: diagnostics)
        case let .failure(errors):
            return .failure(errors)
        }
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }
}

internal func parseRequest(_ value: JSONValue, schema: Schema?) -> Result<Request, Diagnostics> {
    let entries: [JSONObjectEntry]
    switch jsonObject(value, category: .request, code: "request.invalidRoot", expectation: "Request input must be a JSON object") {
    case let .success(objectEntries):
        entries = objectEntries
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }

    let principal = requireRequestUID(entries, key: "principal", owner: value.sourceSpan)
    let action = requireRequestUID(entries, key: "action", owner: value.sourceSpan)
    let resource = requireRequestUID(entries, key: "resource", owner: value.sourceSpan)
    let context = parseRequestContext(findJSONField(entries, "context")?.value)

    var diagnostics = principal.diagnostics
        .appending(contentsOf: action.diagnostics)
        .appending(contentsOf: resource.diagnostics)
        .appending(contentsOf: context.diagnostics)

    guard !diagnostics.hasErrors,
          let principalUID = principal.value,
          let actionUID = action.value,
          let resourceUID = resource.value,
          let restrictedContext = context.value
    else {
        return .failure(diagnostics)
    }

    if let schema {
        diagnostics = diagnostics.appending(contentsOf: validateRequestSchema(
            principal: principalUID,
            action: actionUID,
            resource: resourceUID,
            schema: schema,
            sourceSpan: findJSONField(entries, "action")?.value.sourceSpan
        ))
    }

    if diagnostics.hasErrors {
        return .failure(diagnostics)
    }

    return .success(Request(principal: principalUID, action: actionUID, resource: resourceUID, context: restrictedContext))
}

internal func parseRestrictedExprValue(_ value: JSONValue, category: DiagnosticCategory) -> Result<RestrictedExpr, Diagnostics> {
    switch value {
    case let .bool(booleanValue, _):
        return .success(.bool(booleanValue))
    case .null:
        return .failure(failureDiagnostics(
            code: "\(categoryCode(category)).invalidRestrictedValue",
            category: category,
            message: "Restricted values cannot be null",
            sourceSpan: value.sourceSpan
        ))
    case .number:
        switch jsonInt64(value, category: category, code: "\(categoryCode(category)).invalidRestrictedValue", expectation: "Restricted numeric values must be Int64 JSON integers") {
        case let .success(intValue):
            return .success(.int(intValue))
        case let .failure(diagnostics):
            return .failure(diagnostics)
        }
    case let .string(stringValue, _):
        return .success(.string(stringValue))
    case let .array(values, _):
        var elements: [RestrictedExpr] = []
        var diagnostics = Diagnostics.empty
        for element in values {
            switch parseRestrictedExprValue(element, category: category) {
            case let .success(restricted):
                elements.append(restricted)
            case let .failure(errors):
                diagnostics = diagnostics.appending(contentsOf: errors)
            }
        }

        if diagnostics.hasErrors {
            return .failure(diagnostics)
        }

        return .success(.set(CedarSet.make(elements)))
    case let .object(entries, span):
        // Handle Cedar JSON escape hatches: __entity and __extn
        if let entityRef = findJSONField(entries, "__entity") {
            if case let .object(entityEntries, _) = entityRef.value {
                switch parseEntityUIDObjectForValue(entityEntries, sourceSpan: entityRef.value.sourceSpan, category: category) {
                case let .success(uid):
                    return .success(.entityUID(uid))
                case let .failure(diagnostics):
                    return .failure(diagnostics)
                }
            }
            return .failure(failureDiagnostics(
                code: "\(categoryCode(category)).invalidRestrictedValue",
                category: category,
                message: "__entity must be an object with type and id",
                sourceSpan: entityRef.value.sourceSpan
            ))
        }
        if let extnRef = findJSONField(entries, "__extn") {
            if case let .object(extnEntries, _) = extnRef.value {
                let fnField = findJSONField(extnEntries, "fn")
                let argField = findJSONField(extnEntries, "arg")
                if case let .string(fn, _) = fnField?.value,
                   case let .string(arg, _) = argField?.value,
                   let extFun = parseExtFun(fn) {
                    return .success(.call(extFun, [.string(arg)]))
                }
            }
            return .failure(failureDiagnostics(
                code: "\(categoryCode(category)).invalidRestrictedValue",
                category: category,
                message: "__extn must be an object with fn and arg strings",
                sourceSpan: extnRef.value.sourceSpan
            ))
        }
        if let typeEntry = findJSONField(entries, "type") {
            switch jsonString(typeEntry.value, category: category, code: "\(categoryCode(category)).invalidRestrictedValue", expectation: "Restricted type tag must be a string") {
            case let .success(tag):
                switch tag {
                case "entity":
                    let valueField = sharedStringField(entries, key: "value", owner: span, category: category, missingCode: "\(categoryCode(category)).missingRestrictedValue", invalidCode: "\(categoryCode(category)).invalidRestrictedValue")
                    guard let rawUID = valueField.value else {
                        return .failure(valueField.diagnostics)
                    }

                    switch parseEntityUID(rawUID, category: category, code: "\(categoryCode(category)).invalidRestrictedValue", sourceSpan: findJSONField(entries, "value")?.value.sourceSpan) {
                    case let .success(uid):
                        return .success(.entityUID(uid))
                    case let .failure(errors):
                        return .failure(valueField.diagnostics.appending(contentsOf: errors))
                    }
                case "call":
                    let function = sharedStringField(entries, key: "function", owner: span, category: category, missingCode: "\(categoryCode(category)).missingRestrictedFunction", invalidCode: "\(categoryCode(category)).invalidRestrictedFunction")
                    guard let argsField = findJSONField(entries, "args") else {
                        return .failure(function.diagnostics.appending(Diagnostic(
                            code: "\(categoryCode(category)).missingRestrictedArgs",
                            category: category,
                            severity: .error,
                            message: "Restricted extension calls require an args array",
                            sourceSpan: span
                        )))
                    }

                    let args = parseRestrictedExprArray(argsField.value, category: category)
                    let diagnostics = function.diagnostics.appending(contentsOf: args.diagnostics)
                    guard let rawFunction = function.value, let extFun = parseExtFun(rawFunction), let arguments = args.value else {
                        return .failure(diagnostics)
                    }

                    let restricted = RestrictedExpr.call(extFun, arguments)
                    switch restricted.materialize() {
                    case .success:
                        return .success(restricted)
                    case let .failure(error):
                        return .failure(failureDiagnostics(
                            code: "\(categoryCode(category)).invalidRestrictedValue",
                            category: category,
                            message: "Restricted extension constructor failed: \(String(describing: error))",
                            sourceSpan: span
                        ))
                    }
                default:
                    break
                }
            case let .failure(diagnostics):
                return .failure(diagnostics)
            }
        }

        var recordEntries: [(key: Attr, value: RestrictedExpr)] = []
        var diagnostics = Diagnostics.empty
        for entry in entries {
            switch parseRestrictedExprValue(entry.value, category: category) {
            case let .success(restrictedValue):
                recordEntries.append((key: entry.key, value: restrictedValue))
            case let .failure(errors):
                diagnostics = diagnostics.appending(contentsOf: errors)
            }
        }

        if diagnostics.hasErrors {
            return .failure(diagnostics)
        }

        return .success(.record(CedarMap.make(recordEntries)))
    }
}

private struct ParsedRequestValue<Value> {
    let value: Value?
    let diagnostics: Diagnostics
}

private func requireRequestUID(_ entries: [JSONObjectEntry], key: String, owner: SourceSpan) -> ParsedRequestValue<EntityUID> {
    let field = sharedStringField(entries, key: key, owner: owner, category: .request, missingCode: "request.missing\(key.capitalized)", invalidCode: "request.invalid\(key.capitalized)")
    guard let rawUID = field.value else {
        return ParsedRequestValue(value: nil, diagnostics: field.diagnostics)
    }

    switch parseEntityUID(rawUID, category: .request, code: "request.invalid\(key.capitalized)", sourceSpan: findJSONField(entries, key)?.value.sourceSpan) {
    case let .success(uid):
        return ParsedRequestValue(value: uid, diagnostics: field.diagnostics)
    case let .failure(errors):
        return ParsedRequestValue(value: nil, diagnostics: field.diagnostics.appending(contentsOf: errors))
    }
}

private func parseRequestContext(_ value: JSONValue?) -> ParsedRequestValue<RestrictedExpr> {
    guard let value else {
        return ParsedRequestValue(value: .emptyRecord, diagnostics: .empty)
    }

    switch parseRestrictedExprValue(value, category: .request) {
    case let .success(restricted):
        switch restricted.materializeRecord() {
        case .success:
            return ParsedRequestValue(value: restricted, diagnostics: .empty)
        case let .failure(error):
            return ParsedRequestValue(value: nil, diagnostics: failureDiagnostics(
                code: "request.invalidContext",
                category: .request,
                message: "Request context is invalid: \(String(describing: error))",
                sourceSpan: value.sourceSpan
            ))
        }
    case let .failure(diagnostics):
        return ParsedRequestValue(value: nil, diagnostics: Diagnostics([
            Diagnostic(
                code: "request.invalidContext",
                category: .request,
                severity: .error,
                message: diagnostics.elements.first?.message ?? "Request context is invalid",
                sourceSpan: value.sourceSpan
            )
        ]))
    }
}

private func parseRestrictedExprArray(_ value: JSONValue, category: DiagnosticCategory) -> ParsedRequestValue<[RestrictedExpr]> {
    let values: [JSONValue]
    switch jsonArray(value, category: category, code: "\(categoryCode(category)).invalidRestrictedArgs", expectation: "Expected a JSON array") {
    case let .success(arrayValues):
        values = arrayValues
    case let .failure(diagnostics):
        return ParsedRequestValue(value: nil, diagnostics: diagnostics)
    }

    var result: [RestrictedExpr] = []
    var diagnostics = Diagnostics.empty

    for value in values {
        switch parseRestrictedExprValue(value, category: category) {
        case let .success(restricted):
            result.append(restricted)
        case let .failure(errors):
            diagnostics = diagnostics.appending(contentsOf: errors)
        }
    }

    return ParsedRequestValue(value: diagnostics.hasErrors ? nil : result, diagnostics: diagnostics)
}

/// Parse {"type":"T","id":"I"} object to EntityUID (used for __entity escape hatch).
private func parseEntityUIDObjectForValue(
    _ entries: [JSONObjectEntry],
    sourceSpan: SourceSpan,
    category: DiagnosticCategory
) -> Result<EntityUID, Diagnostics> {
    guard let typeField = findJSONField(entries, "type"),
          case let .string(typeName, _) = typeField.value else {
        return .failure(failureDiagnostics(
            code: "\(categoryCode(category)).invalidRestrictedValue",
            category: category,
            message: "__entity object missing 'type' string",
            sourceSpan: sourceSpan
        ))
    }
    guard let idField = findJSONField(entries, "id"),
          case let .string(eid, _) = idField.value else {
        return .failure(failureDiagnostics(
            code: "\(categoryCode(category)).invalidRestrictedValue",
            category: category,
            message: "__entity object missing 'id' string",
            sourceSpan: sourceSpan
        ))
    }
    return .success(EntityUID(ty: Name(id: typeName), eid: eid))
}

private func validateRequestSchema(
    principal: EntityUID,
    action: EntityUID,
    resource: EntityUID,
    schema: Schema,
    sourceSpan: SourceSpan?
) -> Diagnostics {
    guard let actionDefinition = schema.action(action) else {
        return failureDiagnostics(
            code: "request.actionNotDeclared",
            category: .request,
            message: "Action \(action) is not declared in the schema",
            sourceSpan: sourceSpan
        )
    }

    var diagnostics = Diagnostics.empty

    if !actionDefinition.principalTypes.isEmpty && !actionDefinition.principalTypes.contains(principal.ty) {
        diagnostics = diagnostics.appending(Diagnostic(
            code: "request.actionPrincipalMismatch",
            category: .request,
            severity: .error,
            message: "Action \(action) does not allow principal type \(principal.ty)",
            sourceSpan: sourceSpan
        ))
    }

    if !actionDefinition.resourceTypes.isEmpty && !actionDefinition.resourceTypes.contains(resource.ty) {
        diagnostics = diagnostics.appending(Diagnostic(
            code: "request.actionResourceMismatch",
            category: .request,
            severity: .error,
            message: "Action \(action) does not allow resource type \(resource.ty)",
            sourceSpan: sourceSpan
        ))
    }

    return diagnostics
}
