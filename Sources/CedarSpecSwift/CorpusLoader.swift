import Foundation

public struct Corpus: Equatable, Sendable {
    public let schema: Schema?
    public let templates: Templates
    public let templateLinks: TemplateLinkedPolicies
    public let policies: Policies
    public let entities: Entities
    public let request: Request?

    public init(
        schema: Schema? = nil,
        templates: Templates = .empty,
        templateLinks: TemplateLinkedPolicies = [],
        policies: Policies = .empty,
        entities: Entities = Entities(),
        request: Request? = nil
    ) {
        self.schema = schema
        self.templates = templates
        self.templateLinks = templateLinks
        self.policies = policies
        self.entities = entities
        self.request = request
    }
}

public func loadCorpus(_ text: String, source: String? = nil) -> LoadResult<Corpus> {
    switch decodeJSONValue(text, source: source) {
    case let .success(root, diagnostics):
        switch parseCorpus(root) {
        case let .success(corpus):
            return .success(corpus, diagnostics: diagnostics)
        case let .failure(errors):
            return .failure(errors)
        }
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }
}

public func loadCorpus(_ data: Data, source: String? = nil) -> LoadResult<Corpus> {
    switch decodeJSONValue(data, source: source) {
    case let .success(root, diagnostics):
        switch parseCorpus(root) {
        case let .success(corpus):
            return .success(corpus, diagnostics: diagnostics)
        case let .failure(errors):
            return .failure(errors)
        }
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }
}

private func parseCorpus(_ value: JSONValue) -> Result<Corpus, Diagnostics> {
    let entries: [JSONObjectEntry]
    switch jsonObject(value, category: .internal, code: "corpus.invalidRoot", expectation: "Corpus input must be a JSON object") {
    case let .success(objectEntries):
        entries = objectEntries
    case let .failure(diagnostics):
        return .failure(diagnostics)
    }

    let schemaResult: Result<Schema?, Diagnostics> = findJSONField(entries, "schema").map { parseOptionalSchema($0.value) } ?? .success(nil)
    var schemaValue: Schema?
    var diagnostics = Diagnostics.empty
    switch schemaResult {
    case let .success(schema):
        schemaValue = schema
    case let .failure(errors):
        diagnostics = diagnostics.appending(contentsOf: errors)
    }

    let templates: Result<Templates, Diagnostics> = findJSONField(entries, "templates").map { parseTemplates($0.value) } ?? .success(.empty)
    let templateLinks: Result<TemplateLinkedPolicies, Diagnostics> = findJSONField(entries, "templateLinks").map { parseTemplateLinks($0.value) } ?? .success([])
    let policies: Result<Policies, Diagnostics> = findJSONField(entries, "policies").map { parsePolicies($0.value) } ?? .success(.empty)
    let entities: Result<Entities, Diagnostics> = findJSONField(entries, "entities").map { parseEntities($0.value, schema: schemaValue) } ?? .success(Entities())
    let requestResult: Result<Request, Diagnostics>? = findJSONField(entries, "request").map { parseRequest($0.value, schema: schemaValue) }

    let parsedTemplates = collapse(templates, diagnostics: &diagnostics)
    let parsedLinks = collapse(templateLinks, diagnostics: &diagnostics)
    let parsedPolicies = collapse(policies, diagnostics: &diagnostics)
    let parsedEntities = collapse(entities, diagnostics: &diagnostics)
    let parsedRequest: Request?
    if let requestResult {
        parsedRequest = collapse(requestResult, diagnostics: &diagnostics)
    } else {
        parsedRequest = nil
    }

    if let templates = parsedTemplates, let links = parsedLinks, let policies = parsedPolicies {
        var namespaceEntries = templates.entries.map { PolicyNamespaceEntry(id: $0.key, kind: .template, sourceSpan: nil) }
        namespaceEntries.append(contentsOf: links.map { PolicyNamespaceEntry(id: $0.id, kind: .templateLink, sourceSpan: nil) })
        namespaceEntries.append(contentsOf: policies.entries.map { PolicyNamespaceEntry(id: $0.key, kind: .policy, sourceSpan: nil) })
        diagnostics = diagnostics.appending(contentsOf: duplicatePolicyNamespaceDiagnostics(namespaceEntries))
    }

    guard !diagnostics.hasErrors,
          let parsedTemplates,
          let parsedLinks,
          let parsedPolicies,
          let parsedEntities
    else {
        return .failure(diagnostics)
    }

    return .success(Corpus(
        schema: schemaValue,
        templates: parsedTemplates,
        templateLinks: parsedLinks,
        policies: parsedPolicies,
        entities: parsedEntities,
        request: parsedRequest
    ))
}

private func collapse<Value>(_ result: Result<Value, Diagnostics>, diagnostics: inout Diagnostics) -> Value? {
    switch result {
    case let .success(value):
        return value
    case let .failure(errors):
        diagnostics = diagnostics.appending(contentsOf: errors)
        return nil
    }
}

private func parseOptionalSchema(_ value: JSONValue) -> Result<Schema?, Diagnostics> {
    switch parseSchema(value) {
    case let .success(schema):
        return .success(schema)
    case let .failure(errors):
        return .failure(errors)
    }
}

