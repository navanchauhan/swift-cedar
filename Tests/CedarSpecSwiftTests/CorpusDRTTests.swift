import XCTest
import Foundation
@testable import CedarSpecSwift

final class CorpusDRTTests: XCTestCase {

    // MARK: - Configuration

    private static let testLimit: Int? = {
        if let envLimit = ProcessInfo.processInfo.environment["CEDAR_CORPUS_LIMIT"] {
            if envLimit.lowercased() == "all" { return nil }
            return Int(envLimit)
        }
        return 100
    }()

    private static let corpusDir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CEDAR_CORPUS_DIR"]
        ?? "/Users/navan.chauhan/Developer/navanchauhan/swift-cedar/.ai/corpus-tests")

    private static let skipHashes: Set<String> = []

    // MARK: - Test Entry Point

    func testCorpusDRT() throws {
        let fm = FileManager.default
        let corpusURL = Self.corpusDir

        guard fm.fileExists(atPath: corpusURL.path) else {
            XCTFail("Corpus directory not found at \(corpusURL.path)")
            return
        }

        let allFiles = try fm.contentsOfDirectory(atPath: corpusURL.path)
        var manifestNames = allFiles.filter { $0.hasSuffix(".json") && !$0.contains(".entities.") }
                                    .sorted()

        if let limit = Self.testLimit {
            manifestNames = Array(manifestNames.prefix(limit))
        }

        var passed = 0
        var failed = 0
        var parseErrors = 0
        var skipped = 0
        var failures: [(String, String)] = []

        for manifestName in manifestNames {
            let hash = String(manifestName.dropLast(5))

            if Self.skipHashes.contains(hash) {
                skipped += 1
                continue
            }

            let manifestPath = corpusURL.appendingPathComponent(manifestName).path
            let cedarPath = corpusURL.appendingPathComponent("\(hash).cedar").path
            let entitiesPath = corpusURL.appendingPathComponent("\(hash).entities.json").path

            do {
                let result = try runSingleTest(manifestPath: manifestPath, cedarPath: cedarPath, entitiesPath: entitiesPath, hash: hash)
                switch result {
                case .passed:
                    passed += 1
                case let .failed(detail):
                    failed += 1
                    failures.append((hash, detail))
                }
            } catch {
                parseErrors += 1
                if parseErrors <= 20 {
                    failures.append((hash, "PARSE ERROR: \(error)"))
                }
            }
        }

        let total = passed + failed + parseErrors
        print("")
        print("=== Corpus DRT Summary ===")
        print("Total:        \(total)")
        print("Passed:       \(passed)")
        print("Failed:       \(failed)")
        print("Parse Errors: \(parseErrors)")
        print("Skipped:      \(skipped) (known library crashes)")
        print("Load time:    \(String(format: "%.3f", Self.totalLoadTime))s")
        print("Auth time:    \(String(format: "%.3f", Self.totalAuthTime))s")
        print("")

        if !failures.isEmpty {
            print("--- First \(min(failures.count, 30)) failures ---")
            for (hash, detail) in failures.prefix(30) {
                print("  [\(hash)] \(detail)")
            }
            print("")
        }

        if failed > 0 {
            XCTFail("\(failed) decision mismatch(es) out of \(total) corpus tests")
        }
    }

    // MARK: - Single Test Runner

    private enum TestResult {
        case passed
        case failed(String)
    }

    private struct DecodedRequest {
        let index: Int
        let request: Request
        let expected: Decision
    }

    private struct ParseError: Error, CustomStringConvertible {
        let description: String
    }

    nonisolated(unsafe) private static var totalAuthTime: Double = 0
    nonisolated(unsafe) private static var totalLoadTime: Double = 0

    private func runSingleTest(manifestPath: String, cedarPath: String, entitiesPath: String, hash: String) throws -> TestResult {
        let loadStart = CFAbsoluteTimeGetCurrent()
        // Parse manifest with our JSON parser (single parse, no Foundation JSONSerialization)
        let manifestText = try String(contentsOfFile: manifestPath, encoding: .utf8)
        var manifestParser = JSONParser(source: manifestText, sourceName: hash + ".json", maxDepth: 256)
        let manifestJSON: JSONValue
        switch manifestParser.parse() {
        case let .success(value):
            manifestJSON = value
        case let .failure(diag):
            throw ParseError(description: "Manifest parse failed: \(diag.message)")
        }

        guard case let .object(manifestEntries, _) = manifestJSON else {
            throw ParseError(description: "Manifest must be a JSON object")
        }

        guard let requestsField = findJSONField(manifestEntries, "requests"),
              case let .array(requestValues, _) = requestsField.value else {
            throw ParseError(description: "Manifest missing requests array")
        }

        // Parse Cedar policies (single parse)
        let cedarText = try String(contentsOfFile: cedarPath, encoding: .utf8)
        let loadedPolicies: LoadedPolicies
        switch loadPoliciesCedar(cedarText, source: hash + ".cedar", compiling: true) {
        case let .success(p, _):
            loadedPolicies = p
        case let .failure(diags):
            throw ParseError(description: "Policy parse failed: \(diags.elements.first?.message ?? "unknown")")
        }

        // Load entities (single parse through our JSON parser)
        let entitiesText = try String(contentsOfFile: entitiesPath, encoding: .utf8)
        let entities: Entities
        switch loadEntities(entitiesText, source: hash + ".entities.json") {
        case let .success(e, _):
            entities = e
        case let .failure(diags):
            throw ParseError(description: "Entity parse failed: \(diags.elements.first?.message ?? "unknown")")
        }

        var decodedRequests: [DecodedRequest] = []
        decodedRequests.reserveCapacity(requestValues.count)

        for (idx, reqValue) in requestValues.enumerated() {
            guard case let .object(reqEntries, _) = reqValue else {
                throw ParseError(description: "Request #\(idx) must be an object")
            }

            let principal = try extractEntityUID(reqEntries, field: "principal", idx: idx)
            let action = try extractEntityUID(reqEntries, field: "action", idx: idx)
            let resource = try extractEntityUID(reqEntries, field: "resource", idx: idx)
            let context = extractContext(reqEntries)

            guard let decisionField = findJSONField(reqEntries, "decision"),
                  case let .string(decisionStr, _) = decisionField.value else {
                throw ParseError(description: "Request #\(idx) missing decision")
            }

            let request = Request(principal: principal, action: action, resource: resource, context: context)
            let expected: Decision = decisionStr == "allow" ? .allow : .deny
            decodedRequests.append(DecodedRequest(index: idx, request: request, expected: expected))
        }

        Self.totalLoadTime += CFAbsoluteTimeGetCurrent() - loadStart

        let authStart = CFAbsoluteTimeGetCurrent()
        for decoded in decodedRequests {
            let response: Response
            if let compiledPolicies = loadedPolicies.compiledPolicies {
                response = isAuthorizedCompiled(request: decoded.request, entities: entities, compiledPolicies: compiledPolicies)
            } else {
                response = isAuthorized(request: decoded.request, entities: entities, policies: loadedPolicies.policies)
            }

            if response.decision != decoded.expected {
                return .failed("Request #\(decoded.index): expected \(decoded.expected == .allow ? "allow" : "deny"), got \(response.decision == .allow ? "allow" : "deny")")
            }
        }

        Self.totalAuthTime += CFAbsoluteTimeGetCurrent() - authStart
        return .passed
    }

    // MARK: - JSONValue helpers

    private func extractEntityUID(_ entries: [JSONObjectEntry], field: String, idx: Int) throws -> EntityUID {
        guard let f = findJSONField(entries, field) else {
            throw ParseError(description: "Request #\(idx) missing \(field)")
        }
        guard case let .object(uidEntries, _) = f.value else {
            throw ParseError(description: "Request #\(idx) \(field) must be an object")
        }
        guard let typeField = findJSONField(uidEntries, "type"),
              case let .string(typeName, _) = typeField.value,
              let idField = findJSONField(uidEntries, "id"),
              case let .string(eid, _) = idField.value else {
            throw ParseError(description: "Request #\(idx) \(field) missing type/id")
        }
        return EntityUID(ty: parseName(typeName), eid: eid)
    }

    private func extractContext(_ entries: [JSONObjectEntry]) -> RestrictedExpr {
        guard let contextField = findJSONField(entries, "context"),
              case let .object(contextEntries, _) = contextField.value,
              !contextEntries.isEmpty else {
            return .emptyRecord
        }
        // Build RestrictedExpr directly from JSONValue
        return jsonValueToRestrictedExpr(contextField.value)
    }

    private func jsonValueToRestrictedExpr(_ value: JSONValue) -> RestrictedExpr {
        switch value {
        case let .bool(b, _):
            return .bool(b)
        case let .number(numStr, _):
            if let i = Int64(numStr) {
                return .int(i)
            }
            if let d = Double(numStr), d == Double(Int64(d)), !d.isNaN, !d.isInfinite {
                return .int(Int64(d))
            }
            return .string(numStr) // fallback
        case let .string(s, _):
            return .string(s)
        case let .array(elements, _):
            return .set(CedarSet.make(elements.map { jsonValueToRestrictedExpr($0) }))
        case let .object(entries, _):
            // __entity
            if let entityRef = findJSONField(entries, "__entity"),
               case let .object(entityEntries, _) = entityRef.value,
               let typeField = findJSONField(entityEntries, "type"),
               case let .string(typeName, _) = typeField.value,
               let idField = findJSONField(entityEntries, "id"),
               case let .string(eid, _) = idField.value {
                return .entityUID(EntityUID(ty: parseName(typeName), eid: eid))
            }
            // __extn
            if let extnRef = findJSONField(entries, "__extn"),
               case let .object(extnEntries, _) = extnRef.value,
               let fnField = findJSONField(extnEntries, "fn"),
               case let .string(fn, _) = fnField.value,
               let argField = findJSONField(extnEntries, "arg"),
               case let .string(arg, _) = argField.value,
               let extFun = parseExtFun(fn) {
                return .call(extFun, [.string(arg)])
            }
            // Regular record
            return .record(CedarMap.make(entries.map { (key: $0.key, value: jsonValueToRestrictedExpr($0.value)) }))
        case .null:
            return .emptyRecord
        }
    }

    private func parseName(_ raw: String) -> Name {
        let components = raw.components(separatedBy: "::")
        guard components.count > 1 else {
            return Name(id: raw)
        }
        return Name(id: components.last!, path: Array(components.dropLast()))
    }
}
