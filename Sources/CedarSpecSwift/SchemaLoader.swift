import Foundation

/// Loads a Cedar schema from the official Cedar JSON schema format.
///
/// The JSON format uses namespace-keyed top-level objects, each containing
/// `entityTypes` and `actions`. Entity types use `EntityOrCommon` with a `name`
/// field for type references (e.g. `__cedar::Bool`, `__cedar::Long`, entity type names),
/// `Record` with `attributes` for record types, `Set` with `element` for set types,
/// and `enum` arrays for enum entity types.
public func loadSchemaJSON(_ text: String, source: String? = nil) -> LoadResult<Schema> {
    switch decodeJSONValue(text, source: source) {
    case let .success(root, diagnostics):
        switch parseJSONSchema(root) {
        case let .success(schema):
            return .success(schema, diagnostics: diagnostics)
        case let .failure(errors):
            return .failure(errors)
        }
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }
}

public func loadSchemaJSON(_ data: Data, source: String? = nil) -> LoadResult<Schema> {
    switch decodeJSONValue(data, source: source) {
    case let .success(root, diagnostics):
        switch parseJSONSchema(root) {
        case let .success(schema):
            return .success(schema, diagnostics: diagnostics)
        case let .failure(errors):
            return .failure(errors)
        }
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }
}

// MARK: - Internal JSON Schema Parsing

private func parseJSONSchema(_ value: JSONValue) -> Result<Schema, Diagnostics> {
    let namespaces: [JSONObjectEntry]
    switch jsonObject(value, category: .schema, code: "schema.invalidRoot", expectation: "Schema JSON must be a top-level object keyed by namespace") {
    case let .success(entries):
        namespaces = entries
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }

    var allEntityEntries: [(key: Name, value: Schema.EntityTypeDefinition)] = []
    var allActionEntries: [(key: EntityUID, value: Schema.ActionDefinition)] = []
    var diagnostics = Diagnostics.empty

    for nsEntry in namespaces {
        let namespacePath: [String]
        if nsEntry.key.isEmpty {
            namespacePath = []
        } else {
            namespacePath = nsEntry.key.components(separatedBy: "::")
        }

        let nsEntries: [JSONObjectEntry]
        switch jsonObject(nsEntry.value, category: .schema, code: "schema.invalidNamespace", expectation: "Each namespace must be a JSON object") {
        case let .success(entries):
            nsEntries = entries
        case let .failure(errors):
            diagnostics = diagnostics.appending(contentsOf: errors)
            continue
        }

        // Parse entity types
        if let entityTypesField = findJSONField(nsEntries, "entityTypes") {
            let result = parseJSONSchemaEntityTypes(entityTypesField.value, namespace: namespacePath)
            diagnostics = diagnostics.appending(contentsOf: result.diagnostics)
            if let entries = result.value {
                allEntityEntries.append(contentsOf: entries)
            }
        }

        // Parse actions
        if let actionsField = findJSONField(nsEntries, "actions") {
            let result = parseJSONSchemaActions(actionsField.value, namespace: namespacePath)
            diagnostics = diagnostics.appending(contentsOf: result.diagnostics)
            if let entries = result.value {
                allActionEntries.append(contentsOf: entries)
            }
        }
    }

    guard !diagnostics.hasErrors else {
        return .failure(diagnostics)
    }

    return .success(Schema(
        entityTypes: CedarMap.make(allEntityEntries),
        actions: CedarMap.make(allActionEntries)
    ))
}

private struct JSONSchemaPartialLoad<Value> {
    let value: Value?
    let diagnostics: Diagnostics
}

