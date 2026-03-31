import Foundation

public func loadSchemaCedar(_ text: String, source: String? = nil) -> LoadResult<Schema> {
    var lexer = SchemaTextLexer(source: text, sourceName: source)
    switch lexer.tokenize() {
    case let .failure(diagnostics):
        return .failure(diagnostics)
    case let .success(tokens):
        var parser = SchemaTextParser(tokens: tokens, sourceName: source)
        return loadResult(parser.parseSchema())
    }
}

public func loadSchemaCedar(_ data: Data, source: String? = nil) -> LoadResult<Schema> {
    guard let text = String(data: data, encoding: .utf8) else {
        return .failure(Diagnostics([
            Diagnostic(
                code: "io.invalidUTF8",
                category: .io,
                severity: .error,
                message: "Input data is not valid UTF-8",
                sourceSpan: source.flatMap { name in
                    let location = SourceLocation(line: 1, column: 1, offset: 0)
                    return SourceSpan(start: location, end: location, source: name)
                }
            )
        ]))
    }

    return loadSchemaCedar(text, source: source)
}

private enum SchemaTextTokenKind {
    case identifier
    case string
    case symbol
    case eof
}

private struct SchemaTextToken {
    let kind: SchemaTextTokenKind
    let lexeme: String
    let sourceSpan: SourceSpan
    let stringContents: String?

    var isEOF: Bool {
        kind == .eof
    }
}

private struct SchemaTextLexer {
    private let sourceName: String?
    private let scalars: [Unicode.Scalar]
    private var index: Int
    private var location: SourceLocation

    init(source: String, sourceName: String?) {
        self.sourceName = sourceName
        self.scalars = Array(source.unicodeScalars)
        self.index = 0
        self.location = SourceLocation(line: 1, column: 1, offset: 0)
    }

    mutating func tokenize() -> Result<[SchemaTextToken], Diagnostics> {
        var tokens: [SchemaTextToken] = []

        while true {
            do {
                try skipTrivia()
                let token = try nextToken()
                tokens.append(token)
                if token.isEOF {
                    return .success(tokens)
                }
            } catch let diagnostic as Diagnostic {
                return .failure(Diagnostics([diagnostic]))
            } catch {
                let span = SourceSpan(start: location, end: location, source: sourceName)
                return .failure(Diagnostics([
                    Diagnostic(
                        code: "schema.internalLexerFailure",
                        category: .internal,
                        severity: .error,
                        message: "Unexpected schema lexer failure",
                        sourceSpan: span
                    )
                ]))
            }
        }
    }

    private mutating func skipTrivia() throws {
        while let scalar = peek() {
            if isWhitespace(scalar) {
                advance()
                continue
            }

            if scalar == "/", peek(offset: 1) == "/" {
                advance()
                advance()
                while let next = peek(), next != "\n" {
                    advance()
                }
                continue
            }

            if scalar == "/", peek(offset: 1) == "*" {
                let start = location
                advance()
                advance()

                while let next = peek() {
                    if next == "*", peek(offset: 1) == "/" {
                        advance()
                        advance()
                        break
                    }

                    advance()
                }

                if peek(offset: -1) != "/" {
                    throw schemaParseDiagnostic(
                        code: "schema.unterminatedComment",
                        message: "Unterminated block comment",
                        sourceSpan: span(from: start, to: location)
                    )
                }

                continue
            }

            return
        }
    }

