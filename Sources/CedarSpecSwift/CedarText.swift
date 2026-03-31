import Foundation

public func loadPoliciesCedar(_ text: String, source: String? = nil) -> LoadResult<Policies> {
    loadCedarDocument(text, source: source, kind: .policy)
}

public func loadPoliciesCedar(
    _ text: String,
    source: String? = nil,
    compiling: Bool
) -> LoadResult<LoadedPolicies> {
    switch loadPoliciesCedar(text, source: source) {
    case let .success(policies, diagnostics):
        let compiledPolicies = compiling ? CompiledPolicies(policies) : nil
        if let compiledPolicies {
            warmCompiledPoliciesCache(compiledPolicies, for: policies)
        }

        return .success(
            LoadedPolicies(policies: policies, compiledPolicies: compiledPolicies),
            diagnostics: diagnostics
        )
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }
}

public func loadPoliciesCedar(_ data: Data, source: String? = nil) -> LoadResult<Policies> {
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

    return loadPoliciesCedar(text, source: source)
}

public func loadPoliciesCedar(
    _ data: Data,
    source: String? = nil,
    compiling: Bool
) -> LoadResult<LoadedPolicies> {
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

    return loadPoliciesCedar(text, source: source, compiling: compiling)
}

public func loadTemplatesCedar(_ text: String, source: String? = nil) -> LoadResult<Templates> {
    loadCedarDocument(text, source: source, kind: .template)
}

public func loadTemplatesCedar(_ data: Data, source: String? = nil) -> LoadResult<Templates> {
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

    return loadTemplatesCedar(text, source: source)
}

public func loadExpressionCedar(_ text: String, source: String? = nil) -> LoadResult<Expr> {
    loadCedarExpression(text, source: source)
}

public func loadExpressionCedar(_ data: Data, source: String? = nil) -> LoadResult<Expr> {
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

    return loadExpressionCedar(text, source: source)
}

public func formatCedar(_ text: String, source: String? = nil) -> LoadResult<String> {
    switch loadPoliciesCedar(text, source: source) {
    case let .success(policies, diagnostics):
        return .success(formatCedar(policies), diagnostics: diagnostics)
    case let .failure(policyDiagnostics):
        switch loadTemplatesCedar(text, source: source) {
        case let .success(templates, diagnostics):
            return .success(formatCedar(templates), diagnostics: diagnostics)
        case .failure:
            return .failure(policyDiagnostics)
        }
    }
}

public func formatCedar(_ data: Data, source: String? = nil) -> LoadResult<String> {
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

    return formatCedar(text, source: source)
}

public func formatCedar(_ policies: Policies) -> String {
    emitCedar(policies)
}

public func formatCedar(_ templates: Templates) -> String {
    emitCedar(templates)
}

public func formatCedar(_ policy: Policy) -> String {
    emitCedar(policy)
}

public func formatCedar(_ template: Template) -> String {
    emitCedar(template)
}

public func emitCedar(_ policies: Policies) -> String {
    policies.entries.map { emitCedar($0.value) }.joined(separator: "\n\n")
}

public func emitCedar(_ templates: Templates) -> String {
    templates.entries.map { emitCedar($0.value) }.joined(separator: "\n\n")
}

public func emitCedar(_ policy: Policy) -> String {
    CedarTextEmitter.emit(policy: policy)
}

public func emitCedar(_ template: Template) -> String {
    CedarTextEmitter.emit(template: template)
}

public func emitCedar(_ expr: Expr) -> String {
    CedarTextEmitter.emit(expr: expr)
}

private func loadCedarDocument<Output>(
    _ text: String,
    source: String?,
    kind: CedarTextDocumentKind
) -> LoadResult<Output> {
    var lexer = CedarTextLexer(source: text, sourceName: source)
    switch lexer.tokenize() {
    case let .failure(diagnostics):
        return .failure(diagnostics)
    case let .success(tokens):
        var parser = CedarTextParser(tokens: tokens, sourceName: source)
        switch kind {
        case .policy:
            return parser.parsePoliciesResult() as! LoadResult<Output>
        case .template:
            return parser.parseTemplatesResult() as! LoadResult<Output>
        }
    }
}

private func loadCedarExpression(
    _ text: String,
    source: String?
) -> LoadResult<Expr> {
    var lexer = CedarTextLexer(source: text, sourceName: source)
    switch lexer.tokenize() {
    case let .failure(diagnostics):
        return .failure(diagnostics)
    case let .success(tokens):
        var parser = CedarTextParser(tokens: tokens, sourceName: source)
        return parser.parseExpressionResult()
    }
}

private enum CedarTextDocumentKind {
    case policy
    case template
}

private enum CedarTextTokenKind {
    case identifier
    case integer
    case string
    case keyword
    case slot
    case symbol
    case eof
}

private struct CedarTextToken {
    let kind: CedarTextTokenKind
    let lexeme: String
    let sourceSpan: SourceSpan
    let stringContents: String?

    var isEOF: Bool {
        kind == .eof
    }
}

private struct CedarTextLexer {
    private let source: String
    private let sourceName: String?
    private var scalars: [Unicode.Scalar]
    private var index: Int
    private var location: SourceLocation

    init(source: String, sourceName: String?) {
        self.source = source
        self.sourceName = sourceName
        self.scalars = Array(source.unicodeScalars)
        self.index = 0
        self.location = SourceLocation(line: 1, column: 1, offset: 0)
    }

    mutating func tokenize() -> Result<[CedarTextToken], Diagnostics> {
        var tokens: [CedarTextToken] = []

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
                        code: "parse.internalLexerFailure",
                        category: .parse,
                        severity: .error,
                        message: "Unexpected lexer failure",
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
                while let commentScalar = peek(), commentScalar != "\n" {
                    advance()
                }
                continue
            }

            if scalar == "/", peek(offset: 1) == "*" {
                let start = location
                advance()
                advance()
                while let commentScalar = peek() {
                    if commentScalar == "*", peek(offset: 1) == "/" {
                        advance()
                        advance()
                        break
                    }

                    advance()
                }

                if peek(offset: -1) != "/" {
                    throw Diagnostic(
                        code: "parse.unterminatedComment",
                        category: .parse,
                        severity: .error,
                        message: "Unterminated block comment",
                        sourceSpan: span(from: start, to: location)
                    )
                }
                continue
            }

