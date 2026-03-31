import Foundation

public func loadEntities(_ text: String, schema: Schema? = nil, source: String? = nil) -> LoadResult<Entities> {
    switch decodeJSONValue(text, source: source) {
    case let .success(root, diagnostics):
        switch parseEntities(root, schema: schema) {
        case let .success(entities):
            return .success(entities, diagnostics: diagnostics)
        case let .failure(errors):
            return .failure(errors)
        }
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }
}

public func loadEntities(_ data: Data, schema: Schema? = nil, source: String? = nil) -> LoadResult<Entities> {
    switch decodeJSONValue(data, source: source) {
    case let .success(root, diagnostics):
        switch parseEntities(root, schema: schema) {
        case let .success(entities):
            return .success(entities, diagnostics: diagnostics)
        case let .failure(errors):
            return .failure(errors)
        }
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }
}

internal func parseEntities(_ value: JSONValue, schema: Schema?) -> Result<Entities, Diagnostics> {
    let values: [JSONValue]
    switch jsonArray(value, category: .entity, code: "entity.invalidRoot", expectation: "Entity input must be a JSON array") {
    case let .success(arrayValues):
        values = arrayValues
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }

    var loaded: [LoadedEntity] = []
    var diagnostics = Diagnostics.empty

    for value in values {
        switch parseLoadedEntity(value) {
        case let .success(entity):
            loaded.append(entity)
        case let .failure(errors):
            diagnostics = diagnostics.appending(contentsOf: errors)
        }
    }

    let duplicateDiagnostics = duplicateEntityDiagnostics(loaded)
    diagnostics = diagnostics.appending(contentsOf: duplicateDiagnostics)
    diagnostics = diagnostics.appending(contentsOf: hierarchyDiagnostics(loaded, schema: schema))

    if diagnostics.hasErrors {
        return .failure(diagnostics)
    }

    // Build the entity map, creating implicit empty entities for any referenced-but-undeclared parents
    var entityEntries = loaded.map { (key: $0.uid, value: EntityData(ancestors: CedarSet.make($0.parents), attrs: $0.attrs, tags: $0.tags)) }
    let declaredUIDs = Set(loaded.map { $0.uid })
    for entity in loaded {
        for parent in entity.parents where !declaredUIDs.contains(parent) {
            entityEntries.append((key: parent, value: EntityData()))
        }
    }
    let entities = Entities(CedarMap.make(entityEntries))
    return .success(entities)
}

private struct LoadedEntity {
    let uid: EntityUID
    let parents: [EntityUID]
    let attrs: CedarMap<Attr, CedarValue>
    let tags: CedarMap<Tag, CedarValue>
    let sourceSpan: SourceSpan
}

private func parseLoadedEntity(_ value: JSONValue) -> Result<LoadedEntity, Diagnostics> {
    let entries: [JSONObjectEntry]
    switch jsonObject(value, category: .entity, code: "entity.invalidEntity", expectation: "Each entity must be a JSON object") {
    case let .success(objectEntries):
        entries = objectEntries
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }

    let uidField = parseEntityUIDField(entries, owner: value.sourceSpan)
    let parents = parseEntityParents(findJSONField(entries, "parents")?.value ?? findJSONField(entries, "ancestors")?.value)
    let attrs = parseEntityValues(findJSONField(entries, "attrs")?.value, label: "attrs")
    let tags = parseEntityValues(findJSONField(entries, "tags")?.value, label: "tags")

    let diagnostics = uidField.diagnostics
        .appending(contentsOf: parents.diagnostics)
        .appending(contentsOf: attrs.diagnostics)
        .appending(contentsOf: tags.diagnostics)

    guard let uid = uidField.value else {
        return .failure(diagnostics)
    }

    guard !diagnostics.hasErrors, let parentsValue = parents.value, let attrsValue = attrs.value, let tagsValue = tags.value else {
        return .failure(diagnostics)
    }

    return .success(LoadedEntity(uid: uid, parents: parentsValue, attrs: attrsValue, tags: tagsValue, sourceSpan: value.sourceSpan))
}

private struct EntityParsed<Value> {
    let value: Value?
    let diagnostics: Diagnostics
}