    private mutating func nextToken() throws -> SchemaTextToken {
        let start = location

        guard let scalar = peek() else {
            let span = SourceSpan(start: location, end: location, source: sourceName)
            return SchemaTextToken(kind: .eof, lexeme: "", sourceSpan: span, stringContents: nil)
        }

        if isIdentifierStart(scalar) {
            var lexeme = ""
            while let current = peek(), isIdentifierContinue(current) {
                lexeme.unicodeScalars.append(advance())
            }

            return SchemaTextToken(kind: .identifier, lexeme: lexeme, sourceSpan: span(from: start, to: location), stringContents: nil)
        }

        if scalar == "\"" {
            return try stringToken(start: start)
        }

        if scalar == ":", peek(offset: 1) == ":" {
            advance()
            advance()
            return SchemaTextToken(kind: .symbol, lexeme: "::", sourceSpan: span(from: start, to: location), stringContents: nil)
        }

        let singleCharacterSymbols = ["@", "{", "}", "[", "]", "<", ">", "(", ")", ",", ";", ":", "?", "="]
        let lexeme = String(scalar)
        if singleCharacterSymbols.contains(where: { cedarStringEqual($0, lexeme) }) {
            advance()
            return SchemaTextToken(kind: .symbol, lexeme: lexeme, sourceSpan: span(from: start, to: location), stringContents: nil)
        }

        advance()
        throw schemaParseDiagnostic(
            code: "schema.invalidToken",
            message: "Unexpected token '\(lexeme)'",
            sourceSpan: span(from: start, to: location)
        )
    }

    private mutating func stringToken(start: SourceLocation) throws -> SchemaTextToken {
        advance()
        var contents = ""

        while let scalar = peek() {
            if scalar == "\"" {
                advance()
                return SchemaTextToken(
                    kind: .string,
                    lexeme: contents,
                    sourceSpan: span(from: start, to: location),
                    stringContents: contents
                )
            }

            if scalar == "\\" {
                advance()
                guard let escaped = peek() else {
                    throw schemaParseDiagnostic(
                        code: "schema.unterminatedString",
                        message: "String literal is not terminated",
                        sourceSpan: span(from: start, to: location)
                    )
                }

                switch escaped {
                case "\"": contents.append("\"")
                case "\\": contents.append("\\")
                case "n": contents.append("\n")
                case "r": contents.append("\r")
                case "t": contents.append("\t")
                case "0": contents.append("\0")
                case "u":
                    advance()
                    guard peek() == "{" else {
                        throw schemaParseDiagnostic(
                            code: "schema.invalidEscape",
                            message: "Invalid unicode escape sequence",
                            sourceSpan: span(from: start, to: location)
                        )
                    }
                    advance()

                    var hex = ""
                    while let current = peek(), current != "}" {
                        guard current.value <= 127,
                              (current.value >= 48 && current.value <= 57)
                                  || (current.value >= 65 && current.value <= 70)
                                  || (current.value >= 97 && current.value <= 102)
                        else {
                            throw schemaParseDiagnostic(
                                code: "schema.invalidEscape",
                                message: "Invalid unicode escape sequence",
                                sourceSpan: span(from: start, to: location)
                            )
                        }

                        hex.unicodeScalars.append(advance())
                    }

                    guard peek() == "}", !hex.isEmpty,
                          let value = UInt32(hex, radix: 16),
                          let unicode = Unicode.Scalar(value)
                    else {
                        throw schemaParseDiagnostic(
                            code: "schema.invalidEscape",
                            message: "Invalid unicode escape sequence",
                            sourceSpan: span(from: start, to: location)
                        )
                    }

                    contents.unicodeScalars.append(unicode)
                default:
                    throw schemaParseDiagnostic(
                        code: "schema.invalidEscape",
                        message: "Invalid escape sequence '\\\(escaped)'",
                        sourceSpan: span(from: start, to: location)
                    )
                }

                advance()
                continue
            }

            if scalar == "\n" {
                throw schemaParseDiagnostic(
                    code: "schema.unterminatedString",
                    message: "String literal is not terminated",
                    sourceSpan: span(from: start, to: location)
                )
            }

            contents.unicodeScalars.append(advance())
        }

        throw schemaParseDiagnostic(
            code: "schema.unterminatedString",
            message: "String literal is not terminated",
            sourceSpan: span(from: start, to: location)
        )
    }

    private func peek(offset: Int = 0) -> Unicode.Scalar? {
        let resolvedIndex = index + offset
        guard resolvedIndex >= 0, resolvedIndex < scalars.count else {
            return nil
        }

        return scalars[resolvedIndex]
    }

