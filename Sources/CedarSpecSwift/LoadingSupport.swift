import Foundation

internal let defaultJSONDepthLimit = 64

internal struct RequiredField<Value> {
    let value: Value?
    let diagnostics: Diagnostics
}

internal func decodeJSONValue(
    _ text: String,
    source: String?,
    maxDepth: Int = defaultJSONDepthLimit
) -> LoadResult<JSONValue> {
    var parser = JSONParser(source: text, sourceName: source, maxDepth: maxDepth)
    switch parser.parse() {
    case let .success(value):
        return .success(value, diagnostics: .empty)
    case let .failure(diagnostic):
        return .failure(Diagnostics([diagnostic]))
    }
}

internal func decodeJSONValue(
    _ data: Data,
    source: String?,
    maxDepth: Int = defaultJSONDepthLimit
) -> LoadResult<JSONValue> {
    var parser = JSONParser(data: data, sourceName: source, maxDepth: maxDepth)
    switch parser.parse() {
    case let .success(value):
        return .success(value, diagnostics: .empty)
    case let .failure(diagnostic):
        return .failure(Diagnostics([diagnostic]))
    }
}

internal func loadResult<Success>(
    _ result: Result<Success, Diagnostics>,
    diagnostics: Diagnostics = .empty
) -> LoadResult<Success> {
    switch result {
    case let .success(value):
        return .success(value, diagnostics: diagnostics)
    case let .failure(errors):
        return .failure(diagnostics.appending(contentsOf: errors))
    }
}

internal func failureDiagnostics(
    code: String,
    category: DiagnosticCategory,
    message: String,
    sourceSpan: SourceSpan?
) -> Diagnostics {
    Diagnostics([
        Diagnostic(
            code: code,
            category: category,
            severity: .error,
            message: message,
            sourceSpan: sourceSpan
        )
    ])
}

internal func jsonObject(
    _ value: JSONValue,
    category: DiagnosticCategory,
    code: String,
    expectation: String
) -> Result<[JSONObjectEntry], Diagnostics> {
    guard case let .object(entries, _) = value else {
        return .failure(failureDiagnostics(
            code: code,
            category: category,
            message: expectation,
            sourceSpan: value.sourceSpan
        ))
    }

    return .success(entries)
}

internal func jsonArray(
    _ value: JSONValue,
    category: DiagnosticCategory,
    code: String,
    expectation: String
) -> Result<[JSONValue], Diagnostics> {
    guard case let .array(values, _) = value else {
        return .failure(failureDiagnostics(
            code: code,
            category: category,
            message: expectation,
            sourceSpan: value.sourceSpan
        ))
    }

    return .success(values)
}

internal func jsonString(
    _ value: JSONValue,
    category: DiagnosticCategory,
    code: String,
    expectation: String
) -> Result<String, Diagnostics> {
    guard case let .string(stringValue, _) = value else {
        return .failure(failureDiagnostics(
            code: code,
            category: category,
            message: expectation,
            sourceSpan: value.sourceSpan
        ))
    }

    return .success(stringValue)
}

internal func jsonBool(
    _ value: JSONValue,
    category: DiagnosticCategory,
    code: String,
    expectation: String
) -> Result<Bool, Diagnostics> {
    guard case let .bool(boolValue, _) = value else {
        return .failure(failureDiagnostics(
            code: code,
            category: category,
            message: expectation,
            sourceSpan: value.sourceSpan
        ))
    }

    return .success(boolValue)
}

internal func jsonInt64(
    _ value: JSONValue,
    category: DiagnosticCategory,
    code: String,
    expectation: String
) -> Result<Int64, Diagnostics> {
    guard case let .number(rawNumber, _) = value,
          !rawNumber.contains("."),
          !rawNumber.contains("e"),
          !rawNumber.contains("E"),
          let intValue = Int64(rawNumber)
    else {
        return .failure(failureDiagnostics(
            code: code,
            category: category,
            message: expectation,
            sourceSpan: value.sourceSpan
        ))
    }

    return .success(intValue)
}

internal func findJSONField(_ entries: [JSONObjectEntry], _ key: String) -> JSONObjectEntry? {
    entries.last(where: { cedarStringEqual($0.key, key) })
}

internal func sharedStringField(
    _ entries: [JSONObjectEntry],
    key: String,
    owner: SourceSpan,
    category: DiagnosticCategory,
    missingCode: String,
    invalidCode: String
) -> RequiredField<String> {
    let field: JSONObjectEntry
    switch requireJSONField(entries, key, category: category, code: missingCode, ownerSpan: owner) {
    case let .success(entry):
        field = entry
    case let .failure(diagnostics):
        return RequiredField(value: nil, diagnostics: diagnostics)
    }

    switch jsonString(field.value, category: category, code: invalidCode, expectation: "Field '\(key)' must be a string") {
    case let .success(value):
        return RequiredField(value: value, diagnostics: .empty)
    case let .failure(diagnostics):
        return RequiredField(value: nil, diagnostics: diagnostics)
    }
}