            return
        }
    }

    private mutating func nextToken() throws -> CedarTextToken {
        let start = location

        guard let scalar = peek() else {
            let span = SourceSpan(start: location, end: location, source: sourceName)
            return CedarTextToken(kind: .eof, lexeme: "", sourceSpan: span, stringContents: nil)
        }

        if isIdentifierStart(scalar) {
            var lexeme = ""
            while let current = peek(), isIdentifierContinue(current) {
                lexeme.unicodeScalars.append(advance())
            }

            let kind: CedarTextTokenKind = cedarTextKeywords.contains(where: { cedarStringEqual($0, lexeme) }) ? .keyword : .identifier
            return CedarTextToken(kind: kind, lexeme: lexeme, sourceSpan: span(from: start, to: location), stringContents: nil)
        }

        if isDigit(scalar) {
            var lexeme = ""
            while let current = peek(), isDigit(current) {
                lexeme.unicodeScalars.append(advance())
            }

            return CedarTextToken(kind: .integer, lexeme: lexeme, sourceSpan: span(from: start, to: location), stringContents: nil)
        }

        if scalar == "\"" {
            let contents = try scanQuotedContents(
                quote: "\"",
                diagnosticCode: "parse.unterminatedString",
                diagnosticMessage: "String literal is not terminated",
                start: start
            )
            let lexeme = "\"\(contents)\""
            return CedarTextToken(kind: .string, lexeme: lexeme, sourceSpan: span(from: start, to: location), stringContents: contents)
        }

        if scalar == "`" {
            let identifier = try scanBacktickIdentifier(start: start)
            return CedarTextToken(kind: .identifier, lexeme: identifier, sourceSpan: span(from: start, to: location), stringContents: nil)
        }

        if scalar == "?" {
            advance()
            if peek() == "`" {
                let identifier = try scanBacktickIdentifier(start: start)
                return CedarTextToken(kind: .slot, lexeme: identifier, sourceSpan: span(from: start, to: location), stringContents: nil)
            }

            guard let next = peek(), isIdentifierStart(next) else {
                throw Diagnostic(
                    code: "parse.invalidSlot",
                    category: .parse,
                    severity: .error,
                    message: "Expected a slot identifier after '?'",
                    sourceSpan: span(from: start, to: location)
                )
            }

            var lexeme = ""
            while let current = peek(), isIdentifierContinue(current) {
                lexeme.unicodeScalars.append(advance())
            }

            return CedarTextToken(kind: .slot, lexeme: lexeme, sourceSpan: span(from: start, to: location), stringContents: nil)
        }

        let twoCharacterSymbols = ["::", "==", "!=", "<=", ">=", "&&", "||"]
        if let next = peek(offset: 1) {
            let pair = String([Character(scalar), Character(next)])
            if twoCharacterSymbols.contains(where: { cedarStringEqual($0, pair) }) {
                advance()
                advance()
                return CedarTextToken(kind: .symbol, lexeme: pair, sourceSpan: span(from: start, to: location), stringContents: nil)
            }
        }

        let singleCharacterSymbols = ["@", ".", ",", ";", "(", ")", "{", "}", "[", "]", "+", "-", "*", "!", "<", ">", ":"]
        let lexeme = String(scalar)
        if singleCharacterSymbols.contains(where: { cedarStringEqual($0, lexeme) }) {
            advance()
            return CedarTextToken(kind: .symbol, lexeme: lexeme, sourceSpan: span(from: start, to: location), stringContents: nil)
        }

        advance()
        throw Diagnostic(
            code: "parse.invalidToken",
            category: .parse,
            severity: .error,
            message: "Unexpected token '\(lexeme)'",
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

    private mutating func scanQuotedContents(
        quote: Unicode.Scalar,
        diagnosticCode: String,
        diagnosticMessage: String,
        start: SourceLocation
    ) throws -> String {
        advance()
        var contents = ""

        while let current = peek() {
            if current == quote {
                advance()
                return contents
            }

            if current == "\n" {
                throw Diagnostic(
                    code: diagnosticCode,
                    category: .parse,
                    severity: .error,
                    message: diagnosticMessage,
                    sourceSpan: span(from: start, to: location)
                )
            }

            if current == "\\" {
                contents.unicodeScalars.append(advance())
                guard let escaped = peek(), escaped != "\n" else {
                    throw Diagnostic(
                        code: diagnosticCode,
                        category: .parse,
                        severity: .error,
                        message: diagnosticMessage,
                        sourceSpan: span(from: start, to: location)
                    )
                }
                contents.unicodeScalars.append(advance())
                continue
            }

            contents.unicodeScalars.append(advance())
        }

        throw Diagnostic(
            code: diagnosticCode,
            category: .parse,
            severity: .error,
            message: diagnosticMessage,
            sourceSpan: span(from: start, to: location)
        )
    }

    private mutating func scanBacktickIdentifier(start: SourceLocation) throws -> String {
        let contents = try scanQuotedContents(
            quote: "`",
            diagnosticCode: "parse.unterminatedIdentifier",
            diagnosticMessage: "Backtick identifier is not terminated",
            start: start
        )
        return try cedarDecodeStringLiteral(contents, allowPatternWildcardEscape: false, sourceSpan: span(from: start, to: location))
    }
}

private let cedarTextKeywords: [String] = [
    "permit", "forbid", "when", "unless", "principal", "action", "resource", "context",
    "true", "false", "if", "then", "else", "in", "like", "has", "is"
]

private func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
    scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r"
}

private func isIdentifierStart(_ scalar: Unicode.Scalar) -> Bool {
    scalar == "_" || (scalar.value >= 65 && scalar.value <= 90) || (scalar.value >= 97 && scalar.value <= 122)
}

private func isIdentifierContinue(_ scalar: Unicode.Scalar) -> Bool {
    isIdentifierStart(scalar) || isDigit(scalar)
}

private func isDigit(_ scalar: Unicode.Scalar) -> Bool {
    scalar.value >= 48 && scalar.value <= 57
}

private struct CedarTextParser {
    private let tokens: [CedarTextToken]
    private let sourceName: String?
    private var position: Int = 0
    private var syntheticPolicyIndex = 0
    private var syntheticTemplateIndex = 0

    init(tokens: [CedarTextToken], sourceName: String?) {
        self.tokens = tokens
        self.sourceName = sourceName
    }

    mutating func parsePoliciesResult() -> LoadResult<Policies> {
        switch parsePolicies() {
        case let .success(policies):
            return .success(policies, diagnostics: .empty)
        case let .failure(diagnostics):
            return .failure(diagnostics)
        }
    }

    mutating func parseTemplatesResult() -> LoadResult<Templates> {
        switch parseTemplates() {
        case let .success(templates):
            return .success(templates, diagnostics: .empty)
        case let .failure(diagnostics):
            return .failure(diagnostics)
        }
    }

    mutating func parseExpressionResult() -> LoadResult<Expr> {
        do {
            let expression = try parseExpression()
            let trailing = peek()
            guard trailing.isEOF else {
                throw Diagnostic(
                    code: "parse.expectedEOF",
                    category: .parse,
                    severity: .error,
                    message: "Unexpected trailing token '\(trailing.lexeme)'",
                    sourceSpan: trailing.sourceSpan
                )
            }
            return .success(expression, diagnostics: .empty)
        } catch let diagnostic as Diagnostic {
            return .failure(Diagnostics([diagnostic]))
        } catch {
            return .failure(Diagnostics([internalParserFailureDiagnostic()]))
        }
    }

    private mutating func parsePolicies() -> Result<Policies, Diagnostics> {
        var entries: [(key: PolicyID, value: Policy)] = []
        var namespaceEntries: [PolicyNamespaceEntry] = []

        while !peek().isEOF {
            switch parsePolicy() {
            case let .success(policy):
                entries.append((key: policy.id, value: policy))
                namespaceEntries.append(PolicyNamespaceEntry(id: policy.id, kind: .policy, sourceSpan: previous().sourceSpan))
            case let .failure(diagnostics):
                return .failure(diagnostics)
            }
        }

        let duplicates = duplicatePolicyNamespaceDiagnostics(namespaceEntries)
        if duplicates.hasErrors {
            return .failure(duplicates)
        }

        return .success(CedarMap.make(entries))
    }

    private mutating func parseTemplates() -> Result<Templates, Diagnostics> {
        var entries: [(key: TemplateID, value: Template)] = []
        var namespaceEntries: [PolicyNamespaceEntry] = []

        while !peek().isEOF {
            switch parseTemplate() {
            case let .success(template):
                entries.append((key: template.id, value: template))
                namespaceEntries.append(PolicyNamespaceEntry(id: template.id, kind: .template, sourceSpan: previous().sourceSpan))
            case let .failure(diagnostics):
                return .failure(diagnostics)
            }
        }

        let duplicates = duplicatePolicyNamespaceDiagnostics(namespaceEntries)
        if duplicates.hasErrors {
            return .failure(duplicates)
        }

        return .success(CedarMap.make(entries))
    }

    private mutating func parsePolicy() -> Result<Policy, Diagnostics> {
        do {
            let annotations = try parseAnnotations(documentKind: .policy)
            let effect = try parseEffect()
            try expect("(")
            try expectKeyword("principal")
            let principalScope = try parsePrincipalScope(allowSlots: false)
            try expect(",")
            try expectKeyword("action")
            let actionScope = try parseActionScope()
            try expect(",")
            try expectKeyword("resource")
            let resourceScope = try parseResourceScope(allowSlots: false)
            _ = match(",")
            try expect(")")
            let conditions = try parseConditions()
            try expect(";")
            let id = annotations.explicitID ?? nextSyntheticPolicyID()

            return .success(Policy(
                id: id,
                annotations: annotations.annotations,
                effect: effect,
                principalScope: principalScope,
                actionScope: actionScope,
                resourceScope: resourceScope,
                conditions: conditions
            ))
        } catch let diagnostic as Diagnostic {
            return .failure(Diagnostics([diagnostic]))
        } catch {
            return .failure(Diagnostics([internalParserFailureDiagnostic()]))
        }
    }