    @discardableResult
    private mutating func advance() -> Unicode.Scalar {
        let scalar = scalars[index]
        index += 1

        if scalar == "\n" {
            location = SourceLocation(line: location.line + 1, column: 1, offset: location.offset + 1)
        } else {
            location = SourceLocation(line: location.line, column: location.column + 1, offset: location.offset + 1)
        }

        return scalar
    }

    private func span(from start: SourceLocation, to end: SourceLocation) -> SourceSpan {
        SourceSpan(start: start, end: end, source: sourceName)
    }
}

private struct SchemaTextTypeRef: Sendable {
    indirect enum Kind: Sendable {
        case named(SchemaTextPathRef)
        case set(SchemaTextTypeRef)
        case record(CedarMap<Attr, SchemaTextQualifiedTypeRef>)
    }

    let kind: Kind
    let sourceSpan: SourceSpan?
}

private struct SchemaTextQualifiedTypeRef: Sendable {
    let type: SchemaTextTypeRef
    let required: Bool
}

private struct SchemaTextPathRef: Sendable {
    let components: [String]
    let namespace: [String]
    let sourceSpan: SourceSpan?

    var qualifiedName: Name {
        if components.count == 1 {
            return Name(id: components[0], path: namespace)
        }

        return Name(id: components.last ?? "", path: Array(components.dropLast()))
    }

    var actionUID: EntityUID {
        EntityUID(ty: Name(id: "Action", path: components), eid: "")
    }
}

private struct SchemaTextEntityDefinition: Sendable {
    let name: Name
    let memberOfTypes: [Name]
    let attributes: CedarMap<Attr, SchemaTextQualifiedTypeRef>
    let tags: SchemaTextTypeRef?
    let enumEntityIDs: CedarSet<String>?
    let sourceSpan: SourceSpan?
}

private struct SchemaTextActionDefinition: Sendable {
    let uid: EntityUID
    let principalTypes: [Name]
    let resourceTypes: [Name]
    let memberOf: CedarSet<EntityUID>
    let context: CedarMap<Attr, SchemaTextQualifiedTypeRef>
    let sourceSpan: SourceSpan?
}

private struct SchemaTextAliasDefinition: Sendable {
    let name: Name
    let type: SchemaTextTypeRef
    let sourceSpan: SourceSpan?
}

private struct SchemaTextDocument: Sendable {
    var entities: [Name: SchemaTextEntityDefinition] = [:]
    var actions: [EntityUID: SchemaTextActionDefinition] = [:]
    var aliases: [Name: SchemaTextAliasDefinition] = [:]
}

private struct SchemaTextParser {
    private let tokens: [SchemaTextToken]
    private let sourceName: String?
    private var position: Int = 0

    init(tokens: [SchemaTextToken], sourceName: String?) {
        self.tokens = tokens
        self.sourceName = sourceName
    }

    mutating func parseSchema() -> Result<Schema, Diagnostics> {
        do {
            var document = SchemaTextDocument()
            try parseDeclarations(into: &document, namespace: [], until: nil)
            try expectEOF()
            return lower(document)
        } catch let diagnostic as Diagnostic {
            return .failure(Diagnostics([diagnostic]))
        } catch let diagnostics as Diagnostics {
            return .failure(diagnostics)
        } catch {
            let span = peek().sourceSpan
            return .failure(Diagnostics([
                Diagnostic(
                    code: "schema.internalParserFailure",
                    category: .internal,
                    severity: .error,
                    message: "Unexpected schema parser failure",
                    sourceSpan: span
                )
            ]))
        }
    }

