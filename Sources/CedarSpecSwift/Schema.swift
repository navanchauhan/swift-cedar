import Foundation

public struct Schema: Equatable, Hashable, Sendable {
    public enum ExtensionType: Int, CaseIterable, Equatable, Hashable, Comparable, Sendable {
        case decimal
        case ipaddr
        case datetime
        case duration

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public indirect enum CedarType: Equatable, Hashable, Sendable {
        case bool
        case int
        case string
        case entity(Name)
        case set(CedarType)
        case record(CedarMap<Attr, QualifiedType>)
        case ext(ExtensionType)
    }

    public struct QualifiedType: Equatable, Hashable, Sendable {
        public let type: CedarType
        public let required: Bool

        public init(_ type: CedarType, required: Bool = true) {
            self.type = type
            self.required = required
        }

        public static func required(_ type: CedarType) -> Self {
            Self(type, required: true)
        }

        public static func optional(_ type: CedarType) -> Self {
            Self(type, required: false)
        }
    }

    public struct EntityTypeDefinition: Equatable, Hashable, Sendable {
        public let name: Name
        public let memberOfTypes: CedarSet<Name>
        public let attributes: CedarMap<Attr, QualifiedType>
        public let tags: CedarType?
        public let enumEntityIDs: CedarSet<String>?

        public init(
            name: Name,
            memberOfTypes: CedarSet<Name> = .empty,
            attributes: CedarMap<Attr, QualifiedType> = .empty,
            tags: CedarType? = nil,
            enumEntityIDs: CedarSet<String>? = nil
        ) {
            self.name = name
            self.memberOfTypes = memberOfTypes
            self.attributes = attributes
            self.tags = tags
            self.enumEntityIDs = enumEntityIDs
        }
    }

    public struct ActionDefinition: Equatable, Hashable, Sendable {
        public let uid: EntityUID
        public let principalTypes: CedarSet<Name>
        public let resourceTypes: CedarSet<Name>
        public let memberOf: CedarSet<EntityUID>
        public let context: CedarMap<Attr, QualifiedType>

        public init(
            uid: EntityUID,
            principalTypes: CedarSet<Name> = .empty,
            resourceTypes: CedarSet<Name> = .empty,
            memberOf: CedarSet<EntityUID> = .empty,
            context: CedarMap<Attr, QualifiedType> = .empty
        ) {
            self.uid = uid
            self.principalTypes = principalTypes
            self.resourceTypes = resourceTypes
            self.memberOf = memberOf
            self.context = context
        }
    }

    public let entityTypes: CedarMap<Name, EntityTypeDefinition>
    public let actions: CedarMap<EntityUID, ActionDefinition>

    public init(
        entityTypes: CedarMap<Name, EntityTypeDefinition> = .empty,
        actions: CedarMap<EntityUID, ActionDefinition> = .empty
    ) {
        self.entityTypes = entityTypes
        self.actions = actions
    }

    public func entityType(_ name: Name) -> EntityTypeDefinition? {
        entityTypes.find(name)
    }

