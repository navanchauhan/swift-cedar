internal enum PolicyNamespaceKind: String, Sendable {
    case policy
    case template
    case templateLink
}

internal struct PolicyNamespaceEntry: Sendable {
    let id: PolicyID
    let kind: PolicyNamespaceKind
    let sourceSpan: SourceSpan?
}

internal func duplicatePolicyNamespaceDiagnostics(_ entries: [PolicyNamespaceEntry]) -> Diagnostics {
    var seen: [PolicyNamespaceEntry] = []
    var diagnostics = Diagnostics.empty

    for entry in entries {
        if let first = seen.first(where: { cedarStringEqual($0.id, entry.id) }) {
            diagnostics = diagnostics.appending(Diagnostic(
                code: duplicateCode(for: entry.kind),
                category: duplicateCategory(for: entry.kind),
                severity: .error,
                message: "Duplicate policy identifier '\(entry.id)' first declared in \(first.kind.rawValue)",
                sourceSpan: entry.sourceSpan
            ))
        } else {
            seen.append(entry)
        }
    }

    return diagnostics
}

private func duplicateCode(for kind: PolicyNamespaceKind) -> String {
    switch kind {
    case .policy:
        return "policy.duplicateID"
    case .template:
        return "template.duplicateID"
    case .templateLink:
        return "template.duplicateLinkedID"
    }
}

private func duplicateCategory(for kind: PolicyNamespaceKind) -> DiagnosticCategory {
    switch kind {
    case .policy:
        return .policy
    case .template, .templateLink:
        return .template
    }
}