    private mutating func parseDeclarations(
        into document: inout SchemaTextDocument,
        namespace: [String],
        until closingSymbol: String?
    ) throws {
        while !peek().isEOF {
            if let closingSymbol, checkSymbol(closingSymbol) {
                return
            }

            try parseAnnotations()

            if matchIdentifier("namespace") {
                let path = try parsePath()
                try expectSymbol("{")
                try parseDeclarations(into: &document, namespace: path, until: "}")
                try expectSymbol("}")
                continue
            }

            if matchIdentifier("type") {
                try parseTypeAlias(into: &document, namespace: namespace)
                continue
            }

            if matchIdentifier("entity") {
                try parseEntity(into: &document, namespace: namespace)
                continue
            }

            if matchIdentifier("action") {
                try parseAction(into: &document, namespace: namespace)
                continue
            }

            throw schemaParseDiagnostic(
                code: "schema.unexpectedDeclaration",
                message: "Expected schema declaration",
                sourceSpan: peek().sourceSpan
            )
        }
    }

    private mutating func parseAnnotations() throws {
        while matchSymbol("@") {
            _ = try parseIdentifier(expectation: "annotation name")
            if matchSymbol("(") {
                guard peek().kind == .string else {
                    throw schemaParseDiagnostic(
                        code: "schema.invalidAnnotation",
                        message: "Annotation values must be strings",
                        sourceSpan: peek().sourceSpan
                    )
                }

                advance()
                try expectSymbol(")")
            }
        }
    }

    private mutating func parseTypeAlias(into document: inout SchemaTextDocument, namespace: [String]) throws {
        let start = previous().sourceSpan.start
        let aliasName = try parseIdentifier(expectation: "type name")
        let fullName = Name(id: aliasName, path: namespace)
        try expectSymbol("=")
        let aliasedType = try parseType(namespace: namespace)
        try expectSymbol(";")

        if document.aliases[fullName] != nil {
            throw schemaParseDiagnostic(
                code: "schema.duplicateType",
                message: "Duplicate schema type declaration for \(fullName)",
                sourceSpan: aliasedType.sourceSpan
            )
        }

        document.aliases[fullName] = SchemaTextAliasDefinition(
            name: fullName,
            type: aliasedType,
            sourceSpan: SourceSpan(start: start, end: previous().sourceSpan.end, source: sourceName)
        )
    }

    private mutating func parseEntity(into document: inout SchemaTextDocument, namespace: [String]) throws {
        let start = previous().sourceSpan.start
        let entityNames = try parseIdentifierList()

        if matchIdentifier("enum") {
            let values = try parseEnumValues()
            try expectSymbol(";")

            for rawName in entityNames {
                let fullName = Name(id: rawName, path: namespace)
                if document.entities[fullName] != nil {
                    throw schemaParseDiagnostic(
                        code: "schema.duplicateEntityType",
                        message: "Duplicate entity declaration for \(fullName)",
                        sourceSpan: previous().sourceSpan
                    )
                }

                document.entities[fullName] = SchemaTextEntityDefinition(
                    name: fullName,
                    memberOfTypes: [],
                    attributes: .empty,
                    tags: nil,
                    enumEntityIDs: CedarSet.make(values),
                    sourceSpan: SourceSpan(start: start, end: previous().sourceSpan.end, source: sourceName)
                )
            }

            return
        }

        var memberOfTypes: [Name] = []
        if matchIdentifier("in") {
            memberOfTypes = try parseEntityTypeReferences(namespace: namespace)
        }

        var attributes: CedarMap<Attr, SchemaTextQualifiedTypeRef> = .empty
        if matchSymbol("=") || checkSymbol("{") {
            if previous().lexeme == "=" {
                attributes = try parseRecordType(namespace: namespace)
            } else {
                attributes = try parseRecordType(namespace: namespace)
            }
        }

        var tags: SchemaTextTypeRef?
        if matchIdentifier("tags") {
            tags = try parseType(namespace: namespace)
        }

        try expectSymbol(";")

        for rawName in entityNames {
            let fullName = Name(id: rawName, path: namespace)
            if document.entities[fullName] != nil {
                throw schemaParseDiagnostic(
                    code: "schema.duplicateEntityType",
                    message: "Duplicate entity declaration for \(fullName)",
                    sourceSpan: previous().sourceSpan
                )
            }

            document.entities[fullName] = SchemaTextEntityDefinition(
                name: fullName,
                memberOfTypes: memberOfTypes,
                attributes: attributes,
                tags: tags,
                enumEntityIDs: nil,
                sourceSpan: SourceSpan(start: start, end: previous().sourceSpan.end, source: sourceName)
            )
        }
    }