internal func requireJSONField(
    _ entries: [JSONObjectEntry],
    _ key: String,
    category: DiagnosticCategory,
    code: String,
    ownerSpan: SourceSpan
) -> Result<JSONObjectEntry, Diagnostics> {
    guard let entry = findJSONField(entries, key) else {
        return .failure(failureDiagnostics(
            code: code,
            category: category,
            message: "Missing required field '\(key)'",
            sourceSpan: ownerSpan
        ))
    }

    return .success(entry)
}

internal func parseName(
    _ raw: String,
    category: DiagnosticCategory,
    code: String,
    sourceSpan: SourceSpan?
) -> Result<Name, Diagnostics> {
    let parts = raw.components(separatedBy: "::")
    guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty }) else {
        return .failure(failureDiagnostics(
            code: code,
            category: category,
            message: "Invalid name '\(raw)'",
            sourceSpan: sourceSpan
        ))
    }

    return .success(Name(id: parts.last ?? raw, path: Array(parts.dropLast())))
}

internal func parseEntityUID(
    _ raw: String,
    category: DiagnosticCategory,
    code: String,
    sourceSpan: SourceSpan?
) -> Result<EntityUID, Diagnostics> {
    guard let components = splitEntityUID(raw) else {
        return .failure(failureDiagnostics(
            code: code,
            category: category,
            message: "Invalid entity UID '\(raw)'",
            sourceSpan: sourceSpan
        ))
    }

    switch parseName(components.typePart, category: category, code: code, sourceSpan: sourceSpan) {
    case let .success(name):
        return .success(EntityUID(ty: name, eid: components.eidPart.replacingOccurrences(of: "\\\"", with: "\"")))
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }
}

private func splitEntityUID(_ raw: String) -> (typePart: String, eidPart: String)? {
    let scalars = Array(raw.unicodeScalars)
    guard !scalars.isEmpty else {
        return nil
    }

    let closingQuoteIndex = scalars.count - 1
    guard scalars[closingQuoteIndex] == "\"" else {
        return nil
    }

    var openingQuoteIndex: Int?
    for index in 2..<closingQuoteIndex {
        if scalars[index] == "\"", scalars[index - 2] == ":", scalars[index - 1] == ":" {
            openingQuoteIndex = index
            break
        }
    }

    guard let openingQuoteIndex else {
        return nil
    }

    guard openingQuoteIndex >= 2 else {
        return nil
    }

    let secondColonIndex = openingQuoteIndex - 1
    let firstColonIndex = openingQuoteIndex - 2
    guard scalars[firstColonIndex] == ":", scalars[secondColonIndex] == ":" else {
        return nil
    }

    let typePart = String(String.UnicodeScalarView(scalars[..<firstColonIndex]))
    guard !typePart.isEmpty else {
        return nil
    }

    let eidStartIndex = openingQuoteIndex + 1
    let eidPart = String(String.UnicodeScalarView(scalars[eidStartIndex..<closingQuoteIndex]))
    return (typePart, eidPart)
}

internal func parsePattern(_ raw: String) -> Pattern {
    var elements: [PatElem] = []
    var iterator = raw.unicodeScalars.makeIterator()
    var escaping = false

    while let scalar = iterator.next() {
        if escaping {
            elements.append(.literal(scalar))
            escaping = false
            continue
        }

        if scalar == "\\" {
            escaping = true
            continue
        }

        if scalar == "*" {
            elements.append(.wildcard)
        } else {
            elements.append(.literal(scalar))
        }
    }

    if escaping {
        elements.append(.literal("\\"))
    }

    return Pattern(elements)
}

internal func parseExtFun(_ rawValue: String) -> ExtFun? {
    switch rawValue {
    case "decimal": return .decimal
    case "lessThan": return .lessThan
    case "lessThanOrEqual": return .lessThanOrEqual
    case "greaterThan": return .greaterThan
    case "greaterThanOrEqual": return .greaterThanOrEqual
    case "ip": return .ip
    case "isIpv4": return .isIpv4
    case "isIpv6": return .isIpv6
    case "isLoopback": return .isLoopback
    case "isMulticast": return .isMulticast
    case "isInRange": return .isInRange
    case "datetime": return .datetime
    case "duration": return .duration
    case "offset": return .offset
    case "durationSince": return .durationSince
    case "toDate": return .toDate
    case "toTime": return .toTime
    case "toMilliseconds": return .toMilliseconds
    case "toSeconds": return .toSeconds
    case "toMinutes": return .toMinutes
    case "toHours": return .toHours
    case "toDays": return .toDays
    default: return nil
    }
}

internal func categoryCode(_ category: DiagnosticCategory) -> String {
    switch category {
    case .policy:
        return "policy"
    case .template:
        return "template"
    case .request:
        return "request"
    case .entity:
        return "entity"
    case .schema:
        return "schema"
    case .validation:
        return "validation"
    case .parse:
        return "parse"
    case .io:
        return "io"
    case .internal:
        return "internal"
    }
}
