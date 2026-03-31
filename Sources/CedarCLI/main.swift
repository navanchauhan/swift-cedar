import CedarSpecSwift
import Foundation

private struct CLIError: Error {
    let message: String
    let exitCode: Int32
}

@main
enum CedarCLI {
    static func main() {
        do {
            let exitCode = try run(Array(CommandLine.arguments.dropFirst()))
            Foundation.exit(exitCode)
        } catch let error as CLIError {
            writeStderr(error.message)
            Foundation.exit(error.exitCode)
        } catch {
            writeStderr("Unexpected error: \(error)")
            Foundation.exit(1)
        }
    }

    static func run(_ arguments: [String]) throws -> Int32 {
        guard let subcommand = arguments.first else {
            print(rootUsage)
            return 0
        }

        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "authorize":
            return try runAuthorize(rest)
        case "validate":
            return try runValidate(rest)
        case "format":
            return try runFormat(rest)
        case "evaluate":
            return try runEvaluate(rest)
        case "help", "--help", "-h":
            print(rootUsage)
            return 0
        default:
            throw CLIError(message: "Unknown subcommand '\(subcommand)'\n\n\(rootUsage)", exitCode: 64)
        }
    }

    private static func runAuthorize(_ arguments: [String]) throws -> Int32 {
        if arguments.contains("--help") || arguments.contains("-h") {
            print(authorizeUsage)
            return 0
        }

        var policiesPath: String?
        var entitiesPath: String?
        var requestPath: String?
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--policies":
                policiesPath = try value(for: "--policies", arguments: arguments, index: &index)
            case "--entities":
                entitiesPath = try value(for: "--entities", arguments: arguments, index: &index)
            case "--request":
                requestPath = try value(for: "--request", arguments: arguments, index: &index)
            default:
                throw CLIError(message: "Unknown authorize option '\(arguments[index])'\n\n\(authorizeUsage)", exitCode: 64)
            }
            index += 1
        }

        guard let policiesPath, let entitiesPath, let requestPath else {
            throw CLIError(message: authorizeUsage, exitCode: 64)
        }

        let policies = try loadPoliciesFile(at: policiesPath)
        let entities = try loadEntitiesFile(at: entitiesPath, schema: nil)
        let request = try loadRequestFile(at: requestPath, schema: nil)
        let response = isAuthorized(request: request, entities: entities, policies: policies)

        print("decision: \(decisionString(response.decision))")
        print("determining: \(joined(response.determining.elements))")
        print("erroring: \(joined(response.erroring.elements))")
        return 0
    }

    private static func runValidate(_ arguments: [String]) throws -> Int32 {
        if arguments.contains("--help") || arguments.contains("-h") {
            print(validateUsage)
            return 0
        }

        var schemaPath: String?
        var policiesPath: String?
        var entitiesPath: String?
        var requestPath: String?
        var mode: ValidationMode = .strict
        var level: Int?
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--schema":
                schemaPath = try value(for: "--schema", arguments: arguments, index: &index)
            case "--policies":
                policiesPath = try value(for: "--policies", arguments: arguments, index: &index)
            case "--entities":
                entitiesPath = try value(for: "--entities", arguments: arguments, index: &index)
            case "--request":
                requestPath = try value(for: "--request", arguments: arguments, index: &index)
            case "--mode":
                let rawMode = try value(for: "--mode", arguments: arguments, index: &index)
                switch rawMode {
                case "strict":
                    mode = .strict
                case "permissive":
                    mode = .permissive
                default:
                    throw CLIError(message: "Unknown validation mode '\(rawMode)'", exitCode: 64)
                }
            case "--level":
                let rawLevel = try value(for: "--level", arguments: arguments, index: &index)
                guard let parsedLevel = Int(rawLevel), parsedLevel >= 0 else {
                    throw CLIError(message: "Validation level must be a non-negative integer", exitCode: 64)
                }
                level = parsedLevel
            default:
                throw CLIError(message: "Unknown validate option '\(arguments[index])'\n\n\(validateUsage)", exitCode: 64)
            }
            index += 1
        }

        guard let schemaPath else {
            throw CLIError(message: validateUsage, exitCode: 64)
        }

        guard policiesPath != nil || entitiesPath != nil || requestPath != nil else {
            throw CLIError(message: "Provide at least one of --policies, --entities, or --request\n\n\(validateUsage)", exitCode: 64)
        }

        let schema = try loadSchemaFile(at: schemaPath)
        var diagnostics = Diagnostics.empty
        var isValid = true

        if let policiesPath {
            let policies = try loadPoliciesFile(at: policiesPath)
            let result = validatePolicies(policies, schema: schema, mode: mode, level: level)
            diagnostics = diagnostics.appending(contentsOf: result.diagnostics)
            isValid = isValid && result.isValid
            print("policies: \(result.isValid ? "valid" : "invalid")")
        }

        if let entitiesPath {
            let entities = try loadEntitiesFile(at: entitiesPath, schema: schema)
            let result = validateEntities(entities, schema: schema, mode: mode)
            diagnostics = diagnostics.appending(contentsOf: result.diagnostics)
            isValid = isValid && result.isValid
            print("entities: \(result.isValid ? "valid" : "invalid")")
        }

        if let requestPath {
            let request = try loadRequestFile(at: requestPath, schema: schema)
            let result = validateRequest(request, schema: schema, mode: mode)
            diagnostics = diagnostics.appending(contentsOf: result.diagnostics)
            isValid = isValid && result.isValid
            print("request: \(result.isValid ? "valid" : "invalid")")
        }

        if !diagnostics.isEmpty {
            print("diagnostics:")
            for diagnostic in diagnostics.elements {
                print("- \(renderDiagnostic(diagnostic))")
            }
        }

        return isValid ? 0 : 66
    }

    private static func runFormat(_ arguments: [String]) throws -> Int32 {
        if arguments.contains("--help") || arguments.contains("-h") {
            print(formatUsage)
            return 0
        }

        var inPlace = false
        var files: [String] = []

        for argument in arguments {
            switch argument {
            case "--in-place":
                inPlace = true
            default:
                if argument.hasPrefix("-") {
                    throw CLIError(message: "Unknown format option '\(argument)'\n\n\(formatUsage)", exitCode: 64)
                }
                files.append(argument)
            }
        }

        guard !files.isEmpty else {
            throw CLIError(message: formatUsage, exitCode: 64)
        }

        if !inPlace && files.count > 1 {
            throw CLIError(message: "Use --in-place when formatting multiple files", exitCode: 64)
        }

        for file in files {
            let text = try readText(at: file)
            let formatted = try unwrapLoad(formatCedar(text, source: file), exitCode: 65)
            if inPlace {
                try writeText(formatted, to: file)
            } else {
                print(formatted)
            }
        }

        return 0
    }

    private static func runEvaluate(_ arguments: [String]) throws -> Int32 {
        if arguments.contains("--help") || arguments.contains("-h") {
            print(evaluateUsage)
            return 0
        }

        var expressionText: String?
        var expressionFile: String?
        var requestPath: String?
        var entitiesPath: String?
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--expression":
                expressionText = try value(for: "--expression", arguments: arguments, index: &index)
            case "--file":
                expressionFile = try value(for: "--file", arguments: arguments, index: &index)
            case "--request":
                requestPath = try value(for: "--request", arguments: arguments, index: &index)
            case "--entities":
                entitiesPath = try value(for: "--entities", arguments: arguments, index: &index)
            default:
                throw CLIError(message: "Unknown evaluate option '\(arguments[index])'\n\n\(evaluateUsage)", exitCode: 64)
            }
            index += 1
        }

        guard requestPath != nil else {
            throw CLIError(message: evaluateUsage, exitCode: 64)
        }

        guard (expressionText != nil) != (expressionFile != nil) else {
            throw CLIError(message: "Provide exactly one of --expression or --file\n\n\(evaluateUsage)", exitCode: 64)
        }

        let source = expressionFile ?? "<expr>"
        let rawExpression = try expressionText ?? readText(at: expressionFile!)
        let expression = try unwrapLoad(loadExpressionCedar(rawExpression, source: source), exitCode: 65)
        let request = try loadRequestFile(at: requestPath!, schema: nil)
        let entities = try entitiesPath.map { try loadEntitiesFile(at: $0, schema: nil) } ?? Entities()

        switch evaluate(expression, request: request, entities: entities) {
        case let .success(value):
            print("value: \(emitCedar(.lit(value)))")
            return 0
        case let .failure(error):
            throw CLIError(message: "Evaluation failed: \(error)", exitCode: 67)
        }
    }

    private static func value(for flag: String, arguments: [String], index: inout Int) throws -> String {
        let nextIndex = index + 1
        guard nextIndex < arguments.count else {
            throw CLIError(message: "Missing value for \(flag)", exitCode: 64)
        }
        index = nextIndex
        return arguments[nextIndex]
    }

    private static func loadPoliciesFile(at path: String) throws -> Policies {
        let data = try readData(at: path)
        if path.hasSuffix(".cedar") {
            return try unwrapLoad(loadPoliciesCedar(data, source: path), exitCode: 65)
        }
        if path.hasSuffix(".json") {
            return try unwrapLoad(loadPolicies(data, source: path), exitCode: 65)
        }

        switch loadPoliciesCedar(data, source: path) {
        case let .success(value, _):
            return value
        case .failure:
            return try unwrapLoad(loadPolicies(data, source: path), exitCode: 65)
        }
    }

    private static func loadSchemaFile(at path: String) throws -> Schema {
        let data = try readData(at: path)

        if path.hasSuffix(".cedarschema") {
            return try unwrapLoad(loadSchemaCedar(data, source: path), exitCode: 65)
        }

        if path.hasSuffix(".cedarschema.json") {
            return try unwrapLoad(loadSchemaJSON(data, source: path), exitCode: 65)
        }

        if path.hasSuffix(".json") {
            switch loadSchemaJSON(data, source: path) {
            case let .success(value, _):
                return value
            case .failure:
                return try unwrapLoad(loadSchema(data, source: path), exitCode: 65)
            }
        }

        return try unwrapLoad(loadSchemaCedar(data, source: path), exitCode: 65)
    }

    private static func loadEntitiesFile(at path: String, schema: Schema?) throws -> Entities {
        try unwrapLoad(loadEntities(try readData(at: path), schema: schema, source: path), exitCode: 65)
    }

    private static func loadRequestFile(at path: String, schema: Schema?) throws -> Request {
        try unwrapLoad(loadRequest(try readData(at: path), schema: schema, source: path), exitCode: 65)
    }

    private static func unwrapLoad<T>(_ result: LoadResult<T>, exitCode: Int32) throws -> T {
        switch result {
        case let .success(value, diagnostics):
            if diagnostics.hasErrors {
                throw CLIError(message: renderDiagnostics(diagnostics), exitCode: exitCode)
            }
            return value
        case let .failure(diagnostics):
            throw CLIError(message: renderDiagnostics(diagnostics), exitCode: exitCode)
        }
    }

    private static func readData(at path: String) throws -> Data {
        do {
            return try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw CLIError(message: "Unable to read '\(path)': \(error)", exitCode: 65)
        }
    }

    private static func readText(at path: String) throws -> String {
        guard let text = String(data: try readData(at: path), encoding: .utf8) else {
            throw CLIError(message: "Input '\(path)' is not valid UTF-8", exitCode: 65)
        }
        return text
    }

    private static func writeText(_ text: String, to path: String) throws {
        do {
            try text.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        } catch {
            throw CLIError(message: "Unable to write '\(path)': \(error)", exitCode: 65)
        }
    }

    private static func renderDiagnostics(_ diagnostics: Diagnostics) -> String {
        diagnostics.elements.map(renderDiagnostic).joined(separator: "\n")
    }

    private static func renderDiagnostic(_ diagnostic: Diagnostic) -> String {
        if let span = diagnostic.sourceSpan {
            let source = span.source ?? "<unknown>"
            return "\(diagnostic.code): \(diagnostic.message) (\(source):\(span.start.line):\(span.start.column))"
        }
        return "\(diagnostic.code): \(diagnostic.message)"
    }

    private static func decisionString(_ decision: Decision) -> String {
        decision == .allow ? "allow" : "deny"
    }

    private static func joined(_ values: [String]) -> String {
        values.isEmpty ? "none" : values.joined(separator: ", ")
    }

    private static func writeStderr(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    private static let rootUsage = """
    Usage: cedar <subcommand> [options]

    Subcommands:
      authorize   Evaluate authorization for one request
      validate    Validate policies, entities, or a request against a schema
      format      Canonically format Cedar policy text
      evaluate    Evaluate a single Cedar expression
    """

    private static let authorizeUsage = "Usage: cedar authorize --policies <file> --entities <file> --request <file>"
    private static let validateUsage = "Usage: cedar validate --schema <file> [--policies <file>] [--entities <file>] [--request <file>] [--mode strict|permissive] [--level <n>]"
    private static let formatUsage = "Usage: cedar format [--in-place] <file> [file ...]"
    private static let evaluateUsage = "Usage: cedar evaluate (--expression <expr> | --file <file>) --request <file> [--entities <file>]"
}