    private mutating func parseAction(into document: inout SchemaTextDocument, namespace: [String]) throws {
        let start = previous().sourceSpan.start
        let actionNames = try parseNameList()

        var memberOf: CedarSet<EntityUID> = .empty
        if matchIdentifier("in") {
            memberOf = CedarSet.make(try parseActionParents(namespace: namespace))
        }

        var principalTypes: [Name] = []
        var resourceTypes: [Name] = []
        var context: CedarMap<Attr, SchemaTextQualifiedTypeRef> = .empty
        if matchIdentifier("appliesTo") {
            let appliesTo = try parseAppliesTo(namespace: namespace)
            principalTypes = appliesTo.principalTypes
            resourceTypes = appliesTo.resourceTypes
            context = appliesTo.context
        }

        if matchIdentifier("attributes") {
            try expectSymbol("{")
            try expectSymbol("}")
        }

        try expectSymbol(";")

        for name in actionNames {
            let uid = EntityUID(ty: Name(id: "Action", path: namespace), eid: name)
            if document.actions[uid] != nil {
                throw schemaParseDiagnostic(
                    code: "schema.duplicateAction",
                    message: "Duplicate action declaration for \(uid)",
                    sourceSpan: previous().sourceSpan
                )
            }

            document.actions[uid] = SchemaTextActionDefinition(
                uid: uid,
                principalTypes: principalTypes,
                resourceTypes: resourceTypes,
                memberOf: memberOf,
                context: context,
                sourceSpan: SourceSpan(start: start, end: previous().sourceSpan.end, source: sourceName)
            )
        }
    }

    private mutating func parseEnumValues() throws -> [String] {
        try expectSymbol("[")
        var values: [String] = []

        while !checkSymbol("]") {
            guard peek().kind == .string, let value = peek().stringContents else {
                throw schemaParseDiagnostic(
                    code: "schema.invalidEnumValue",
                    message: "Enum values must be strings",
                    sourceSpan: peek().sourceSpan
                )
            }

            values.append(value)
            advance()
            if !matchSymbol(",") {
                break
            }
        }

        try expectSymbol("]")
        return values
    }

    private mutating func parseAppliesTo(namespace: [String]) throws -> (
        principalTypes: [Name],
        resourceTypes: [Name],
        context: CedarMap<Attr, SchemaTextQualifiedTypeRef>
    ) {
        try expectSymbol("{")

        var principalTypes: [Name] = []
        var resourceTypes: [Name] = []
        var context: CedarMap<Attr, SchemaTextQualifiedTypeRef> = .empty

        while !checkSymbol("}") {
            let field = try parseIdentifier(expectation: "appliesTo field")
            try expectSymbol(":")

            if cedarStringEqual(field, "principal") {
                principalTypes = try parseEntityTypeReferences(namespace: namespace)
            } else if cedarStringEqual(field, "resource") {
                resourceTypes = try parseEntityTypeReferences(namespace: namespace)
            } else if cedarStringEqual(field, "context") {
                context = try parseRecordType(namespace: namespace)
            } else {
                throw schemaParseDiagnostic(
                    code: "schema.invalidAppliesToField",
                    message: "Unexpected appliesTo field '\(field)'",
                    sourceSpan: previous().sourceSpan
                )
            }

            if !matchSymbol(",") {
                break
            }
        }

        try expectSymbol("}")
        return (principalTypes, resourceTypes, context)
    }

    private mutating func parseEntityTypeReferences(namespace: [String]) throws -> [Name] {
        if matchSymbol("[") {
            var names: [Name] = []

            while !checkSymbol("]") {
                let path = try parsePath()
                names.append(qualify(path, namespace: namespace))
                if !matchSymbol(",") {
                    break
                }
            }

            try expectSymbol("]")
            return names
        }

        return [qualify(try parsePath(), namespace: namespace)]
    }