    private mutating func parseTemplate() -> Result<Template, Diagnostics> {
        do {
            let annotations = try parseAnnotations(documentKind: .template)
            let effect = try parseEffect()
            try expect("(")
            try expectKeyword("principal")
            let principalScope = try parsePrincipalTemplateScope()
            try expect(",")
            try expectKeyword("action")
            let actionScope = try parseActionScope()
            try expect(",")
            try expectKeyword("resource")
            let resourceScope = try parseResourceTemplateScope()
            _ = match(",")
            try expect(")")
            let conditions = try parseConditions()
            try expect(";")
            let id = annotations.explicitID ?? nextSyntheticTemplateID()

            return .success(Template(
                id: id,
                annotations: annotations.annotations,
                effect: effect,
                principalScope: principalScope,
                actionScope: actionScope,
                resourceScope: resourceScope,
                conditions: conditions
            ))
        } catch let diagnostic as Diagnostic {
            return .failure(Diagnostics([diagnostic]))
        } catch {
            return .failure(Diagnostics([internalParserFailureDiagnostic()]))
        }
    }

    private mutating func parseAnnotations(documentKind: CedarTextDocumentKind) throws -> ParsedTextAnnotations {
        var entries: [(key: String, value: String)] = []
        var seenKeys: [String] = []
        var explicitID: String?

        while match("@") {
            let keyToken = advance()
            guard keyToken.kind == .identifier || keyToken.kind == .keyword else {
                throw expectedDiagnostic("annotation key", at: keyToken.sourceSpan)
            }

            try expect("(")
            let valueToken = advance()
            guard valueToken.kind == .string else {
                throw expectedDiagnostic("annotation string literal", at: valueToken.sourceSpan)
            }

            let value = try decodeString(token: valueToken)
            try expect(")")

            if seenKeys.contains(where: { cedarStringEqual($0, keyToken.lexeme) }) {
                throw Diagnostic(
                    code: "parse.duplicateAnnotation",
                    category: .parse,
                    severity: .error,
                    message: "Duplicate annotation '@\(keyToken.lexeme)'",
                    sourceSpan: keyToken.sourceSpan
                )
            }
            seenKeys.append(keyToken.lexeme)

            if cedarStringEqual(keyToken.lexeme, "id") {
                explicitID = value
            } else {
                entries.append((key: keyToken.lexeme, value: value))
            }
        }

        return ParsedTextAnnotations(annotations: CedarMap.make(entries), explicitID: explicitID)
    }

    private mutating func parseEffect() throws -> Effect {
        let token = advance()
        switch token.lexeme {
        case "permit": return .permit
        case "forbid": return .forbid
        default:
            throw Diagnostic(
                code: "parse.invalidEffect",
                category: .parse,
                severity: .error,
                message: "Expected 'permit' or 'forbid'",
                sourceSpan: token.sourceSpan
            )
        }
    }

    private mutating func parsePrincipalScope(allowSlots: Bool) throws -> PrincipalScope {
        let parsed = try parseStaticScope(allowSlots: allowSlots, subject: "principal")
        switch parsed {
        case .any:
            return .any
        case let .entityEq(uid):
            return .eq(entity: uid)
        case let .entityIn(uid):
            return .in(entity: uid)
        case let .entityType(entityType):
            return .isEntityType(entityType: entityType)
        case let .entityTypeIn(entityType, uid):
            return .isEntityTypeIn(entityType: entityType, entity: uid)
        case .slotEq, .slotIn, .entityTypeInSlot:
            throw Diagnostic(
                code: "parse.invalidPolicySlot",
                category: .parse,
                severity: .error,
                message: "Policy scopes cannot contain template slots",
                sourceSpan: previous().sourceSpan
            )
        }
    }

    private mutating func parseResourceScope(allowSlots: Bool) throws -> ResourceScope {
        let parsed = try parseStaticScope(allowSlots: allowSlots, subject: "resource")
        switch parsed {
        case .any:
            return .any
        case let .entityEq(uid):
            return .eq(entity: uid)
        case let .entityIn(uid):
            return .in(entity: uid)
        case let .entityType(entityType):
            return .isEntityType(entityType: entityType)
        case let .entityTypeIn(entityType, uid):
            return .isEntityTypeIn(entityType: entityType, entity: uid)
        case .slotEq, .slotIn, .entityTypeInSlot:
            throw Diagnostic(
                code: "parse.invalidPolicySlot",
                category: .parse,
                severity: .error,
                message: "Policy scopes cannot contain template slots",
                sourceSpan: previous().sourceSpan
            )
        }
    }

    private mutating func parsePrincipalTemplateScope() throws -> PrincipalScopeTemplate {
        PrincipalScopeTemplate(try parseTemplateScope(subject: "principal"))
    }

    private mutating func parseResourceTemplateScope() throws -> ResourceScopeTemplate {
        ResourceScopeTemplate(try parseTemplateScope(subject: "resource"))
    }

    private mutating func parseTemplateScope(subject: String) throws -> ScopeTemplate {
        let parsed = try parseStaticScope(allowSlots: true, subject: subject)
        switch parsed {
        case .any:
            return .any
        case let .entityEq(uid):
            return .eq(.entityUID(uid))
        case let .entityIn(uid):
            return .in(.entityUID(uid))
        case let .slotEq(slot):
            return .eq(.slot(slot))
        case let .slotIn(slot):
            return .in(.slot(slot))
        case let .entityType(entityType):
            return .isEntityType(entityType)
        case let .entityTypeIn(entityType, uid):
            return .isEntityTypeIn(entityType, .entityUID(uid))
        case let .entityTypeInSlot(entityType, slot):
            return .isEntityTypeIn(entityType, .slot(slot))
        }
    }

    private mutating func parseStaticScope(allowSlots: Bool, subject: String) throws -> ParsedStaticScope {
        if match("==") {
            if !allowSlots, peek().kind == .slot {
                throw Diagnostic(
                    code: "parse.invalidPolicySlot",
                    category: .parse,
                    severity: .error,
                    message: "Policy scopes cannot contain template slots",
                    sourceSpan: peek().sourceSpan
                )
            }
            if allowSlots, let slot = try parseOptionalSlot() {
                return .slotEq(slot)
            }

            return .entityEq(try parseEntityUID())
        }

        if matchKeyword("in") {
            if !allowSlots, peek().kind == .slot {
                throw Diagnostic(
                    code: "parse.invalidPolicySlot",
                    category: .parse,
                    severity: .error,
                    message: "Policy scopes cannot contain template slots",
                    sourceSpan: peek().sourceSpan
                )
            }
            if allowSlots, let slot = try parseOptionalSlot() {
                return .slotIn(slot)
            }

            return .entityIn(try parseEntityUID())
        }

        if matchKeyword("is") {
            let entityType = try parseName()
            if matchKeyword("in") {
                if !allowSlots, peek().kind == .slot {
                    throw Diagnostic(
                        code: "parse.invalidPolicySlot",
                        category: .parse,
                        severity: .error,
                        message: "Policy scopes cannot contain template slots",
                        sourceSpan: peek().sourceSpan
                    )
                }
                if allowSlots, let slot = try parseOptionalSlot() {
                    return .entityTypeInSlot(entityType, slot)
                }

                return .entityTypeIn(entityType, try parseEntityUID())
            }

            return .entityType(entityType)
        }

        if scopeKeywordMatchesSubject(subject) {
            return .any
        }

        return .any
    }