private func parseJSONSchemaEntityTypes(
    _ value: JSONValue,
    namespace: [String]
) -> JSONSchemaPartialLoad<[(key: Name, value: Schema.EntityTypeDefinition)]> {
    let entries: [JSONObjectEntry]
    switch jsonObject(value, category: .schema, code: "schema.invalidEntityTypes", expectation: "entityTypes must be a JSON object") {
    case let .success(objectEntries):
        entries = objectEntries
    case let .failure(diagnostics):
        return JSONSchemaPartialLoad(value: nil, diagnostics: diagnostics)
    }

    var definitions: [(key: Name, value: Schema.EntityTypeDefinition)] = []
    var diagnostics = Diagnostics.empty

    for entry in entries {
        let name = Name(id: entry.key, path: namespace)

        let objectEntries: [JSONObjectEntry]
        switch jsonObject(entry.value, category: .schema, code: "schema.invalidEntityType", expectation: "Each entity type definition must be a JSON object") {
        case let .success(parsedEntries):
            objectEntries = parsedEntries
        case let .failure(errors):
            diagnostics = diagnostics.appending(contentsOf: errors)
            continue
        }

        // Parse memberOfTypes
        var memberOfTypes: [Name] = []
        if let memberOfField = findJSONField(objectEntries, "memberOfTypes") {
            switch jsonArray(memberOfField.value, category: .schema, code: "schema.invalidMemberOfTypes", expectation: "memberOfTypes must be an array") {
            case let .success(values):
                for val in values {
                    switch jsonString(val, category: .schema, code: "schema.invalidMemberOfType", expectation: "memberOfTypes entries must be strings") {
                    case let .success(rawType):
                        memberOfTypes.append(resolveJSONSchemaName(rawType, namespace: namespace))
                    case let .failure(errors):
                        diagnostics = diagnostics.appending(contentsOf: errors)
                    }
                }
            case let .failure(errors):
                diagnostics = diagnostics.appending(contentsOf: errors)
            }
        }

        // Parse enum entity IDs
        var enumEntityIDs: CedarSet<String>?
        if let enumField = findJSONField(objectEntries, "enum") {
            switch jsonArray(enumField.value, category: .schema, code: "schema.invalidEnum", expectation: "enum must be an array of strings") {
            case let .success(values):
                var ids: [String] = []
                for val in values {
                    switch jsonString(val, category: .schema, code: "schema.invalidEnumValue", expectation: "enum values must be strings") {
                    case let .success(id):
                        ids.append(id)
                    case let .failure(errors):
                        diagnostics = diagnostics.appending(contentsOf: errors)
                    }
                }
                enumEntityIDs = CedarSet.make(ids)
            case let .failure(errors):
                diagnostics = diagnostics.appending(contentsOf: errors)
            }
        }

        // Parse shape (attributes)
        var attributes: CedarMap<Attr, Schema.QualifiedType> = .empty
        if let shapeField = findJSONField(objectEntries, "shape") {
            let result = parseJSONSchemaRecordType(shapeField.value, namespace: namespace)
            diagnostics = diagnostics.appending(contentsOf: result.diagnostics)
            if let attrs = result.value {
                attributes = attrs
            }
        }

        // Parse tags
        var tags: Schema.CedarType?
        if let tagsField = findJSONField(objectEntries, "tags") {
            let result = parseJSONSchemaType(tagsField.value, namespace: namespace)
            diagnostics = diagnostics.appending(contentsOf: result.diagnostics)
            tags = result.value
        }

        definitions.append((
            key: name,
            value: Schema.EntityTypeDefinition(
                name: name,
                memberOfTypes: CedarSet.make(memberOfTypes),
                attributes: attributes,
                tags: tags,
                enumEntityIDs: enumEntityIDs
            )
        ))
    }

    return JSONSchemaPartialLoad(value: definitions, diagnostics: diagnostics)
}