    private mutating func parseActionParents(namespace: [String]) throws -> [EntityUID] {
        if matchSymbol("[") {
            var parents: [EntityUID] = []

            while !checkSymbol("]") {
                parents.append(try parseActionParent(namespace: namespace))
                if !matchSymbol(",") {
                    break
                }
            }

            try expectSymbol("]")
            return parents
        }

        return [try parseActionParent(namespace: namespace)]
    }

    private mutating func parseActionParent(namespace: [String]) throws -> EntityUID {
        let first = peek()
        if first.kind == .string, let name = first.stringContents {
            advance()
            return EntityUID(ty: Name(id: "Action", path: namespace), eid: name)
        }

        let path = try parsePath()
        if matchSymbol("::") {
            guard peek().kind == .string, let identifier = peek().stringContents else {
                throw schemaParseDiagnostic(
                    code: "schema.invalidActionParent",
                    message: "Qualified action references must end with a string identifier",
                    sourceSpan: peek().sourceSpan
                )
            }

            advance()
            return EntityUID(ty: Name(id: "Action", path: path), eid: identifier)
        }

        guard path.count == 1 else {
            throw schemaParseDiagnostic(
                code: "schema.invalidActionParent",
                message: "Action parent references must be bare action names or namespace-qualified names",
                sourceSpan: first.sourceSpan
            )
        }

        return EntityUID(ty: Name(id: "Action", path: namespace), eid: path[0])
    }

    private mutating func parseType(namespace: [String]) throws -> SchemaTextTypeRef {
        if checkSymbol("{") {
            let start = peek().sourceSpan
            return SchemaTextTypeRef(kind: .record(try parseRecordType(namespace: namespace)), sourceSpan: start)
        }

        if matchIdentifier("Set") {
            let start = previous().sourceSpan
            try expectSymbol("<")
            let element = try parseType(namespace: namespace)
            try expectSymbol(">")
            return SchemaTextTypeRef(kind: .set(element), sourceSpan: SourceSpan(start: start.start, end: previous().sourceSpan.end, source: sourceName))
        }

        let path = try parsePath()
        let span = previous().sourceSpan
        return SchemaTextTypeRef(
            kind: .named(SchemaTextPathRef(components: path, namespace: namespace, sourceSpan: span)),
            sourceSpan: span
        )
    }

    private mutating func parseRecordType(namespace: [String]) throws -> CedarMap<Attr, SchemaTextQualifiedTypeRef> {
        try expectSymbol("{")
        var attributes: [(key: Attr, value: SchemaTextQualifiedTypeRef)] = []

        while !checkSymbol("}") {
            try parseAnnotations()
            let attributeName = try parseName(expectation: "attribute name")
            let required = !matchSymbol("?")
            try expectSymbol(":")
            let type = try parseType(namespace: namespace)
            attributes.append((key: attributeName, value: SchemaTextQualifiedTypeRef(type: type, required: required)))

            if !matchSymbol(",") {
                break
            }
        }

        try expectSymbol("}")
        return CedarMap.make(attributes)
    }

    private mutating func parsePath() throws -> [String] {
        var components: [String] = [try parseIdentifier(expectation: "identifier")]
        while matchSymbol("::") {
            components.append(try parseIdentifier(expectation: "identifier"))
        }
        return components
    }

    private mutating func parseIdentifierList() throws -> [String] {
        var names: [String] = [try parseIdentifier(expectation: "identifier")]
        while matchSymbol(",") {
            names.append(try parseIdentifier(expectation: "identifier"))
        }
        return names
    }

    private mutating func parseNameList() throws -> [String] {
        var names: [String] = [try parseName(expectation: "name")]
        while matchSymbol(",") {
            names.append(try parseName(expectation: "name"))
        }
        return names
    }

    private mutating func parseIdentifier(expectation: String) throws -> String {
        guard peek().kind == .identifier else {
            throw schemaParseDiagnostic(
                code: "schema.unexpectedToken",
                message: "Expected \(expectation)",
                sourceSpan: peek().sourceSpan
            )
        }

        let token = advance()
        return token.lexeme
    }