    private mutating func parseActionScope() throws -> ActionScope {
        if peekKeyword("action") || peekSymbol(",") || peekSymbol(")") {
            return .any
        }

        if match("==") {
            return .eq(entity: try parseEntityUID())
        }

        if matchKeyword("in") {
            if match("[") {
                var entities: [EntityUID] = []
                if !peekSymbol("]") {
                    while true {
                        entities.append(try parseEntityUID())
                        if match(",") {
                            if peekSymbol("]") {
                                break
                            }
                            continue
                        }
                        break
                    }
                }
                try expect("]")
                return .actionInAny(entities: CedarSet.make(entities))
            }

            return .in(entity: try parseEntityUID())
        }

        if matchKeyword("is") {
            let entityType = try parseName()
            if matchKeyword("in") {
                return .isEntityTypeIn(entityType: entityType, entity: try parseEntityUID())
            }
            return .isEntityType(entityType: entityType)
        }

        return .any
    }

    private mutating func parseConditions() throws -> [Condition] {
        var conditions: [Condition] = []

        while true {
            if matchKeyword("when") {
                conditions.append(Condition(kind: .when, body: try parseConditionBody()))
                continue
            }

            if matchKeyword("unless") {
                conditions.append(Condition(kind: .unless, body: try parseConditionBody()))
                continue
            }

            return conditions
        }
    }

    private mutating func parseConditionBody() throws -> Expr {
        try expect("{")
        let expression = try parseExpression()
        try expect("}")
        return expression
    }

    private mutating func parseExpression() throws -> Expr {
        if matchKeyword("if") {
            let condition = try parseExpression()
            try expectKeyword("then")
            let thenExpr = try parseExpression()
            try expectKeyword("else")
            let elseExpr = try parseExpression()
            return .ifThenElse(condition, thenExpr, elseExpr)
        }

        return try parseOrExpression()
    }

    private mutating func parseOrExpression() throws -> Expr {
        var expression = try parseAndExpression()
        while match("||") {
            expression = .binaryApp(.or, expression, try parseAndExpression())
        }
        return expression
    }

    private mutating func parseAndExpression() throws -> Expr {
        var expression = try parseRelationExpression()
        while match("&&") {
            expression = .binaryApp(.and, expression, try parseRelationExpression())
        }
        return expression
    }

    private mutating func parseRelationExpression() throws -> Expr {
        let expression = try parseAddExpression()

        if match("==") {
            return .binaryApp(.equal, expression, try parseAddExpression())
        }
        if match("!=") {
            return .unaryApp(.not, .binaryApp(.equal, expression, try parseAddExpression()))
        }
        if match("<") {
            return .binaryApp(.lessThan, expression, try parseAddExpression())
        }
        if match("<=") {
            return .binaryApp(.lessThanOrEqual, expression, try parseAddExpression())
        }
        if match(">") {
            let rhs = try parseAddExpression()
            return .binaryApp(.lessThan, rhs, expression)
        }
        if match(">=") {
            let rhs = try parseAddExpression()
            return .binaryApp(.lessThanOrEqual, rhs, expression)
        }
        if matchKeyword("in") {
            return .binaryApp(.in, expression, try parseAddExpression())
        }
        if matchKeyword("has") {
            let attr = try parseAttributeNameForHas()
            return .hasAttr(expression, attr)
        }
        if matchKeyword("like") {
            let token = advance()
            guard token.kind == .string else {
                throw expectedDiagnostic("pattern string literal", at: token.sourceSpan)
            }
            return .like(expression, try decodePattern(token: token))
        }
        if matchKeyword("is") {
            let entityType = try parseName()
            if matchKeyword("in") {
                let rhs = try parseAddExpression()
                return .binaryApp(
                    .and,
                    .isEntityType(expression, entityType),
                    .binaryApp(.in, expression, rhs)
                )
            }

            return .isEntityType(expression, entityType)
        }

        return expression
    }

    private mutating func parseAddExpression() throws -> Expr {
        var expression = try parseMultiplyExpression()

        while true {
            if match("+") {
                expression = .binaryApp(.add, expression, try parseMultiplyExpression())
                continue
            }
            if match("-") {
                expression = .binaryApp(.sub, expression, try parseMultiplyExpression())
                continue
            }
            return expression
        }
    }

    private mutating func parseMultiplyExpression() throws -> Expr {
        var expression = try parseUnaryExpression()

        while match("*") {
            expression = .binaryApp(.mul, expression, try parseUnaryExpression())
        }

        return expression
    }

    private mutating func parseUnaryExpression() throws -> Expr {
        if match("!") {
            return .unaryApp(.not, try parseUnaryExpression())
        }

        if match("-") {
            if let minimumValue = try parseOptionalInt64MinimumLiteral() {
                return .lit(.prim(.int(minimumValue)))
            }

            return .unaryApp(.neg, try parseUnaryExpression())
        }

        return try parsePostfixExpression()
    }

    private mutating func parsePostfixExpression() throws -> Expr {
        var expression = try parsePrimaryExpression()

        while true {
            if match(".") {
                let memberToken = advance()
                guard memberToken.kind == .identifier else {
                    throw expectedDiagnostic("member identifier", at: memberToken.sourceSpan)
                }

                if match("(") {
                    let arguments = try parseArgumentList(afterOpeningParenConsumed: true)
                    expression = try lowerMethodCall(receiver: expression, nameToken: memberToken, arguments: arguments)
                } else {
                    expression = .getAttr(expression, memberToken.lexeme)
                }
                continue
            }

            if match("[") {
                let attrToken = advance()
                guard attrToken.kind == .string else {
                    throw expectedDiagnostic("string literal", at: attrToken.sourceSpan)
                }

                let attr = try decodeString(token: attrToken)
                try expect("]")
                expression = .getAttr(expression, attr)
                continue
            }

            return expression
        }
    }

    private mutating func parsePrimaryExpression() throws -> Expr {
        let token = advance()

        switch token.kind {
        case .keyword:
            switch token.lexeme {
            case "true":
                return .lit(.prim(.bool(true)))
            case "false":
                return .lit(.prim(.bool(false)))
            case "principal":
                return .variable(.principal)
            case "action":
                return .variable(.action)
            case "resource":
                return .variable(.resource)
            case "context":
                return .variable(.context)
            default:
                throw expectedDiagnostic("expression", at: token.sourceSpan)
            }
        case .integer:
            guard let value = Int64(token.lexeme) else {
                throw Diagnostic(
                    code: "parse.invalidInteger",
                    category: .parse,
                    severity: .error,
                    message: "Integer literal '\(token.lexeme)' is out of range for Int64",
                    sourceSpan: token.sourceSpan
                )
            }
            return .lit(.prim(.int(value)))
        case .string:
            return .lit(.prim(.string(try decodeString(token: token))))
        case .identifier:
            if match("(") {
                let arguments = try parseArgumentList(afterOpeningParenConsumed: true)
                guard let function = parseExtFun(token.lexeme) else {
                    throw Diagnostic(
                        code: "parse.unknownFunction",
                        category: .parse,
                        severity: .error,
                        message: "Unknown extension function '\(token.lexeme)'",
                        sourceSpan: token.sourceSpan
                    )
                }
                return .call(function, arguments)
            }

            if peekSymbol("::") {
                return .lit(.prim(.entityUID(try parseEntityUID(firstIdentifier: token.lexeme, firstSpan: token.sourceSpan))))
            }

            throw expectedDiagnostic("entity literal or extension call", at: token.sourceSpan)
        case .symbol where cedarStringEqual(token.lexeme, "("):
            let expression = try parseExpression()
            try expect(")")
            return expression
        case .symbol where cedarStringEqual(token.lexeme, "["):
            return .set(try parseExpressionList(closingSymbol: "]"))
        case .symbol where cedarStringEqual(token.lexeme, "{"):
            return .record(try parseRecordEntries())
        default:
            throw expectedDiagnostic("expression", at: token.sourceSpan)
        }
    }

    private mutating func parseArgumentList(afterOpeningParenConsumed: Bool) throws -> [Expr] {
        var arguments: [Expr] = []
        if peekSymbol(")") {
            try expect(")")
            return arguments
        }

        while true {
            arguments.append(try parseExpression())
            if match(",") {
                if peekSymbol(")") {
                    break
                }
                continue
            }
            break
        }

        try expect(")")
        return arguments
    }