private func parseJSONSchemaActions(
    _ value: JSONValue,
    namespace: [String]
) -> JSONSchemaPartialLoad<[(key: EntityUID, value: Schema.ActionDefinition)]> {
    let entries: [JSONObjectEntry]
    switch jsonObject(value, category: .schema, code: "schema.invalidActions", expectation: "actions must be a JSON object") {
    case let .success(objectEntries):
        entries = objectEntries
    case let .failure(diagnostics):
        return JSONSchemaPartialLoad(value: nil, diagnostics: diagnostics)
    }

    var definitions: [(key: EntityUID, value: Schema.ActionDefinition)] = []
    var diagnostics = Diagnostics.empty

    for entry in entries {
        let uid = EntityUID(ty: Name(id: "Action", path: namespace), eid: entry.key)

        let objectEntries: [JSONObjectEntry]
        switch jsonObject(entry.value, category: .schema, code: "schema.invalidAction", expectation: "Each action definition must be a JSON object") {
        case let .success(parsedEntries):
            objectEntries = parsedEntries
        case let .failure(errors):
            diagnostics = diagnostics.appending(contentsOf: errors)
            continue
        }

        var principalTypes: [Name] = []
        var resourceTypes: [Name] = []
        var context: CedarMap<Attr, Schema.QualifiedType> = .empty
        var memberOf: [EntityUID] = []

        // Parse appliesTo
        if let appliesToField = findJSONField(objectEntries, "appliesTo") {
            switch jsonObject(appliesToField.value, category: .schema, code: "schema.invalidAppliesTo", expectation: "appliesTo must be a JSON object") {
            case let .success(appliesToEntries):
                // principalTypes
                if let ptField = findJSONField(appliesToEntries, "principalTypes") {
                    switch jsonArray(ptField.value, category: .schema, code: "schema.invalidPrincipalTypes", expectation: "principalTypes must be an array") {
                    case let .success(values):
                        for val in values {
                            switch jsonString(val, category: .schema, code: "schema.invalidPrincipalType", expectation: "principalTypes entries must be strings") {
                            case let .success(rawType):
                                principalTypes.append(resolveJSONSchemaName(rawType, namespace: namespace))
                            case let .failure(errors):
                                diagnostics = diagnostics.appending(contentsOf: errors)
                            }
                        }
                    case let .failure(errors):
                        diagnostics = diagnostics.appending(contentsOf: errors)
                    }
                }

                // resourceTypes
                if let rtField = findJSONField(appliesToEntries, "resourceTypes") {
                    switch jsonArray(rtField.value, category: .schema, code: "schema.invalidResourceTypes", expectation: "resourceTypes must be an array") {
                    case let .success(values):
                        for val in values {
                            switch jsonString(val, category: .schema, code: "schema.invalidResourceType", expectation: "resourceTypes entries must be strings") {
                            case let .success(rawType):
                                resourceTypes.append(resolveJSONSchemaName(rawType, namespace: namespace))
                            case let .failure(errors):
                                diagnostics = diagnostics.appending(contentsOf: errors)
                            }
                        }
                    case let .failure(errors):
                        diagnostics = diagnostics.appending(contentsOf: errors)
                    }
                }

                // context
                if let contextField = findJSONField(appliesToEntries, "context") {
                    let result = parseJSONSchemaRecordType(contextField.value, namespace: namespace)
                    diagnostics = diagnostics.appending(contentsOf: result.diagnostics)
                    if let ctx = result.value {
                        context = ctx
                    }
                }
            case let .failure(errors):
                diagnostics = diagnostics.appending(contentsOf: errors)
            }
        }

        // Parse memberOf
        if let memberOfField = findJSONField(objectEntries, "memberOf") {
            switch jsonArray(memberOfField.value, category: .schema, code: "schema.invalidActionParents", expectation: "memberOf must be an array") {
            case let .success(values):
                for val in values {
                    switch jsonObject(val, category: .schema, code: "schema.invalidActionParent", expectation: "memberOf entries must be objects") {
                    case let .success(parentEntries):
                        if let idField = findJSONField(parentEntries, "id") {
                            switch jsonString(idField.value, category: .schema, code: "schema.invalidActionParentId", expectation: "action parent id must be a string") {
                            case let .success(eid):
                                let parentType: Name
                                if let typeField = findJSONField(parentEntries, "type") {
                                    switch jsonString(typeField.value, category: .schema, code: "schema.invalidActionParentType", expectation: "action parent type must be a string") {
                                    case let .success(rawType):
                                        parentType = resolveJSONSchemaName(rawType, namespace: namespace)
                                    case let .failure(errors):
                                        diagnostics = diagnostics.appending(contentsOf: errors)
                                        continue
                                    }
                                } else {
                                    parentType = Name(id: "Action", path: namespace)
                                }
                                memberOf.append(EntityUID(ty: parentType, eid: eid))
                            case let .failure(errors):
                                diagnostics = diagnostics.appending(contentsOf: errors)
                            }
                        }
                    case let .failure(errors):
                        diagnostics = diagnostics.appending(contentsOf: errors)
                    }
                }
            case let .failure(errors):
                diagnostics = diagnostics.appending(contentsOf: errors)
            }
        }

        definitions.append((
            key: uid,
            value: Schema.ActionDefinition(
                uid: uid,
                principalTypes: CedarSet.make(principalTypes),
                resourceTypes: CedarSet.make(resourceTypes),
                memberOf: CedarSet.make(memberOf),
                context: context
            )
        ))
    }

    return JSONSchemaPartialLoad(value: definitions, diagnostics: diagnostics)
}