    private mutating func parseName(expectation: String) throws -> String {
        let token = peek()
        switch token.kind {
        case .identifier:
            advance()
            return token.lexeme
        case .string:
            advance()
            return token.stringContents ?? token.lexeme
        default:
            throw schemaParseDiagnostic(
                code: "schema.unexpectedToken",
                message: "Expected \(expectation)",
                sourceSpan: token.sourceSpan
            )
        }
    }

    private mutating func expectSymbol(_ symbol: String) throws {
        guard matchSymbol(symbol) else {
            throw schemaParseDiagnostic(
                code: "schema.unexpectedToken",
                message: "Expected '\(symbol)'",
                sourceSpan: peek().sourceSpan
            )
        }
    }

    private mutating func expectEOF() throws {
        guard peek().isEOF else {
            throw schemaParseDiagnostic(
                code: "schema.unexpectedToken",
                message: "Unexpected trailing input",
                sourceSpan: peek().sourceSpan
            )
        }
    }

    @discardableResult
    private mutating func matchSymbol(_ symbol: String) -> Bool {
        guard checkSymbol(symbol) else {
            return false
        }
        advance()
        return true
    }

    @discardableResult
    private mutating func matchIdentifier(_ identifier: String) -> Bool {
        guard checkIdentifier(identifier) else {
            return false
        }
        advance()
        return true
    }

    private func checkSymbol(_ symbol: String) -> Bool {
        let token = peek()
        return token.kind == .symbol && cedarStringEqual(token.lexeme, symbol)
    }

    private func checkIdentifier(_ identifier: String) -> Bool {
        let token = peek()
        return token.kind == .identifier && cedarStringEqual(token.lexeme, identifier)
    }

    private func peek(_ offset: Int = 0) -> SchemaTextToken {
        let resolved = position + offset
        if resolved >= tokens.count {
            return tokens[tokens.count - 1]
        }

        return tokens[resolved]
    }

    @discardableResult
    private mutating func advance() -> SchemaTextToken {
        let token = peek()
        if !token.isEOF {
            position += 1
        }
        return token
    }

    private func previous() -> SchemaTextToken {
        tokens[max(0, position - 1)]
    }

    private func qualify(_ path: [String], namespace: [String]) -> Name {
        if path.count == 1 {
            return Name(id: path[0], path: namespace)
        }

        return Name(id: path.last ?? "", path: Array(path.dropLast()))
    }