    private mutating func parseExpressionList(closingSymbol: String) throws -> [Expr] {
        var expressions: [Expr] = []
        if peekSymbol(closingSymbol) {
            try expect(closingSymbol)
            return expressions
        }

        while true {
            expressions.append(try parseExpression())
            if match(",") {
                if peekSymbol(closingSymbol) {
                    break
                }
                continue
            }
            break
        }

        try expect(closingSymbol)
        return expressions
    }

    private mutating func parseRecordEntries() throws -> [(key: Attr, value: Expr)] {
        var entries: [(key: Attr, value: Expr)] = []

        if peekSymbol("}") {
            try expect("}")
            return entries
        }

        while true {
            let keyToken = advance()
            let key: String
            switch keyToken.kind {
            case .identifier:
                key = keyToken.lexeme
            case .string:
                key = try decodeString(token: keyToken)
            default:
                throw expectedDiagnostic("record key", at: keyToken.sourceSpan)
            }

            try expect(":")
            entries.append((key: key, value: try parseExpression()))
            if match(",") {
                if peekSymbol("}") {
                    break
                }
                continue
            }
            break
        }

        try expect("}")
        return entries
    }

    private mutating func parseAttributeNameForHas() throws -> String {
        let token = advance()
        switch token.kind {
        case .identifier:
            return token.lexeme
        case .string:
            return try decodeString(token: token)
        default:
            throw expectedDiagnostic("attribute name", at: token.sourceSpan)
        }
    }

    private mutating func parseName() throws -> Name {
        let first = advance()
        guard first.kind == .identifier else {
            throw expectedDiagnostic("identifier", at: first.sourceSpan)
        }

        var parts = [first.lexeme]
        while match("::") {
            let next = advance()
            guard next.kind == .identifier else {
                throw expectedDiagnostic("identifier", at: next.sourceSpan)
            }
            parts.append(next.lexeme)
        }

        return Name(id: parts.last ?? first.lexeme, path: Array(parts.dropLast()))
    }

    private mutating func parseEntityUID() throws -> EntityUID {
        let first = advance()
        guard first.kind == .identifier else {
            throw expectedDiagnostic("entity type identifier", at: first.sourceSpan)
        }
        return try parseEntityUID(firstIdentifier: first.lexeme, firstSpan: first.sourceSpan)
    }

    private mutating func parseEntityUID(firstIdentifier: String, firstSpan: SourceSpan) throws -> EntityUID {
        var parts = [firstIdentifier]
        repeat {
            try expect("::")
            let next = advance()
            if next.kind == .string {
                let name = Name(id: parts.last ?? firstIdentifier, path: Array(parts.dropLast()))
                return EntityUID(ty: name, eid: try decodeString(token: next))
            }

            guard next.kind == .identifier else {
                throw expectedDiagnostic("identifier or string literal", at: next.sourceSpan)
            }
            parts.append(next.lexeme)
        } while peekSymbol("::")

        throw Diagnostic(
            code: "parse.invalidEntityUID",
            category: .parse,
            severity: .error,
            message: "Entity literals must end in a string literal identifier",
            sourceSpan: firstSpan
        )
    }

    private mutating func parseOptionalSlot() throws -> Slot? {
        guard peek().kind == .slot else {
            return nil
        }
        return Slot(advance().lexeme)
    }

    private mutating func parseOptionalInt64MinimumLiteral() throws -> Int64? {
        guard peek().kind == .integer else {
            return nil
        }

        let token = advance()
        if cedarStringEqual(token.lexeme, "9223372036854775808") {
            return Int64.min
        }

        if Int64(token.lexeme) == nil {
            throw Diagnostic(
                code: "parse.invalidInteger",
                category: .parse,
                severity: .error,
                message: "Integer literal '\(token.lexeme)' is out of range for Int64",
                sourceSpan: token.sourceSpan
            )
        }

        position -= 1
        return nil
    }

    private mutating func lowerMethodCall(receiver: Expr, nameToken: CedarTextToken, arguments: [Expr]) throws -> Expr {
        switch nameToken.lexeme {
        case "contains":
            guard arguments.count == 1 else { throw invalidMethodArity(nameToken, expected: 1) }
            return .binaryApp(.contains, receiver, arguments[0])
        case "containsAll":
            guard arguments.count == 1 else { throw invalidMethodArity(nameToken, expected: 1) }
            return .binaryApp(.containsAll, receiver, arguments[0])
        case "containsAny":
            guard arguments.count == 1 else { throw invalidMethodArity(nameToken, expected: 1) }
            return .binaryApp(.containsAny, receiver, arguments[0])
        case "hasTag":
            guard arguments.count == 1 else { throw invalidMethodArity(nameToken, expected: 1) }
            return .binaryApp(.hasTag, receiver, arguments[0])
        case "getTag":
            guard arguments.count == 1 else { throw invalidMethodArity(nameToken, expected: 1) }
            return .binaryApp(.getTag, receiver, arguments[0])
        case "isEmpty":
            guard arguments.isEmpty else { throw invalidMethodArity(nameToken, expected: 0) }
            return .unaryApp(.isEmpty, receiver)
        default:
            guard let function = parseExtFun(nameToken.lexeme) else {
                throw Diagnostic(
                    code: "parse.unknownMethod",
                    category: .parse,
                    severity: .error,
                    message: "Unknown method '\(nameToken.lexeme)'",
                    sourceSpan: nameToken.sourceSpan
                )
            }
            return .call(function, [receiver] + arguments)
        }
    }

    private func invalidMethodArity(_ token: CedarTextToken, expected: Int) -> Diagnostic {
        Diagnostic(
            code: "parse.invalidArity",
            category: .parse,
            severity: .error,
            message: "Method '\(token.lexeme)' expects \(expected) argument\(expected == 1 ? "" : "s")",
            sourceSpan: token.sourceSpan
        )
    }

    private mutating func decodeString(token: CedarTextToken) throws -> String {
        guard let contents = token.stringContents else {
            throw expectedDiagnostic("string literal", at: token.sourceSpan)
        }
        return try cedarDecodeStringLiteral(contents, allowPatternWildcardEscape: false, sourceSpan: token.sourceSpan)
    }

    private mutating func decodePattern(token: CedarTextToken) throws -> Pattern {
        guard let contents = token.stringContents else {
            throw expectedDiagnostic("pattern string literal", at: token.sourceSpan)
        }
        return try cedarDecodePatternLiteral(contents, sourceSpan: token.sourceSpan)
    }

    private func scopeKeywordMatchesSubject(_ subject: String) -> Bool {
        let token = previous()
        return cedarStringEqual(token.lexeme, subject)
    }

    @discardableResult
    private mutating func expect(_ lexeme: String) throws -> CedarTextToken {
        let token = advance()
        guard cedarStringEqual(token.lexeme, lexeme) else {
            throw Diagnostic(
                code: "parse.expectedToken",
                category: .parse,
                severity: .error,
                message: "Expected '\(lexeme)' but found '\(token.lexeme)'",
                sourceSpan: token.sourceSpan
            )
        }
        return token
    }

    @discardableResult
    private mutating func expectKeyword(_ lexeme: String) throws -> CedarTextToken {
        let token = advance()
        guard token.kind == .keyword, cedarStringEqual(token.lexeme, lexeme) else {
            throw Diagnostic(
                code: "parse.expectedKeyword",
                category: .parse,
                severity: .error,
                message: "Expected keyword '\(lexeme)'",
                sourceSpan: token.sourceSpan
            )
        }
        return token
    }

    private mutating func match(_ lexeme: String) -> Bool {
        guard cedarStringEqual(peek().lexeme, lexeme) else {
            return false
        }
        position += 1
        return true
    }

    private mutating func matchKeyword(_ lexeme: String) -> Bool {
        let token = peek()
        guard token.kind == .keyword, cedarStringEqual(token.lexeme, lexeme) else {
            return false
        }
        position += 1
        return true
    }

