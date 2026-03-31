import CedarSpecSwift
import Dispatch
import Foundation

@main
enum BenchmarksMain {
    static func main() {
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data(("Benchmark failed: \(error)\n").utf8))
            Foundation.exit(1)
        }
    }

    static func run(_ arguments: [String]) throws {
        let limit = benchmarkLimit(arguments)
        let corpusDir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CEDAR_CORPUS_DIR"] ?? defaultCorpusDir)
        let validationDir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CEDAR_VALIDATION_DIR"] ?? defaultValidationDir)
        let jsonSchemaDir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CEDAR_JSON_SCHEMA_DIR"] ?? defaultJSONSchemaDir)

        guard FileManager.default.fileExists(atPath: corpusDir.path) else {
            throw BenchmarkError("Corpus directory not found at \(corpusDir.path)")
        }

        let parsing = try benchmarkParsing(corpusDir: corpusDir, limit: limit)
        let authorization = try benchmarkAuthorization(corpusDir: corpusDir, limit: limit)

        print("Benchmark limit: \(limit.map(String.init) ?? "all")")
        print("parsing: \(parsing.cases) policies in \(formatNanos(parsing.duration))")
        print("authorization: \(authorization.requests) requests across \(authorization.cases) manifests in \(formatNanos(authorization.duration))")

        if FileManager.default.fileExists(atPath: validationDir.path) {
            let validation = try benchmarkValidation(
                corpusDir: corpusDir,
                validationDir: validationDir,
                jsonSchemaDir: jsonSchemaDir,
                limit: limit
            )
            print("validation: \(validation.requests) request validations across \(validation.cases) manifests in \(formatNanos(validation.duration))")
        } else {
            print("validation: skipped (validation corpus not found at \(validationDir.path))")
        }
    }

    private static func benchmarkLimit(_ arguments: [String]) -> Int? {
        if let raw = ProcessInfo.processInfo.environment["CEDAR_BENCH_LIMIT"] {
            return raw.lowercased() == "all" ? nil : Int(raw)
        }

        var index = 0
        while index < arguments.count {
            if arguments[index] == "--limit", index + 1 < arguments.count {
                let raw = arguments[index + 1]
                return raw.lowercased() == "all" ? nil : Int(raw)
            }
            index += 1
        }

        return 100
    }

    private static func benchmarkParsing(corpusDir: URL, limit: Int?) throws -> BenchmarkResult {
        let cedarFiles = try FileManager.default.contentsOfDirectory(at: corpusDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "cedar" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let selected = limit.map { Array(cedarFiles.prefix($0)) } ?? cedarFiles

        let start = DispatchTime.now().uptimeNanoseconds
        for url in selected {
            let text = try String(contentsOf: url, encoding: .utf8)
            _ = try unwrapLoad(loadPoliciesCedar(text, source: url.lastPathComponent))
        }
        let end = DispatchTime.now().uptimeNanoseconds

        return BenchmarkResult(cases: selected.count, requests: 0, duration: end - start)
    }

    private static func benchmarkAuthorization(corpusDir: URL, limit: Int?) throws -> BenchmarkResult {
        let manifestURLs = try manifestURLs(in: corpusDir, limit: limit)
        var requestCount = 0
        let start = DispatchTime.now().uptimeNanoseconds

        for manifestURL in manifestURLs {
            let hash = manifestURL.deletingPathExtension().lastPathComponent
            let manifest = try loadJSONObject(at: manifestURL)
            guard let requests = manifest["requests"] as? [[String: Any]] else {
                throw BenchmarkError("Invalid manifest at \(manifestURL.path)")
            }

            let policiesText = try String(contentsOf: corpusDir.appendingPathComponent("\(hash).cedar"), encoding: .utf8)
            let loadedPolicies = try unwrapLoad(loadPoliciesCedar(policiesText, source: "\(hash).cedar", compiling: true))
            let entities = try loadCorpusEntities(corpusDir: corpusDir, hash: hash)

            for requestObject in requests {
                let request = try makeRequest(from: requestObject)
                if let compiledPolicies = loadedPolicies.compiledPolicies {
                    _ = isAuthorizedCompiled(request: request, entities: entities, compiledPolicies: compiledPolicies)
                } else {
                    _ = isAuthorized(request: request, entities: entities, policies: loadedPolicies.policies)
                }
                requestCount += 1
            }
        }

        let end = DispatchTime.now().uptimeNanoseconds
        return BenchmarkResult(cases: manifestURLs.count, requests: requestCount, duration: end - start)
    }

    private static func benchmarkValidation(
        corpusDir: URL,
        validationDir: URL,
        jsonSchemaDir: URL,
        limit: Int?
    ) throws -> BenchmarkResult {
        let validationURLs = try FileManager.default.contentsOfDirectory(at: validationDir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".validation.json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let selected = limit.map { Array(validationURLs.prefix($0)) } ?? validationURLs

        var requestCount = 0
        let start = DispatchTime.now().uptimeNanoseconds

        for validationURL in selected {
            let hash = validationURL.lastPathComponent.replacingOccurrences(of: ".validation.json", with: "")
            let policiesText = try String(contentsOf: corpusDir.appendingPathComponent("\(hash).cedar"), encoding: .utf8)
            let policies = try unwrapLoad(loadPoliciesCedar(policiesText, source: "\(hash).cedar"))
            let schema = try loadBenchmarkSchema(hash: hash, corpusDir: corpusDir, jsonSchemaDir: jsonSchemaDir)
            let entities = try loadCorpusEntities(corpusDir: corpusDir, hash: hash)
            let manifest = try loadJSONObject(at: corpusDir.appendingPathComponent("\(hash).json"))
            guard let requests = manifest["requests"] as? [[String: Any]] else {
                throw BenchmarkError("Invalid manifest at \(hash).json")
            }

            _ = validatePolicies(policies, schema: schema, mode: .strict)
            _ = validateEntities(entities, schema: schema, mode: .strict)
            for requestObject in requests {
                let request = try makeRequest(from: requestObject)
                _ = validateRequest(request, schema: schema, mode: .strict)
                requestCount += 1
            }
        }

        let end = DispatchTime.now().uptimeNanoseconds
        return BenchmarkResult(cases: selected.count, requests: requestCount, duration: end - start)
    }

    private static func manifestURLs(in corpusDir: URL, limit: Int?) throws -> [URL] {
        let urls = try FileManager.default.contentsOfDirectory(at: corpusDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.contains(".entities.") && !$0.lastPathComponent.contains(".validation.") && !$0.lastPathComponent.contains(".cedarschema.") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return limit.map { Array(urls.prefix($0)) } ?? urls
    }

    private static func loadBenchmarkSchema(hash: String, corpusDir: URL, jsonSchemaDir: URL) throws -> Schema {
        let jsonSchemaURL = jsonSchemaDir.appendingPathComponent("\(hash).cedarschema.json")
        if FileManager.default.fileExists(atPath: jsonSchemaURL.path) {
            let text = try String(contentsOf: jsonSchemaURL, encoding: .utf8)
            switch loadSchemaJSON(text, source: jsonSchemaURL.lastPathComponent) {
            case let .success(schema, _):
                return schema
            case .failure:
                break
            }
        }

        let cedarSchemaURL = corpusDir.appendingPathComponent("\(hash).cedarschema")
        let text = try String(contentsOf: cedarSchemaURL, encoding: .utf8)
        return try unwrapLoad(loadSchemaCedar(text, source: cedarSchemaURL.lastPathComponent))
    }

    private static func loadCorpusEntities(corpusDir: URL, hash: String) throws -> Entities {
        let url = corpusDir.appendingPathComponent("\(hash).entities.json")
        let rawEntities = try loadJSONArray(at: url)
        let converted = try convertEntities(rawEntities)
        let data = try JSONSerialization.data(withJSONObject: converted)
        let text = String(decoding: data, as: UTF8.self)
        return try unwrapLoad(loadEntities(text, source: url.lastPathComponent))
    }

    private static func makeRequest(from object: [String: Any]) throws -> Request {
        guard let principalObject = object["principal"] as? [String: Any],
              let actionObject = object["action"] as? [String: Any],
              let resourceObject = object["resource"] as? [String: Any]
        else {
            throw BenchmarkError("Invalid request object")
        }

        return Request(
            principal: try makeEntityUID(principalObject),
            action: try makeEntityUID(actionObject),
            resource: try makeEntityUID(resourceObject),
            context: try makeContext(object["context"])
        )
    }

    private static func makeEntityUID(_ object: [String: Any]) throws -> EntityUID {
        guard let type = object["type"] as? String, let id = object["id"] as? String else {
            throw BenchmarkError("Invalid entity UID object")
        }
        return EntityUID(ty: parseName(type), eid: id)
    }

    private static func parseName(_ raw: String) -> Name {
        let parts = raw.components(separatedBy: "::")
        guard parts.count > 1 else {
            return Name(id: raw)
        }
        return Name(id: parts.last ?? raw, path: Array(parts.dropLast()))
    }

    private static func formatEntityUIDString(_ object: [String: Any]) -> String {
        let type = object["type"] as? String ?? ""
        let id = object["id"] as? String ?? ""
        let escapedID = id.replacingOccurrences(of: "\"", with: "\\\"")
        return "\(type)::\"\(escapedID)\""
    }

    private static func convertEntities(_ rawEntities: [[String: Any]]) throws -> [[String: Any]] {
        try rawEntities.map { entity in
            var converted: [String: Any] = [:]

            if let uidObject = entity["uid"] as? [String: Any] {
                converted["uid"] = formatEntityUIDString(uidObject)
            }

            if let parents = entity["parents"] as? [[String: Any]] {
                converted["parents"] = parents.map(formatEntityUIDString)
            } else {
                converted["parents"] = [String]()
            }

            converted["attrs"] = try convertValueMap(entity["attrs"] as? [String: Any] ?? [:])
            converted["tags"] = try convertValueMap(entity["tags"] as? [String: Any] ?? [:])
            return converted
        }
    }

    private static func convertValueMap(_ dictionary: [String: Any]) throws -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in dictionary {
            result[key] = try convertValue(value)
        }
        return result
    }

    private static func convertValue(_ value: Any) throws -> Any {
        if let dictionary = value as? [String: Any] {
            if let entityRef = dictionary["__entity"] as? [String: Any] {
                return [
                    "type": "entity",
                    "value": formatEntityUIDString(entityRef),
                ]
            }
            if let extRef = dictionary["__extn"] as? [String: Any] {
                return [
                    "type": "call",
                    "function": extRef["fn"] as? String ?? "",
                    "args": [extRef["arg"] as? String ?? ""],
                ]
            }
            return try convertValueMap(dictionary)
        }

        if let array = value as? [Any] {
            return try array.map(convertValue)
        }

        return value
    }

    private static func makeContext(_ raw: Any?) throws -> RestrictedExpr {
        guard let dictionary = raw as? [String: Any], !dictionary.isEmpty else {
            return .emptyRecord
        }
        return try buildRestrictedExpr(try convertValueMap(dictionary))
    }

    private static func buildRestrictedExpr(_ value: Any) throws -> RestrictedExpr {
        if let boolean = value as? Bool {
            return .bool(boolean)
        }
        if let intValue = value as? Int64 {
            return .int(intValue)
        }
        if let intValue = value as? Int {
            return .int(Int64(intValue))
        }
        if let stringValue = value as? String {
            return .string(stringValue)
        }
        if let array = value as? [Any] {
            return .set(CedarSet.make(try array.map(buildRestrictedExpr)))
        }
        if let dictionary = value as? [String: Any] {
            if dictionary["type"] as? String == "entity", let rawUID = dictionary["value"] as? String {
                return .entityUID(try parseEntityUID(rawUID))
            }
            if dictionary["type"] as? String == "call",
               let functionName = dictionary["function"] as? String,
               let arguments = dictionary["args"] as? [Any],
               let function = extFunction(named: functionName) {
                return .call(function, try arguments.map(buildRestrictedExpr))
            }
            return .record(CedarMap.make(try dictionary.map { key, value in
                (key: key, value: try buildRestrictedExpr(value))
            }))
        }

        throw BenchmarkError("Unsupported context value: \(value)")
    }

    private static func parseEntityUID(_ raw: String) throws -> EntityUID {
        guard let range = raw.range(of: "::\"", options: .backwards), raw.hasSuffix("\"") else {
            throw BenchmarkError("Invalid entity UID string: \(raw)")
        }
        let typePart = String(raw[..<range.lowerBound])
        let idPart = String(raw[range.upperBound..<raw.index(before: raw.endIndex)]).replacingOccurrences(of: "\\\"", with: "\"")
        return EntityUID(ty: parseName(typePart), eid: idPart)
    }

    private static func extFunction(named name: String) -> ExtFun? {
        switch name {
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

    private static func loadJSONObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BenchmarkError("Invalid JSON object at \(url.path)")
        }
        return value
    }

    private static func loadJSONArray(at url: URL) throws -> [[String: Any]] {
        let data = try Data(contentsOf: url)
        guard let value = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw BenchmarkError("Invalid JSON array at \(url.path)")
        }
        return value
    }

    private static func unwrapLoad<T>(_ result: LoadResult<T>) throws -> T {
        switch result {
        case let .success(value, diagnostics):
            guard !diagnostics.hasErrors else {
                throw BenchmarkError(diagnostics.elements.map(\.message).joined(separator: "; "))
            }
            return value
        case let .failure(diagnostics):
            throw BenchmarkError(diagnostics.elements.map(\.message).joined(separator: "; "))
        }
    }

    private static func formatNanos(_ nanos: UInt64) -> String {
        String(format: "%.2f ms", Double(nanos) / 1_000_000.0)
    }

    private static let defaultCorpusDir = "/Users/navan.chauhan/Developer/navanchauhan/swift-cedar/.ai/corpus-tests"
    private static let defaultValidationDir = "/Users/navan.chauhan/Developer/navanchauhan/swift-cedar/.ai/corpus-tests-validation"
    private static let defaultJSONSchemaDir = "/Users/navan.chauhan/Developer/navanchauhan/swift-cedar/.ai/corpus-tests-json-schemas"
}

private struct BenchmarkResult {
    let cases: Int
    let requests: Int
    let duration: UInt64
}

private struct BenchmarkError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