/// Parse a "uid" field that can be either a string `Type::"id"` or an object `{"type":"T","id":"I"}`.
private func parseEntityUIDField(_ entries: [JSONObjectEntry], owner: SourceSpan) -> EntityParsed<EntityUID> {
    guard let field = findJSONField(entries, "uid") else {
        return EntityParsed(value: nil, diagnostics: failureDiagnostics(
            code: "entity.missingUID",
            category: .entity,
            message: "Entity is missing required field 'uid'",
            sourceSpan: owner
        ))
    }

    switch field.value {
    case let .string(raw, _):
        switch parseEntityUID(raw, category: .entity, code: "entity.invalidUID", sourceSpan: field.value.sourceSpan) {
        case let .success(uid):
            return EntityParsed(value: uid, diagnostics: .empty)
        case let .failure(errors):
            return EntityParsed(value: nil, diagnostics: errors)
        }
    case let .object(objectEntries, _):
        return parseEntityUIDObject(objectEntries, sourceSpan: field.value.sourceSpan)
    default:
        return EntityParsed(value: nil, diagnostics: failureDiagnostics(
            code: "entity.invalidUID",
            category: .entity,
            message: "Field 'uid' must be a string or {\"type\":...,\"id\":...} object",
            sourceSpan: field.value.sourceSpan
        ))
    }
}

/// Parse `{"type":"T","id":"I"}` object format for entity UIDs.
private func parseEntityUIDObject(_ entries: [JSONObjectEntry], sourceSpan: SourceSpan) -> EntityParsed<EntityUID> {
    guard let typeField = findJSONField(entries, "type") else {
        return EntityParsed(value: nil, diagnostics: failureDiagnostics(
            code: "entity.invalidUID",
            category: .entity,
            message: "Entity UID object missing 'type' field",
            sourceSpan: sourceSpan
        ))
    }

    guard let idField = findJSONField(entries, "id") else {
        return EntityParsed(value: nil, diagnostics: failureDiagnostics(
            code: "entity.invalidUID",
            category: .entity,
            message: "Entity UID object missing 'id' field",
            sourceSpan: sourceSpan
        ))
    }

    guard case let .string(typeName, _) = typeField.value else {
        return EntityParsed(value: nil, diagnostics: failureDiagnostics(
            code: "entity.invalidUID",
            category: .entity,
            message: "Entity UID 'type' must be a string",
            sourceSpan: typeField.value.sourceSpan
        ))
    }

    guard case let .string(eid, _) = idField.value else {
        return EntityParsed(value: nil, diagnostics: failureDiagnostics(
            code: "entity.invalidUID",
            category: .entity,
            message: "Entity UID 'id' must be a string",
            sourceSpan: idField.value.sourceSpan
        ))
    }

    let uid = EntityUID(ty: Name(id: typeName), eid: eid)
    return EntityParsed(value: uid, diagnostics: .empty)
}

/// Parse a single parent entry that can be a string `Type::"id"` or an object `{"type":"T","id":"I"}`.
private func parseParentUID(_ value: JSONValue) -> Result<EntityUID, Diagnostics> {
    switch value {
    case let .string(raw, _):
        return parseEntityUID(raw, category: .entity, code: "entity.invalidParent", sourceSpan: value.sourceSpan)
    case let .object(entries, _):
        let parsed = parseEntityUIDObject(entries, sourceSpan: value.sourceSpan)
        if let uid = parsed.value {
            return .success(uid)
        }
        return .failure(parsed.diagnostics)
    default:
        return .failure(failureDiagnostics(
            code: "entity.invalidParent",
            category: .entity,
            message: "Parent must be an entity UID string or {\"type\":...,\"id\":...} object",
            sourceSpan: value.sourceSpan
        ))
    }
}

private func parseEntityParents(_ value: JSONValue?) -> EntityParsed<[EntityUID]> {
    guard let value else {
        return EntityParsed(value: [], diagnostics: .empty)
    }

    let values: [JSONValue]
    switch jsonArray(value, category: .entity, code: "entity.invalidParents", expectation: "parents must be a JSON array") {
    case let .success(arrayValues):
        values = arrayValues
    case let .failure(diagnostics):
        return EntityParsed(value: nil, diagnostics: diagnostics)
    }

    var parents: [EntityUID] = []
    var diagnostics = Diagnostics.empty

    for value in values {
        switch parseParentUID(value) {
        case let .success(uid):
            parents.append(uid)
        case let .failure(errors):
            diagnostics = diagnostics.appending(contentsOf: errors)
        }
    }

    return EntityParsed(value: diagnostics.hasErrors ? nil : parents, diagnostics: diagnostics)
}