    private func peekKeyword(_ lexeme: String) -> Bool {
        let token = peek()
        return token.kind == .keyword && cedarStringEqual(token.lexeme, lexeme)
    }

    private func peekSymbol(_ lexeme: String) -> Bool {
        cedarStringEqual(peek().lexeme, lexeme)
    }

    private mutating func advance() -> CedarTextToken {
        let token = tokens[position]
        if position < tokens.count - 1 {
            position += 1
        }
        return token
    }

    private func peek() -> CedarTextToken {
        tokens[position]
    }

    private func previous() -> CedarTextToken {
        tokens[max(position - 1, 0)]
    }

    private func expectedDiagnostic(_ expectation: String, at span: SourceSpan) -> Diagnostic {
        Diagnostic(
            code: "parse.expected\(expectation.replacingOccurrences(of: " ", with: ""))",
            category: .parse,
            severity: .error,
            message: "Expected \(expectation)",
            sourceSpan: span
        )
    }

    private func internalParserFailureDiagnostic() -> Diagnostic {
        Diagnostic(
            code: "parse.internalParserFailure",
            category: .parse,
            severity: .error,
            message: "Unexpected parser failure",
            sourceSpan: peek().sourceSpan
        )
    }

    private mutating func nextSyntheticPolicyID() -> PolicyID {
        defer { syntheticPolicyIndex += 1 }
        return "policy\(syntheticPolicyIndex)"
    }

    private mutating func nextSyntheticTemplateID() -> TemplateID {
        defer { syntheticTemplateIndex += 1 }
        return "template\(syntheticTemplateIndex)"
    }
}

private struct ParsedTextAnnotations {
    let annotations: CedarMap<String, String>
    let explicitID: String?
}

private enum ParsedStaticScope {
    case any
    case entityEq(EntityUID)
    case entityIn(EntityUID)
    case slotEq(Slot)
    case slotIn(Slot)
    case entityType(EntityType)
    case entityTypeIn(EntityType, EntityUID)
    case entityTypeInSlot(EntityType, Slot)
}

private func cedarDecodeStringLiteral(
    _ contents: String,
    allowPatternWildcardEscape: Bool,
    sourceSpan: SourceSpan
) throws -> String {
    var result = ""
    let scalars = Array(contents.unicodeScalars)
    var index = 0

    while index < scalars.count {
        let scalar = scalars[index]
        if scalar != "\\" {
            result.unicodeScalars.append(scalar)
            index += 1
            continue
        }

        index += 1
        guard index < scalars.count else {
            throw Diagnostic(
                code: "parse.invalidEscape",
                category: .parse,
                severity: .error,
                message: "Invalid string escape",
                sourceSpan: sourceSpan
            )
        }

        let escape = scalars[index]
        switch escape {
        case "n": result.unicodeScalars.append("\n")
        case "r": result.unicodeScalars.append("\r")
        case "t": result.unicodeScalars.append("\t")
        case "0": result.unicodeScalars.append("\0")
        case "\\": result.unicodeScalars.append("\\")
        case "\"": result.unicodeScalars.append("\"")
        case "'": result.unicodeScalars.append("'")
        case "*" where allowPatternWildcardEscape:
            result.unicodeScalars.append("*")
        case "x":
            let scalarValue = try cedarDecodeFixedHexEscape(scalars: scalars, index: &index, digits: 2, sourceSpan: sourceSpan)
            result.unicodeScalars.append(scalarValue)
        case "u":
            index += 1
            guard index < scalars.count, scalars[index] == "{" else {
                throw Diagnostic(
                    code: "parse.invalidEscape",
                    category: .parse,
                    severity: .error,
                    message: "Invalid unicode escape",
                    sourceSpan: sourceSpan
                )
            }
            let scalarValue = try cedarDecodeBracketedUnicodeEscape(scalars: scalars, index: &index, sourceSpan: sourceSpan)
            result.unicodeScalars.append(scalarValue)
        default:
            throw Diagnostic(
                code: "parse.invalidEscape",
                category: .parse,
                severity: .error,
                message: "Invalid string escape",
                sourceSpan: sourceSpan
            )
        }
        index += 1
    }

    return result
}

private func cedarDecodePatternLiteral(_ contents: String, sourceSpan: SourceSpan) throws -> Pattern {
    let scalars = Array(contents.unicodeScalars)
    var index = 0
    var elements: [PatElem] = []

    while index < scalars.count {
        let scalar = scalars[index]
        if scalar == "*" {
            elements.append(.wildcard)
            index += 1
            continue
        }

        if scalar == "\\" {
            let decoded = try cedarDecodeEscapedScalar(
                scalars: scalars,
                index: &index,
                allowPatternWildcardEscape: true,
                trailingBackslashIsLiteral: true,
                sourceSpan: sourceSpan
            )
            elements.append(.literal(decoded))
            index += 1
            continue
        }

        elements.append(.literal(scalar))
        index += 1
    }

    return Pattern(elements)
}

private func cedarDecodeEscapedScalar(
    scalars: [Unicode.Scalar],
    index: inout Int,
    allowPatternWildcardEscape: Bool,
    trailingBackslashIsLiteral: Bool,
    sourceSpan: SourceSpan
) throws -> Unicode.Scalar {
    guard scalars[index] == "\\" else {
        return scalars[index]
    }

    index += 1
    guard index < scalars.count else {
        if trailingBackslashIsLiteral {
            return "\\"
        }
        throw Diagnostic(
            code: "parse.invalidEscape",
            category: .parse,
            severity: .error,
            message: "Invalid string escape",
            sourceSpan: sourceSpan
        )
    }

    let escape = scalars[index]
    switch escape {
    case "n": return "\n"
    case "r": return "\r"
    case "t": return "\t"
    case "0": return "\0"
    case "\\": return "\\"
    case "\"": return "\""
    case "'": return "'"
    case "*" where allowPatternWildcardEscape:
        return "*"
    case "x":
        return try cedarDecodeFixedHexEscape(scalars: scalars, index: &index, digits: 2, sourceSpan: sourceSpan)
    case "u":
        index += 1
        guard index < scalars.count, scalars[index] == "{" else {
            throw Diagnostic(
                code: "parse.invalidEscape",
                category: .parse,
                severity: .error,
                message: "Invalid unicode escape",
                sourceSpan: sourceSpan
            )
        }
        return try cedarDecodeBracketedUnicodeEscape(scalars: scalars, index: &index, sourceSpan: sourceSpan)
    default:
        throw Diagnostic(
            code: "parse.invalidEscape",
            category: .parse,
            severity: .error,
            message: "Invalid string escape",
            sourceSpan: sourceSpan
        )
    }
}

private func cedarDecodeFixedHexEscape(
    scalars: [Unicode.Scalar],
    index: inout Int,
    digits: Int,
    sourceSpan: SourceSpan
) throws -> Unicode.Scalar {
    var raw = ""
    for _ in 0..<digits {
        index += 1
        guard index < scalars.count, let value = cedarHexValue(of: scalars[index]) else {
            throw Diagnostic(
                code: "parse.invalidEscape",
                category: .parse,
                severity: .error,
                message: "Invalid hex escape",
                sourceSpan: sourceSpan
            )
        }
        raw.append(String(scalars[index]))
        _ = value
    }

    guard let scalarValue = UInt32(raw, radix: 16), let scalar = Unicode.Scalar(scalarValue) else {
        throw Diagnostic(
            code: "parse.invalidEscape",
            category: .parse,
            severity: .error,
            message: "Invalid hex escape",
            sourceSpan: sourceSpan
        )
    }

    return scalar
}