    private func lower(_ document: SchemaTextDocument) -> Result<Schema, Diagnostics> {
        var diagnostics = Diagnostics.empty
        var resolutionCache: [Name: Schema.CedarType] = [:]
        var resolutionStack: [Name] = []

        func builtinType(for components: [String]) -> Schema.CedarType? {
            guard components.count == 1 else {
                return nil
            }

            switch components[0] {
            case "Bool":
                return .bool
            case "Long":
                return .int
            case "String":
                return .string
            case "decimal":
                return .ext(.decimal)
            case "ipaddr":
                return .ext(.ipaddr)
            case "datetime":
                return .ext(.datetime)
            case "duration":
                return .ext(.duration)
            default:
                return nil
            }
        }

        func resolveType(_ rawType: SchemaTextTypeRef) -> Schema.CedarType? {
            switch rawType.kind {
            case let .record(record):
                var resolvedEntries: [(key: Attr, value: Schema.QualifiedType)] = []
                for entry in record.entries {
                    guard let resolved = resolveType(entry.value.type) else {
                        continue
                    }
                    resolvedEntries.append((key: entry.key, value: Schema.QualifiedType(resolved, required: entry.value.required)))
                }
                return .record(CedarMap.make(resolvedEntries))
            case let .set(element):
                guard let resolved = resolveType(element) else {
                    return nil
                }
                return .set(resolved)
            case let .named(pathRef):
                if let builtin = builtinType(for: pathRef.components) {
                    return builtin
                }

                let qualified = pathRef.qualifiedName
                if let cached = resolutionCache[qualified] {
                    return cached
                }

                if qualified.id == "Action" {
                    return .entity(qualified)
                }

                if document.entities[qualified] != nil {
                    return .entity(qualified)
                }

                if let alias = document.aliases[qualified] {
                    if resolutionStack.contains(qualified) {
                        diagnostics = diagnostics.appending(schemaDiagnostic(
                            code: "schema.typeCycle",
                            message: "Schema type alias \(qualified) is recursive",
                            sourceSpan: alias.sourceSpan
                        ))
                        return nil
                    }

                    resolutionStack.append(qualified)
                    let resolved = resolveType(alias.type)
                    _ = resolutionStack.popLast()
                    if let resolved {
                        resolutionCache[qualified] = resolved
                    }
                    return resolved
                }

                diagnostics = diagnostics.appending(schemaDiagnostic(
                    code: "schema.unknownTypeReference",
                    message: "Unknown schema type reference \(qualified)",
                    sourceSpan: pathRef.sourceSpan
                ))
                return nil
            }
        }

        var entityEntries: [(key: Name, value: Schema.EntityTypeDefinition)] = []
        entityEntries.reserveCapacity(document.entities.count)
        for entity in document.entities.values.sorted(by: { $0.name < $1.name }) {
            var attributes: [(key: Attr, value: Schema.QualifiedType)] = []
            for entry in entity.attributes.entries {
                guard let resolved = resolveType(entry.value.type) else {
                    continue
                }
                attributes.append((key: entry.key, value: Schema.QualifiedType(resolved, required: entry.value.required)))
            }

            let tags = entity.tags.flatMap(resolveType)
            entityEntries.append((
                key: entity.name,
                value: Schema.EntityTypeDefinition(
                    name: entity.name,
                    memberOfTypes: CedarSet.make(entity.memberOfTypes),
                    attributes: CedarMap.make(attributes),
                    tags: tags,
                    enumEntityIDs: entity.enumEntityIDs
                )
            ))
        }

        var actionEntries: [(key: EntityUID, value: Schema.ActionDefinition)] = []
        actionEntries.reserveCapacity(document.actions.count)
        for action in document.actions.values.sorted(by: { $0.uid < $1.uid }) {
            var contextEntries: [(key: Attr, value: Schema.QualifiedType)] = []
            for entry in action.context.entries {
                guard let resolved = resolveType(entry.value.type) else {
                    continue
                }
                contextEntries.append((key: entry.key, value: Schema.QualifiedType(resolved, required: entry.value.required)))
            }

            actionEntries.append((
                key: action.uid,
                value: Schema.ActionDefinition(
                    uid: action.uid,
                    principalTypes: CedarSet.make(action.principalTypes),
                    resourceTypes: CedarSet.make(action.resourceTypes),
                    memberOf: action.memberOf,
                    context: CedarMap.make(contextEntries)
                )
            ))
        }

        if diagnostics.hasErrors {
            return .failure(diagnostics)
        }

        return .success(Schema(entityTypes: CedarMap.make(entityEntries), actions: CedarMap.make(actionEntries)))
    }
}

private func schemaParseDiagnostic(code: String, message: String, sourceSpan: SourceSpan?) -> Diagnostic {
    Diagnostic(
        code: code,
        category: .parse,
        severity: .error,
        message: message,
        sourceSpan: sourceSpan
    )
}

private func schemaDiagnostic(code: String, message: String, sourceSpan: SourceSpan?) -> Diagnostic {
    Diagnostic(
        code: code,
        category: .schema,
        severity: .error,
        message: message,
        sourceSpan: sourceSpan
    )
}

private func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
    scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r"
}

private func isIdentifierStart(_ scalar: Unicode.Scalar) -> Bool {
    scalar == "_" || CharacterSet.letters.contains(scalar)
}

private func isIdentifierContinue(_ scalar: Unicode.Scalar) -> Bool {
    isIdentifierStart(scalar) || CharacterSet.decimalDigits.contains(scalar)
}