/// Parse a type from the JSON schema format.
/// Types can be:
/// - `{"type": "EntityOrCommon", "name": "..."}` for entity refs and builtins
/// - `{"type": "Record", "attributes": {...}}` for records
/// - `{"type": "Set", "element": {...}}` for sets
private func parseJSONSchemaType(
    _ value: JSONValue,
    namespace: [String]
) -> JSONSchemaPartialLoad<Schema.CedarType> {
    let entries: [JSONObjectEntry]
    switch jsonObject(value, category: .schema, code: "schema.invalidType", expectation: "Type definition must be a JSON object") {
    case let .success(objectEntries):
        entries = objectEntries
    case let .failure(diagnostics):
        return JSONSchemaPartialLoad(value: nil, diagnostics: diagnostics)
    }

    guard let typeField = findJSONField(entries, "type") else {
        return JSONSchemaPartialLoad(value: nil, diagnostics: failureDiagnostics(
            code: "schema.missingType",
            category: .schema,
            message: "Type definition must have a 'type' field",
            sourceSpan: value.sourceSpan
        ))
    }

    let rawType: String
    switch jsonString(typeField.value, category: .schema, code: "schema.invalidType", expectation: "type must be a string") {
    case let .success(typeName):
        rawType = typeName
    case let .failure(diagnostics):
        return JSONSchemaPartialLoad(value: nil, diagnostics: diagnostics)
    }

    switch rawType {
    case "EntityOrCommon":
        guard let nameField = findJSONField(entries, "name") else {
            return JSONSchemaPartialLoad(value: nil, diagnostics: failureDiagnostics(
                code: "schema.missingName",
                category: .schema,
                message: "EntityOrCommon type must have a 'name' field",
                sourceSpan: value.sourceSpan
            ))
        }

        let rawName: String
        switch jsonString(nameField.value, category: .schema, code: "schema.invalidName", expectation: "name must be a string") {
        case let .success(name):
            rawName = name
        case let .failure(diagnostics):
            return JSONSchemaPartialLoad(value: nil, diagnostics: diagnostics)
        }

        // Resolve __cedar:: builtins
        if rawName.hasPrefix("__cedar::") {
            let builtinName = String(rawName.dropFirst("__cedar::".count))
            switch builtinName {
            case "Bool":
                return JSONSchemaPartialLoad(value: .bool, diagnostics: .empty)
            case "Long":
                return JSONSchemaPartialLoad(value: .int, diagnostics: .empty)
            case "String":
                return JSONSchemaPartialLoad(value: .string, diagnostics: .empty)
            case "decimal":
                return JSONSchemaPartialLoad(value: .ext(.decimal), diagnostics: .empty)
            case "ipaddr":
                return JSONSchemaPartialLoad(value: .ext(.ipaddr), diagnostics: .empty)
            case "datetime":
                return JSONSchemaPartialLoad(value: .ext(.datetime), diagnostics: .empty)
            case "duration":
                return JSONSchemaPartialLoad(value: .ext(.duration), diagnostics: .empty)
            default:
                return JSONSchemaPartialLoad(value: nil, diagnostics: failureDiagnostics(
                    code: "schema.unknownBuiltin",
                    category: .schema,
                    message: "Unknown __cedar:: builtin type '\(builtinName)'",
                    sourceSpan: nameField.value.sourceSpan
                ))
            }
        }

        // Entity type reference
        let entityName = resolveJSONSchemaName(rawName, namespace: namespace)
        return JSONSchemaPartialLoad(value: .entity(entityName), diagnostics: .empty)

    case "Record":
        let result = parseJSONSchemaRecordAttributes(entries, namespace: namespace)
        return JSONSchemaPartialLoad(
            value: result.value.map { .record($0) },
            diagnostics: result.diagnostics
        )

    case "Set":
        guard let elementField = findJSONField(entries, "element") else {
            return JSONSchemaPartialLoad(value: nil, diagnostics: failureDiagnostics(
                code: "schema.missingElement",
                category: .schema,
                message: "Set type must have an 'element' field",
                sourceSpan: value.sourceSpan
            ))
        }

        let elementResult = parseJSONSchemaType(elementField.value, namespace: namespace)
        return JSONSchemaPartialLoad(
            value: elementResult.value.map { .set($0) },
            diagnostics: elementResult.diagnostics
        )

    default:
        // Some type names in the corpus are actually action entity type names used as the
        // "type" field value (e.g. "r::P::A0zz03300::r::Action"). Treat them as entity types.
        let entityName = resolveJSONSchemaName(rawType, namespace: namespace)
        return JSONSchemaPartialLoad(value: .entity(entityName), diagnostics: .empty)
    }
}