private func cedarDecodeBracketedUnicodeEscape(
    scalars: [Unicode.Scalar],
    index: inout Int,
    sourceSpan: SourceSpan
) throws -> Unicode.Scalar {
    var raw = ""
    index += 1
    while index < scalars.count, scalars[index] != "}" {
        guard cedarHexValue(of: scalars[index]) != nil else {
            throw Diagnostic(
                code: "parse.invalidEscape",
                category: .parse,
                severity: .error,
                message: "Invalid unicode escape",
                sourceSpan: sourceSpan
            )
        }
        raw.append(String(scalars[index]))
        index += 1
    }

    guard index < scalars.count, !raw.isEmpty, raw.count <= 6, let scalarValue = UInt32(raw, radix: 16), let scalar = Unicode.Scalar(scalarValue) else {
        throw Diagnostic(
            code: "parse.invalidEscape",
            category: .parse,
            severity: .error,
            message: "Invalid unicode escape",
            sourceSpan: sourceSpan
        )
    }

    return scalar
}

private func cedarHexValue(of scalar: Unicode.Scalar) -> Int? {
    switch scalar.value {
    case 48...57:
        return Int(scalar.value - 48)
    case 65...70:
        return Int(scalar.value - 55)
    case 97...102:
        return Int(scalar.value - 87)
    default:
        return nil
    }
}

private enum CedarTextEmitter {
    private static let methodFunctions: CedarSet<ExtFun> = .make([
        .lessThan, .lessThanOrEqual, .greaterThan, .greaterThanOrEqual,
        .isIpv4, .isIpv6, .isLoopback, .isMulticast, .isInRange,
        .offset, .durationSince, .toDate, .toTime,
        .toMilliseconds, .toSeconds, .toMinutes, .toHours, .toDays,
    ])

    private static let keywordStrings: CedarSet<String> = .make(cedarTextKeywords)

    static func emit(policy: Policy) -> String {
        emitDocument(
            id: policy.id,
            annotations: policy.annotations,
            effect: policy.effect,
            principal: emit(scope: policy.principalScope),
            action: emit(scope: policy.actionScope),
            resource: emit(scope: policy.resourceScope),
            conditions: policy.conditions
        )
    }

    static func emit(template: Template) -> String {
        emitDocument(
            id: template.id,
            annotations: template.annotations,
            effect: template.effect,
            principal: emit(scope: template.principalScope),
            action: emit(scope: template.actionScope),
            resource: emit(scope: template.resourceScope),
            conditions: template.conditions
        )
    }

    static func emit(expr: Expr) -> String {
        emit(expr, parentPrecedence: .lowest)
    }

    private static func emit(_ expr: Expr) -> String {
        emit(expr, parentPrecedence: .lowest)
    }

    private static func emitDocument(
        id: String,
        annotations: CedarMap<String, String>,
        effect: Effect,
        principal: String,
        action: String,
        resource: String,
        conditions: [Condition]
    ) -> String {
        var lines: [String] = ["@id(\(emitStringLiteral(id)))"]
        lines.append(contentsOf: annotations.entries.map { "@\($0.key)(\(emitStringLiteral($0.value)))" })
        lines.append(effect == .permit ? "permit (" : "forbid (")
        lines.append("  \(principal),")
        lines.append("  \(action),")
        lines.append("  \(resource)")
        lines.append(")")

        if conditions.isEmpty {
            lines[lines.count - 1] += ";"
            return lines.joined(separator: "\n")
        }

        for (index, condition) in conditions.enumerated() {
            let prefix = condition.kind == .when ? "when" : "unless"
            let suffix = index == conditions.count - 1 ? ";" : ""
            lines.append("\(prefix) { \(emit(condition.body)) }\(suffix)")
        }

        return lines.joined(separator: "\n")
    }

    private static func emit(scope: PrincipalScope) -> String {
        switch scope {
        case .any:
            return "principal"
        case let .eq(entity):
            return "principal == \(emit(entity: entity))"
        case let .in(entity):
            return "principal in \(emit(entity: entity))"
        case let .isEntityType(entityType):
            return "principal is \(entityType)"
        case let .isEntityTypeIn(entityType, entity):
            return "principal is \(entityType) in \(emit(entity: entity))"
        }
    }

    private static func emit(scope: ResourceScope) -> String {
        switch scope {
        case .any:
            return "resource"
        case let .eq(entity):
            return "resource == \(emit(entity: entity))"
        case let .in(entity):
            return "resource in \(emit(entity: entity))"
        case let .isEntityType(entityType):
            return "resource is \(entityType)"
        case let .isEntityTypeIn(entityType, entity):
            return "resource is \(entityType) in \(emit(entity: entity))"
        }
    }

    private static func emit(scope: ActionScope) -> String {
        switch scope {
        case .any:
            return "action"
        case let .eq(entity):
            return "action == \(emit(entity: entity))"
        case let .in(entity):
            return "action in \(emit(entity: entity))"
        case let .isEntityType(entityType):
            return "action is \(entityType)"
        case let .isEntityTypeIn(entityType, entity):
            return "action is \(entityType) in \(emit(entity: entity))"
        case let .actionInAny(entities):
            let rendered = entities.elements.map(emit(entity:)).joined(separator: ", ")
            return "action in [\(rendered)]"
        }
    }

    private static func emit(scope: PrincipalScopeTemplate) -> String {
        emit(subject: "principal", scope: scope.scope)
    }

    private static func emit(scope: ResourceScopeTemplate) -> String {
        emit(subject: "resource", scope: scope.scope)
    }

    private static func emit(subject: String, scope: ScopeTemplate) -> String {
        switch scope {
        case .any:
            return subject
        case let .eq(value):
            return "\(subject) == \(emit(scopeValue: value))"
        case let .in(value):
            return "\(subject) in \(emit(scopeValue: value))"
        case let .isEntityType(entityType):
            return "\(subject) is \(entityType)"
        case let .isEntityTypeIn(entityType, value):
            return "\(subject) is \(entityType) in \(emit(scopeValue: value))"
        }
    }

    private static func emit(scopeValue: EntityUIDOrSlot) -> String {
        switch scopeValue {
        case let .entityUID(uid):
            return emit(entity: uid)
        case let .slot(slot):
            return "?\(slot.id)"
        }
    }

    private static func emit(entity: EntityUID) -> String {
        "\(entity.ty)::\(emitStringLiteral(entity.eid))"
    }

    private static func emit(_ expr: Expr, parentPrecedence: CedarTextPrecedence) -> String {
        let rendered: String
        let precedence = precedence(of: expr)

        switch expr {
        case let .lit(value):
            rendered = emit(literal: value)
        case let .variable(variable):
            rendered = emit(variable: variable)
        case let .unaryApp(.not, argument):
            rendered = "!\(emit(argument, parentPrecedence: .unary))"
        case let .unaryApp(.neg, argument):
            rendered = "-\(emit(argument, parentPrecedence: .unary))"
        case let .unaryApp(.isEmpty, argument):
            rendered = "\(emit(argument, parentPrecedence: .member)).isEmpty()"
        case let .binaryApp(.contains, lhs, rhs):
            rendered = "\(emit(lhs, parentPrecedence: .member)).contains(\(emit(rhs)))"
        case let .binaryApp(.containsAll, lhs, rhs):
            rendered = "\(emit(lhs, parentPrecedence: .member)).containsAll(\(emit(rhs)))"
        case let .binaryApp(.containsAny, lhs, rhs):
            rendered = "\(emit(lhs, parentPrecedence: .member)).containsAny(\(emit(rhs)))"
        case let .binaryApp(.hasTag, lhs, rhs):
            rendered = "\(emit(lhs, parentPrecedence: .member)).hasTag(\(emit(rhs)))"
        case let .binaryApp(.getTag, lhs, rhs):
            rendered = "\(emit(lhs, parentPrecedence: .member)).getTag(\(emit(rhs)))"
        case let .binaryApp(op, lhs, rhs):
            let operatorText = emit(binaryOperator: op)
            let (leftPrecedence, rightPrecedence) = childPrecedence(for: op)
            rendered = "\(emit(lhs, parentPrecedence: leftPrecedence)) \(operatorText) \(emit(rhs, parentPrecedence: rightPrecedence))"
        case let .ifThenElse(condition, thenExpr, elseExpr):
            rendered = "if \(emit(condition, parentPrecedence: .ifExpression)) then \(emit(thenExpr, parentPrecedence: .ifExpression)) else \(emit(elseExpr, parentPrecedence: .ifExpression))"
        case let .set(elements):
            rendered = "[\(elements.map { emit($0) }.joined(separator: ", "))]"
        case let .record(entries):
            rendered = "{\(entries.map { "\(emit(recordKey: $0.key)): \(emit($0.value))" }.joined(separator: ", "))}"
        case let .hasAttr(expr, attr):
            rendered = "\(emit(expr, parentPrecedence: .relationPlus)) has \(emit(hasAttrName: attr))"
        case let .getAttr(expr, attr):
            if cedarCanEmitIdentifier(attr) {
                rendered = "\(emit(expr, parentPrecedence: .member)).\(attr)"
            } else {
                rendered = "\(emit(expr, parentPrecedence: .member))[\(emitStringLiteral(attr))]"
            }
        case let .like(expr, pattern):
            rendered = "\(emit(expr, parentPrecedence: .relationPlus)) like \(emit(pattern: pattern))"
        case let .isEntityType(expr, entityType):
            rendered = "\(emit(expr, parentPrecedence: .relationPlus)) is \(entityType)"
        case let .call(function, arguments):
            rendered = emit(function: function, arguments: arguments)
        }

        if precedence < parentPrecedence {
            return "(\(rendered))"
        }

        return rendered
    }