private func parseEntityValues(_ value: JSONValue?, label: String) -> EntityParsed<CedarMap<String, CedarValue>> {
    guard let value else {
        return EntityParsed(value: .empty, diagnostics: .empty)
    }

    let entries: [JSONObjectEntry]
    switch jsonObject(value, category: .entity, code: "entity.invalid\(label.capitalized)", expectation: "\(label) must be a JSON object") {
    case let .success(objectEntries):
        entries = objectEntries
    case let .failure(diagnostics):
        return EntityParsed(value: nil, diagnostics: diagnostics)
    }

    var result: [(key: String, value: CedarValue)] = []
    var diagnostics = Diagnostics.empty

    for entry in entries {
        switch parseRestrictedExprValue(entry.value, category: .entity) {
        case let .success(restricted):
            switch restricted.materialize() {
            case let .success(materialized):
                result.append((key: entry.key, value: materialized))
            case let .failure(error):
                diagnostics = diagnostics.appending(Diagnostic(
                    code: "entity.invalidValue",
                    category: .entity,
                    severity: .error,
                    message: "Unable to materialize \(label) value: \(String(describing: error))",
                    sourceSpan: entry.value.sourceSpan
                ))
            }
        case let .failure(errors):
            diagnostics = diagnostics.appending(contentsOf: errors)
        }
    }

    return EntityParsed(value: diagnostics.hasErrors ? nil : CedarMap.make(result), diagnostics: diagnostics)
}

private func duplicateEntityDiagnostics(_ loaded: [LoadedEntity]) -> Diagnostics {
    var seen: [LoadedEntity] = []
    var diagnostics = Diagnostics.empty

    for entity in loaded {
        if seen.contains(where: { $0.uid == entity.uid }) {
            diagnostics = diagnostics.appending(Diagnostic(
                code: "entity.duplicateUID",
                category: .entity,
                severity: .error,
                message: "Duplicate entity identifier \(entity.uid)",
                sourceSpan: entity.sourceSpan
            ))
        } else {
            seen.append(entity)
        }
    }

    return diagnostics
}

private func hierarchyDiagnostics(_ loaded: [LoadedEntity], schema: Schema?) -> Diagnostics {
    var diagnostics = Diagnostics.empty

    for entity in loaded {
        for parent in entity.parents {
            // Missing parents are created implicitly — only validate schema constraints
            if let schema, let parentEntity = loaded.first(where: { $0.uid == parent }) {
                diagnostics = diagnostics.appending(contentsOf: schemaDiagnostics(for: entity, parent: parentEntity, schema: schema))
            }
        }
    }

    diagnostics = diagnostics.appending(contentsOf: cycleDiagnostics(loaded))
    return diagnostics
}

private func schemaDiagnostics(for entity: LoadedEntity, parent: LoadedEntity, schema: Schema) -> Diagnostics {
    let actionType = Name(id: "Action")

    if entity.uid.ty == actionType {
        guard let actionDefinition = schema.action(entity.uid) else {
            return failureDiagnostics(
                code: "entity.undeclaredType",
                category: .entity,
                message: "Action entity \(entity.uid) is not declared in the schema",
                sourceSpan: entity.sourceSpan
            )
        }

        guard parent.uid.ty == actionType, actionDefinition.memberOf.contains(parent.uid) else {
            return failureDiagnostics(
                code: "entity.invalidActionParent",
                category: .entity,
                message: "Action entity \(entity.uid) has an invalid parent \(parent.uid)",
                sourceSpan: entity.sourceSpan
            )
        }

        return .empty
    }

    guard let definition = schema.entityType(entity.uid.ty) else {
        return failureDiagnostics(
            code: "entity.undeclaredType",
            category: .entity,
            message: "Entity type \(entity.uid.ty) is not declared in the schema",
            sourceSpan: entity.sourceSpan
        )
    }

    if !definition.memberOfTypes.isEmpty && !definition.memberOfTypes.contains(parent.uid.ty) {
        return failureDiagnostics(
            code: "entity.invalidAncestorType",
            category: .entity,
            message: "Entity \(entity.uid) cannot be a member of \(parent.uid.ty)",
            sourceSpan: entity.sourceSpan
        )
    }

    return .empty
}

private func cycleDiagnostics(_ loaded: [LoadedEntity]) -> Diagnostics {
    for entity in loaded {
        if hasCycle(start: entity.uid, current: entity.uid, loaded: loaded, path: []) {
            return failureDiagnostics(
                code: "entity.cycle",
                category: .entity,
                message: "Entity hierarchy contains a cycle reachable from \(entity.uid)",
                sourceSpan: entity.sourceSpan
            )
        }
    }

    return .empty
}

private func hasCycle(start: EntityUID, current: EntityUID, loaded: [LoadedEntity], path: [EntityUID]) -> Bool {
    guard let entity = loaded.first(where: { $0.uid == current }) else {
        return false
    }

    var nextPath = path
    nextPath.append(current)

    for parent in entity.parents {
        if parent == start {
            return true
        }

        if nextPath.contains(where: { $0 == parent }) {
            return true
        }

        if hasCycle(start: start, current: parent, loaded: loaded, path: nextPath) {
            return true
        }
    }

    return false
}