/// Parse a Record type, extracting `attributes` from the object entries.
private func parseJSONSchemaRecordAttributes(
    _ entries: [JSONObjectEntry],
    namespace: [String]
) -> JSONSchemaPartialLoad<CedarMap<Attr, Schema.QualifiedType>> {
    guard let attrsField = findJSONField(entries, "attributes") else {
        return JSONSchemaPartialLoad(value: .empty, diagnostics: .empty)
    }

    let attrEntries: [JSONObjectEntry]
    switch jsonObject(attrsField.value, category: .schema, code: "schema.invalidAttributes", expectation: "attributes must be a JSON object") {
    case let .success(objectEntries):
        attrEntries = objectEntries
    case let .failure(diagnostics):
        return JSONSchemaPartialLoad(value: nil, diagnostics: diagnostics)
    }

    var parsedAttrs: [(key: Attr, value: Schema.QualifiedType)] = []
    var diagnostics = Diagnostics.empty

    for attrEntry in attrEntries {
        let typeResult = parseJSONSchemaType(attrEntry.value, namespace: namespace)
        diagnostics = diagnostics.appending(contentsOf: typeResult.diagnostics)

        if let cedarType = typeResult.value {
            // Check for required field (default true)
            let required: Bool
            if case let .object(attrObjEntries, _) = attrEntry.value,
               let requiredField = findJSONField(attrObjEntries, "required") {
                switch jsonBool(requiredField.value, category: .schema, code: "schema.invalidRequired", expectation: "required must be a boolean") {
                case let .success(req):
                    required = req
                case let .failure(errors):
                    diagnostics = diagnostics.appending(contentsOf: errors)
                    continue
                }
            } else {
                required = true
            }

            parsedAttrs.append((key: attrEntry.key, value: Schema.QualifiedType(cedarType, required: required)))
        }
    }

    return JSONSchemaPartialLoad(value: CedarMap.make(parsedAttrs), diagnostics: diagnostics)
}

/// Parse a Record type value (the `shape` field in entity type definitions, or `context` in actions).
private func parseJSONSchemaRecordType(
    _ value: JSONValue,
    namespace: [String]
) -> JSONSchemaPartialLoad<CedarMap<Attr, Schema.QualifiedType>> {
    let entries: [JSONObjectEntry]
    switch jsonObject(value, category: .schema, code: "schema.invalidRecordType", expectation: "Record type must be a JSON object") {
    case let .success(objectEntries):
        entries = objectEntries
    case let .failure(diagnostics):
        return JSONSchemaPartialLoad(value: nil, diagnostics: diagnostics)
    }

    return parseJSONSchemaRecordAttributes(entries, namespace: namespace)
}

/// Resolve a type name from the JSON schema format.
/// Names without `::` are qualified with the current namespace.
/// Names with `::` are used as-is.
private func resolveJSONSchemaName(_ rawName: String, namespace: [String]) -> Name {
    let parts = rawName.components(separatedBy: "::")
    if parts.count > 1 {
        return Name(id: parts.last ?? rawName, path: Array(parts.dropLast()))
    }
    return Name(id: rawName, path: namespace)
}