    private static func emit(literal value: CedarValue) -> String {
        switch value {
        case let .prim(.bool(boolean)):
            return boolean ? "true" : "false"
        case let .prim(.int(integer)):
            return String(integer)
        case let .prim(.string(stringValue)):
            return emitStringLiteral(stringValue)
        case let .prim(.entityUID(uid)):
            return emit(entity: uid)
        case let .set(setValue):
            return "[\(setValue.elements.map(emit(literal:)).joined(separator: ", "))]"
        case let .record(recordValue):
            return "{\(recordValue.entries.map { "\(emit(recordKey: $0.key)): \(emit(literal: $0.value))" }.joined(separator: ", "))}"
        case let .ext(.decimal(value)):
            return "decimal(\(emitStringLiteral(value.rawValue)))"
        case let .ext(.ipaddr(value)):
            return "ip(\(emitStringLiteral(value.rawValue)))"
        case let .ext(.datetime(value)):
            return "datetime(\(emitStringLiteral(value.rawValue)))"
        case let .ext(.duration(value)):
            return "duration(\(emitStringLiteral(value.rawValue)))"
        }
    }

    private static func emit(variable: Var) -> String {
        switch variable {
        case .principal: return "principal"
        case .action: return "action"
        case .resource: return "resource"
        case .context: return "context"
        }
    }

    private static func emit(binaryOperator op: BinaryOp) -> String {
        switch op {
        case .and: return "&&"
        case .or: return "||"
        case .equal: return "=="
        case .lessThan: return "<"
        case .lessThanOrEqual: return "<="
        case .add: return "+"
        case .sub: return "-"
        case .mul: return "*"
        case .in: return "in"
        case .contains, .containsAll, .containsAny, .hasTag, .getTag:
            return ""
        }
    }

    private static func emit(function: ExtFun, arguments: [Expr]) -> String {
        let functionName = emit(functionName: function)
        if methodFunctions.contains(function), let receiver = arguments.first {
            let renderedArguments = Array(arguments.dropFirst()).map { emit($0) }.joined(separator: ", ")
            return "\(emit(receiver, parentPrecedence: .member)).\(functionName)(\(renderedArguments))"
        }

        return "\(functionName)(\(arguments.map { emit($0) }.joined(separator: ", ")))"
    }

    private static func emit(functionName function: ExtFun) -> String {
        switch function {
        case .decimal: return "decimal"
        case .lessThan: return "lessThan"
        case .lessThanOrEqual: return "lessThanOrEqual"
        case .greaterThan: return "greaterThan"
        case .greaterThanOrEqual: return "greaterThanOrEqual"
        case .ip: return "ip"
        case .isIpv4: return "isIpv4"
        case .isIpv6: return "isIpv6"
        case .isLoopback: return "isLoopback"
        case .isMulticast: return "isMulticast"
        case .isInRange: return "isInRange"
        case .datetime: return "datetime"
        case .duration: return "duration"
        case .offset: return "offset"
        case .durationSince: return "durationSince"
        case .toDate: return "toDate"
        case .toTime: return "toTime"
        case .toMilliseconds: return "toMilliseconds"
        case .toSeconds: return "toSeconds"
        case .toMinutes: return "toMinutes"
        case .toHours: return "toHours"
        case .toDays: return "toDays"
        }
    }

    private static func emit(recordKey key: String) -> String {
        cedarCanEmitIdentifier(key) ? key : emitStringLiteral(key)
    }

    private static func emit(hasAttrName key: String) -> String {
        cedarCanEmitIdentifier(key) ? key : emitStringLiteral(key)
    }

    private static func emit(pattern: Pattern) -> String {
        var rendered = "\""
        for element in pattern.elements {
            switch element {
            case .wildcard:
                rendered.append("*")
            case let .literal(scalar):
                rendered.append(contentsOf: emitEscapedScalar(scalar, escapeWildcard: true))
            }
        }
        rendered.append("\"")
        return rendered
    }

    private static func emitStringLiteral(_ value: String) -> String {
        var rendered = "\""
        for scalar in value.unicodeScalars {
            rendered.append(contentsOf: emitEscapedScalar(scalar, escapeWildcard: false))
        }
        rendered.append("\"")
        return rendered
    }

    private static func emitEscapedScalar(_ scalar: Unicode.Scalar, escapeWildcard: Bool) -> String {
        switch scalar {
        case "\n": return "\\n"
        case "\r": return "\\r"
        case "\t": return "\\t"
        case "\0": return "\\0"
        case "\\": return "\\\\"
        case "\"": return "\\\""
        case "*" where escapeWildcard:
            return "\\*"
        default:
            if scalar.value < 0x20 {
                return "\\u{\(String(scalar.value, radix: 16))}"
            }
            return String(scalar)
        }
    }

    private static func cedarCanEmitIdentifier(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first, isIdentifierStart(first) else {
            return false
        }

        guard !keywordStrings.contains(value) else {
            return false
        }

        for scalar in value.unicodeScalars.dropFirst() {
            guard isIdentifierContinue(scalar) else {
                return false
            }
        }

        return true
    }

    private static func precedence(of expr: Expr) -> CedarTextPrecedence {
        switch expr {
        case .ifThenElse:
            return .ifExpression
        case let .binaryApp(op, _, _):
            switch op {
            case .or:
                return .or
            case .and:
                return .and
            case .equal, .lessThan, .lessThanOrEqual, .in:
                return .relation
            case .add, .sub:
                return .add
            case .mul:
                return .multiply
            case .contains, .containsAll, .containsAny, .hasTag, .getTag:
                return .member
            }
        case let .unaryApp(op, _):
            return op == .isEmpty ? .member : .unary
        case .hasAttr, .like, .isEntityType:
            return .relationPlus
        case .getAttr, .call:
            return .member
        case .lit, .variable, .set, .record:
            return .primary
        }
    }

    private static func childPrecedence(for op: BinaryOp) -> (CedarTextPrecedence, CedarTextPrecedence) {
        switch op {
        case .or:
            return (.or, .and)
        case .and:
            return (.and, .relation)
        case .equal, .lessThan, .lessThanOrEqual, .in:
            return (.relationPlus, .relationPlus)
        case .add, .sub:
            return (.add, .multiply)
        case .mul:
            return (.multiply, .unary)
        case .contains, .containsAll, .containsAny, .hasTag, .getTag:
            return (.member, .lowest)
        }
    }
}

private enum CedarTextPrecedence: Int, Comparable {
    case lowest = 0
    case ifExpression = 1
    case or = 2
    case and = 3
    case relation = 4
    case relationPlus = 5
    case add = 6
    case multiply = 7
    case unary = 8
    case member = 9
    case primary = 10

    static func < (lhs: CedarTextPrecedence, rhs: CedarTextPrecedence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