    public func action(_ uid: EntityUID) -> ActionDefinition? {
        actions.find(uid)
    }
}

public func loadSchema(_ text: String, source: String? = nil) -> LoadResult<Schema> {
    switch decodeJSONValue(text, source: source) {
    case let .success(root, diagnostics):
        switch parseSchema(root) {
        case let .success(schema):
            return .success(schema, diagnostics: diagnostics)
        case let .failure(errors):
            return .failure(errors)
        }
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }
}

public func loadSchema(_ data: Data, source: String? = nil) -> LoadResult<Schema> {
    switch decodeJSONValue(data, source: source) {
    case let .success(root, diagnostics):
        switch parseSchema(root) {
        case let .success(schema):
            return .success(schema, diagnostics: diagnostics)
        case let .failure(errors):
            return .failure(errors)
        }
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }
}

internal func parseSchema(_ value: JSONValue) -> Result<Schema, Diagnostics> {
    let entries: [JSONObjectEntry]
    switch jsonObject(value, category: .schema, code: "schema.invalidRoot", expectation: "Schema input must be a JSON object") {
    case let .success(objectEntries):
        entries = objectEntries
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }

    let entityTypes = parseSchemaEntityTypes(findJSONField(entries, "entityTypes")?.value)
    let actions = parseSchemaActions(findJSONField(entries, "actions")?.value)
    let diagnostics = entityTypes.diagnostics.appending(contentsOf: actions.diagnostics)

    guard !diagnostics.hasErrors else {
        return .failure(diagnostics)
    }

    return .success(Schema(entityTypes: entityTypes.value ?? .empty, actions: actions.value ?? .empty))
}

private struct PartialLoad<Value> {
    let value: Value?
    let diagnostics: Diagnostics
}

private func parseSchemaEntityTypes(_ value: JSONValue?) -> PartialLoad<CedarMap<Name, Schema.EntityTypeDefinition>> {
    guard let value else {
        return PartialLoad(value: .empty, diagnostics: .empty)
    }

    let entries: [JSONObjectEntry]
    switch jsonObject(value, category: .schema, code: "schema.invalidEntityTypes", expectation: "Schema entityTypes must be a JSON object") {
    case let .success(objectEntries):
        entries = objectEntries
    case let .failure(diagnostics):
        return PartialLoad(value: nil, diagnostics: diagnostics)
    }

    var definitions: [(key: Name, value: Schema.EntityTypeDefinition)] = []
    var diagnostics = Diagnostics.empty

    for entry in entries {
        let name: Name
        switch parseName(entry.key, category: .schema, code: "schema.invalidEntityTypeName", sourceSpan: entry.keySpan) {
        case let .success(parsed):
            name = parsed
        case let .failure(errors):
            diagnostics = diagnostics.appending(contentsOf: errors)
            continue
        }

        let objectEntries: [JSONObjectEntry]
        switch jsonObject(entry.value, category: .schema, code: "schema.invalidEntityType", expectation: "Each entity type definition must be a JSON object") {
        case let .success(parsedEntries):
            objectEntries = parsedEntries
        case let .failure(errors):
            diagnostics = diagnostics.appending(contentsOf: errors)
            continue
        }

        var memberOfTypes: [Name] = []
        if let memberOfEntry = findJSONField(objectEntries, "memberOfTypes") {
            switch jsonArray(memberOfEntry.value, category: .schema, code: "schema.invalidMemberOfTypes", expectation: "memberOfTypes must be a JSON array") {
            case let .success(values):
                for value in values {
                    switch jsonString(value, category: .schema, code: "schema.invalidMemberOfType", expectation: "memberOfTypes entries must be strings") {
                    case let .success(rawType):
                        switch parseName(rawType, category: .schema, code: "schema.invalidMemberOfType", sourceSpan: value.sourceSpan) {
                        case let .success(parsedType):
                            memberOfTypes.append(parsedType)
                        case let .failure(errors):
                            diagnostics = diagnostics.appending(contentsOf: errors)
                        }
                    case let .failure(errors):
                        diagnostics = diagnostics.appending(contentsOf: errors)
                    }
                }
            case let .failure(errors):
                diagnostics = diagnostics.appending(contentsOf: errors)
            }
        }

        let attributes = parseSchemaQualifiedTypeMap(findJSONField(objectEntries, "attrs")?.value, code: "schema.invalidEntityAttrs")
        let tags = parseSchemaType(findJSONField(objectEntries, "tags")?.value, code: "schema.invalidEntityTags")
        let enumEntityIDs = parseSchemaEnumEntityIDs(findJSONField(objectEntries, "enumEntityIDs")?.value, code: "schema.invalidEnumEntityIDs")

        diagnostics = diagnostics
            .appending(contentsOf: attributes.diagnostics)
            .appending(contentsOf: tags.diagnostics)
            .appending(contentsOf: enumEntityIDs.diagnostics)

        definitions.append((
            key: name,
            value: Schema.EntityTypeDefinition(
                name: name,
                memberOfTypes: CedarSet.make(memberOfTypes),
                attributes: attributes.value ?? .empty,
                tags: tags.value,
                enumEntityIDs: enumEntityIDs.value ?? nil
            )
        ))
    }

    return PartialLoad(value: CedarMap.make(definitions), diagnostics: diagnostics)
}

private func parseSchemaActions(_ value: JSONValue?) -> PartialLoad<CedarMap<EntityUID, Schema.ActionDefinition>> {
    guard let value else {
        return PartialLoad(value: .empty, diagnostics: .empty)
    }

    let entries: [JSONObjectEntry]
    switch jsonObject(value, category: .schema, code: "schema.invalidActions", expectation: "Schema actions must be a JSON object") {
    case let .success(objectEntries):
        entries = objectEntries
    case let .failure(diagnostics):
        return PartialLoad(value: nil, diagnostics: diagnostics)
    }

    var definitions: [(key: EntityUID, value: Schema.ActionDefinition)] = []
    var diagnostics = Diagnostics.empty

    for entry in entries {
        let uid: EntityUID
        switch parseEntityUID(entry.key, category: .schema, code: "schema.invalidActionUID", sourceSpan: entry.keySpan) {
        case let .success(parsed):
            uid = parsed
        case let .failure(errors):
            diagnostics = diagnostics.appending(contentsOf: errors)
            continue
        }

        let objectEntries: [JSONObjectEntry]
        switch jsonObject(entry.value, category: .schema, code: "schema.invalidAction", expectation: "Each action definition must be a JSON object") {
        case let .success(parsedEntries):
            objectEntries = parsedEntries
        case let .failure(errors):
            diagnostics = diagnostics.appending(contentsOf: errors)
            continue
        }

        let principalTypes = parseSchemaNameArray(findJSONField(objectEntries, "principalTypes")?.value, code: "schema.invalidActionPrincipalTypes")
        let resourceTypes = parseSchemaNameArray(findJSONField(objectEntries, "resourceTypes")?.value, code: "schema.invalidActionResourceTypes")
        let memberOf = parseSchemaUIDArray(findJSONField(objectEntries, "memberOf")?.value, code: "schema.invalidActionParents")
        let context = parseSchemaQualifiedTypeMap(findJSONField(objectEntries, "context")?.value, code: "schema.invalidActionContext")

        diagnostics = diagnostics
            .appending(contentsOf: principalTypes.diagnostics)
            .appending(contentsOf: resourceTypes.diagnostics)
            .appending(contentsOf: memberOf.diagnostics)
            .appending(contentsOf: context.diagnostics)

        definitions.append((
            key: uid,
            value: Schema.ActionDefinition(
                uid: uid,
                principalTypes: principalTypes.value ?? .empty,
                resourceTypes: resourceTypes.value ?? .empty,
                memberOf: memberOf.value ?? .empty,
                context: context.value ?? .empty
            )
        ))
    }

    return PartialLoad(value: CedarMap.make(definitions), diagnostics: diagnostics)
}

private func parseSchemaNameArray(_ value: JSONValue?, code: String) -> PartialLoad<CedarSet<Name>> {
    guard let value else {
        return PartialLoad(value: .empty, diagnostics: .empty)
    }

    let values: [JSONValue]
    switch jsonArray(value, category: .schema, code: code, expectation: "Expected a JSON array of names") {
    case let .success(arrayValues):
        values = arrayValues
    case let .failure(diagnostics):
        return PartialLoad(value: nil, diagnostics: diagnostics)
    }

    var names: [Name] = []
    var diagnostics = Diagnostics.empty

    for element in values {
        switch jsonString(element, category: .schema, code: code, expectation: "Expected a string name") {
        case let .success(rawName):
            switch parseName(rawName, category: .schema, code: code, sourceSpan: element.sourceSpan) {
            case let .success(name):
                names.append(name)
            case let .failure(errors):
                diagnostics = diagnostics.appending(contentsOf: errors)
            }
        case let .failure(errors):
            diagnostics = diagnostics.appending(contentsOf: errors)
        }
    }

    return PartialLoad(value: CedarSet.make(names), diagnostics: diagnostics)
}

private func parseSchemaUIDArray(_ value: JSONValue?, code: String) -> PartialLoad<CedarSet<EntityUID>> {
    guard let value else {
        return PartialLoad(value: .empty, diagnostics: .empty)
    }

    let values: [JSONValue]
    switch jsonArray(value, category: .schema, code: code, expectation: "Expected a JSON array of entity UIDs") {
    case let .success(arrayValues):
        values = arrayValues
    case let .failure(diagnostics):
        return PartialLoad(value: nil, diagnostics: diagnostics)
    }

    var uids: [EntityUID] = []
    var diagnostics = Diagnostics.empty

    for element in values {
        switch jsonString(element, category: .schema, code: code, expectation: "Expected an entity UID string") {
        case let .success(rawUID):
            switch parseEntityUID(rawUID, category: .schema, code: code, sourceSpan: element.sourceSpan) {
            case let .success(uid):
                uids.append(uid)
            case let .failure(errors):
                diagnostics = diagnostics.appending(contentsOf: errors)
            }
        case let .failure(errors):
            diagnostics = diagnostics.appending(contentsOf: errors)
        }
    }

    return PartialLoad(value: CedarSet.make(uids), diagnostics: diagnostics)
}

private func parseSchemaQualifiedTypeMap(_ value: JSONValue?, code: String) -> PartialLoad<CedarMap<Attr, Schema.QualifiedType>> {
    guard let value else {
        return PartialLoad(value: .empty, diagnostics: .empty)
    }

    let entries: [JSONObjectEntry]
    switch jsonObject(value, category: .schema, code: code, expectation: "Expected a JSON object of typed attributes") {
    case let .success(objectEntries):
        entries = objectEntries
    case let .failure(diagnostics):
        return PartialLoad(value: nil, diagnostics: diagnostics)
    }

    var parsedEntries: [(key: Attr, value: Schema.QualifiedType)] = []
    var diagnostics = Diagnostics.empty

    for entry in entries {
        let parsedType = parseSchemaQualifiedType(entry.value, code: code)
        diagnostics = diagnostics.appending(contentsOf: parsedType.diagnostics)
        if let value = parsedType.value {
            parsedEntries.append((key: entry.key, value: value))
        }
    }

    return PartialLoad(value: diagnostics.hasErrors ? nil : CedarMap.make(parsedEntries), diagnostics: diagnostics)
}

private func parseSchemaQualifiedType(_ value: JSONValue, code: String) -> PartialLoad<Schema.QualifiedType> {
    switch value {
    case .string:
        let parsedType = parseSchemaType(value, code: code)
        return PartialLoad(
            value: parsedType.value.map(Schema.QualifiedType.required),
            diagnostics: parsedType.diagnostics
        )
    case let .object(entries, _):
        let required: Bool
        if let requiredField = findJSONField(entries, "required") {
            switch jsonBool(requiredField.value, category: .schema, code: code, expectation: "required must be a boolean") {
            case let .success(parsedRequired):
                required = parsedRequired
            case let .failure(diagnostics):
                return PartialLoad(value: nil, diagnostics: diagnostics)
            }
        } else {
            required = true
        }

        let parsedType = parseSchemaType(value, code: code)
        return PartialLoad(
            value: parsedType.value.map { Schema.QualifiedType($0, required: required) },
            diagnostics: parsedType.diagnostics
        )
    default:
        return PartialLoad(value: nil, diagnostics: failureDiagnostics(
            code: code,
            category: .schema,
            message: "Expected an attribute type definition",
            sourceSpan: value.sourceSpan
        ))
    }
}

private func parseSchemaType(_ value: JSONValue?, code: String) -> PartialLoad<Schema.CedarType> {
    guard let value else {
        return PartialLoad(value: nil, diagnostics: .empty)
    }

    let rawType: String
    let objectEntries: [JSONObjectEntry]?

    switch value {
    case let .string(typeName, _):
        rawType = typeName
        objectEntries = nil
    case let .object(entries, span):
        objectEntries = entries
        let typeField: JSONObjectEntry
        switch requireJSONField(entries, "type", category: .schema, code: code, ownerSpan: span) {
        case let .success(field):
            typeField = field
        case let .failure(diagnostics):
            return PartialLoad(value: nil, diagnostics: diagnostics)
        }

        switch jsonString(typeField.value, category: .schema, code: code, expectation: "type must be a string") {
        case let .success(typeName):
            rawType = typeName
        case let .failure(diagnostics):
            return PartialLoad(value: nil, diagnostics: diagnostics)
        }
    default:
        return PartialLoad(value: nil, diagnostics: failureDiagnostics(
            code: code,
            category: .schema,
            message: "Expected a schema type definition",
            sourceSpan: value.sourceSpan
        ))
    }

    switch rawType {
    case "bool":
        return PartialLoad(value: .bool, diagnostics: .empty)
    case "int":
        return PartialLoad(value: .int, diagnostics: .empty)
    case "string":
        return PartialLoad(value: .string, diagnostics: .empty)
    case "entity":
        guard let objectEntries else {
            return PartialLoad(value: nil, diagnostics: failureDiagnostics(
                code: code,
                category: .schema,
                message: "entity types must include a name",
                sourceSpan: value.sourceSpan
            ))
        }

        guard let nameField = findJSONField(objectEntries, "name") ?? findJSONField(objectEntries, "entityType") else {
            return PartialLoad(value: nil, diagnostics: failureDiagnostics(
                code: code,
                category: .schema,
                message: "entity types must include a name field",
                sourceSpan: value.sourceSpan
            ))
        }

        switch jsonString(nameField.value, category: .schema, code: code, expectation: "entity type names must be strings") {
        case let .success(rawName):
            switch parseName(rawName, category: .schema, code: code, sourceSpan: nameField.value.sourceSpan) {
            case let .success(name):
                return PartialLoad(value: .entity(name), diagnostics: .empty)
            case let .failure(diagnostics):
                return PartialLoad(value: nil, diagnostics: diagnostics)
            }
        case let .failure(diagnostics):
            return PartialLoad(value: nil, diagnostics: diagnostics)
        }
    case "set":
        guard let objectEntries, let elementField = findJSONField(objectEntries, "element") else {
            return PartialLoad(value: nil, diagnostics: failureDiagnostics(
                code: code,
                category: .schema,
                message: "set types must include an element field",
                sourceSpan: value.sourceSpan
            ))
        }

        let elementType = parseSchemaType(elementField.value, code: code)
        return PartialLoad(value: elementType.value.map(Schema.CedarType.set), diagnostics: elementType.diagnostics)
    case "record":
        guard let objectEntries else {
            return PartialLoad(value: nil, diagnostics: failureDiagnostics(
                code: code,
                category: .schema,
                message: "record types must include attrs",
                sourceSpan: value.sourceSpan
            ))
        }

        let attrs = parseSchemaQualifiedTypeMap(findJSONField(objectEntries, "attrs")?.value, code: code)
        return PartialLoad(value: attrs.value.map(Schema.CedarType.record), diagnostics: attrs.diagnostics)
    case "decimal":
        return PartialLoad(value: .ext(.decimal), diagnostics: .empty)
    case "ip", "ipaddr":
        return PartialLoad(value: .ext(.ipaddr), diagnostics: .empty)
    case "datetime":
        return PartialLoad(value: .ext(.datetime), diagnostics: .empty)
    case "duration":
        return PartialLoad(value: .ext(.duration), diagnostics: .empty)
    default:
        return PartialLoad(value: nil, diagnostics: failureDiagnostics(
            code: code,
            category: .schema,
            message: "Unknown schema type '\(rawType)'",
            sourceSpan: value.sourceSpan
        ))
    }
}

private func parseSchemaEnumEntityIDs(_ value: JSONValue?, code: String) -> PartialLoad<CedarSet<String>?> {
    guard let value else {
        return PartialLoad(value: nil, diagnostics: .empty)
    }

    let values: [JSONValue]
    switch jsonArray(value, category: .schema, code: code, expectation: "enumEntityIDs must be an array of strings") {
    case let .success(arrayValues):
        values = arrayValues
    case let .failure(diagnostics):
        return PartialLoad(value: nil, diagnostics: diagnostics)
    }

    var entityIDs: [String] = []
    var diagnostics = Diagnostics.empty

    for element in values {
        switch jsonString(element, category: .schema, code: code, expectation: "enumEntityIDs entries must be strings") {
        case let .success(entityID):
            entityIDs.append(entityID)
        case let .failure(errors):
            diagnostics = diagnostics.appending(contentsOf: errors)
        }
    }

    return PartialLoad(value: diagnostics.hasErrors ? nil : CedarSet.make(entityIDs), diagnostics: diagnostics)
}
