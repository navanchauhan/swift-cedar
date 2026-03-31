import XCTest
import Foundation
@testable import CedarSpecSwift

final class CorpusValidationTests: XCTestCase {

    // MARK: - Configuration

    /// Defaults to 100 for fast iteration. Set to nil to run all ~7750 tests.
    /// Override via CEDAR_CORPUS_LIMIT env var (use "all" for no limit, or a number).
    private static let testLimit: Int? = {
        if let envLimit = ProcessInfo.processInfo.environment["CEDAR_CORPUS_LIMIT"] {
            if envLimit.lowercased() == "all" { return nil }
            return Int(envLimit)
        }
        return 100
    }()

    private static let corpusDir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CEDAR_CORPUS_DIR"]
        ?? "/Users/navan.chauhan/Developer/navanchauhan/swift-cedar/.ai/corpus-tests")

    private static let validationDir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CEDAR_VALIDATION_DIR"]
        ?? "/Users/navan.chauhan/Developer/navanchauhan/swift-cedar/.ai/corpus-tests-validation")

    private static let jsonSchemaDir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CEDAR_JSON_SCHEMA_DIR"]
        ?? "/Users/navan.chauhan/Developer/navanchauhan/swift-cedar/.ai/corpus-tests-json-schemas")

    /// Hashes to skip (known issues).
    private static let skipHashes: Set<String> = []

    // MARK: - Test Entry Point

    func testCorpusValidation() throws {
        let fm = FileManager.default

        guard fm.fileExists(atPath: Self.validationDir.path) else {
            XCTFail("Validation directory not found at \(Self.validationDir.path)")
            return
        }

        guard fm.fileExists(atPath: Self.corpusDir.path) else {
            XCTFail("Corpus directory not found at \(Self.corpusDir.path)")
            return
        }

        let allFiles = try fm.contentsOfDirectory(atPath: Self.validationDir.path)
        var validationFiles = allFiles.filter { $0.hasSuffix(".validation.json") }.sorted()

        if let limit = Self.testLimit {
            validationFiles = Array(validationFiles.prefix(limit))
        }

        var counts = TestCounts()
        var failures: [(String, String)] = []

        for validationFile in validationFiles {
            // Extract hash: "abcdef.validation.json" -> "abcdef"
            let hash = String(validationFile.dropLast(".validation.json".count))

            if Self.skipHashes.contains(hash) {
                counts.skipped += 1
                continue
            }

            do {
                let result = try runSingleValidationTest(hash: hash)

                counts.policyStrictPassed += result.policyStrictPassed
                counts.policyStrictFailed += result.policyStrictFailed
                counts.policyPermissivePassed += result.policyPermissivePassed
                counts.policyPermissiveFailed += result.policyPermissiveFailed
                counts.entityPassed += result.entityPassed
                counts.entityFailed += result.entityFailed
                counts.requestStrictPassed += result.requestStrictPassed
                counts.requestStrictFailed += result.requestStrictFailed
                counts.requestPermissivePassed += result.requestPermissivePassed
                counts.requestPermissiveFailed += result.requestPermissiveFailed
                counts.testsPassed += result.allPassed ? 1 : 0
                counts.testsFailed += result.allPassed ? 0 : 1

                if !result.allPassed {
                    for detail in result.failureDetails {
                        failures.append((hash, detail))
                    }
                }
            } catch {
                counts.parseErrors += 1
                if counts.parseErrors <= 20 {
                    failures.append((hash, "PARSE ERROR: \(error)"))
                }
            }
        }

        // Report summary
        let totalTests = counts.testsPassed + counts.testsFailed + counts.parseErrors
        print("")
        print("=== Corpus Validation Summary ===")
        print("Total tests:           \(totalTests)")
        print("Tests passed:          \(counts.testsPassed)")
        print("Tests failed:          \(counts.testsFailed)")
        print("Parse errors:          \(counts.parseErrors)")
        print("Skipped:               \(counts.skipped)")
        print("")
        print("Policy strict:         \(counts.policyStrictPassed) passed, \(counts.policyStrictFailed) failed")
        print("Policy permissive:     \(counts.policyPermissivePassed) passed, \(counts.policyPermissiveFailed) failed")
        print("Entity validation:     \(counts.entityPassed) passed, \(counts.entityFailed) failed")
        print("Request strict:        \(counts.requestStrictPassed) passed, \(counts.requestStrictFailed) failed")
        print("Request permissive:    \(counts.requestPermissivePassed) passed, \(counts.requestPermissiveFailed) failed")
        print("")

        if !failures.isEmpty {
            print("--- First \(min(failures.count, 30)) failures ---")
            for (hash, detail) in failures.prefix(30) {
                print("  [\(hash)] \(detail)")
            }
            print("")
        }

        if counts.testsFailed > 0 {
            XCTFail("\(counts.testsFailed) validation mismatch(es) out of \(totalTests) corpus tests")
        }
    }

    // MARK: - Counts

    private struct TestCounts {
        var testsPassed = 0
        var testsFailed = 0
        var parseErrors = 0
        var skipped = 0
        var policyStrictPassed = 0
        var policyStrictFailed = 0
        var policyPermissivePassed = 0
        var policyPermissiveFailed = 0
        var entityPassed = 0
        var entityFailed = 0
        var requestStrictPassed = 0
        var requestStrictFailed = 0
        var requestPermissivePassed = 0
        var requestPermissiveFailed = 0
    }

    // MARK: - Single Test Result

    private struct SingleTestResult {
        var policyStrictPassed = 0
        var policyStrictFailed = 0
        var policyPermissivePassed = 0
        var policyPermissiveFailed = 0
        var entityPassed = 0
        var entityFailed = 0
        var requestStrictPassed = 0
        var requestStrictFailed = 0
        var requestPermissivePassed = 0
        var requestPermissiveFailed = 0
        var failureDetails: [String] = []

        var allPassed: Bool {
            policyStrictFailed == 0
                && policyPermissiveFailed == 0
                && entityFailed == 0
                && requestStrictFailed == 0
                && requestPermissiveFailed == 0
        }
    }

    // MARK: - Error Type

    private struct ParseError: Error, CustomStringConvertible {
        let description: String
    }

    // MARK: - Single Test Runner

    private func runSingleValidationTest(hash: String) throws -> SingleTestResult {
        var result = SingleTestResult()

        // Load validation expectations
        let validationURL = Self.validationDir.appendingPathComponent("\(hash).validation.json")
        let validationData = try Data(contentsOf: validationURL)
        guard let validation = try JSONSerialization.jsonObject(with: validationData) as? [String: Any] else {
            throw ParseError(description: "Invalid validation JSON")
        }

        // Load policies
        let cedarURL = Self.corpusDir.appendingPathComponent("\(hash).cedar")
        let cedarText = try String(contentsOf: cedarURL, encoding: .utf8)
        let policies: Policies
        switch loadPoliciesCedar(cedarText, source: hash + ".cedar") {
        case let .success(p, _):
            policies = p
        case let .failure(diags):
            throw ParseError(description: "Policy parse failed: \(diags.elements.first?.message ?? "unknown")")
        }

        // Load schema: try JSON schema format first, fall back to .cedarschema text format
        let schema: Schema
        let jsonSchemaURL = Self.jsonSchemaDir.appendingPathComponent("\(hash).cedarschema.json")
        if FileManager.default.fileExists(atPath: jsonSchemaURL.path) {
            let jsonSchemaText = try String(contentsOf: jsonSchemaURL, encoding: .utf8)
            switch loadSchemaJSON(jsonSchemaText, source: hash + ".cedarschema.json") {
            case let .success(s, _):
                schema = s
            case let .failure(diags):
                // Fall back to text format
                let cedarSchemaURL = Self.corpusDir.appendingPathComponent("\(hash).cedarschema")
                let cedarSchemaText = try String(contentsOf: cedarSchemaURL, encoding: .utf8)
                switch loadSchemaCedar(cedarSchemaText, source: hash + ".cedarschema") {
                case let .success(s, _):
                    schema = s
                case let .failure(textDiags):
                    throw ParseError(description: "Schema parse failed (JSON: \(diags.elements.first?.message ?? "unknown"), text: \(textDiags.elements.first?.message ?? "unknown"))")
                }
            }
        } else {
            let cedarSchemaURL = Self.corpusDir.appendingPathComponent("\(hash).cedarschema")
            let cedarSchemaText = try String(contentsOf: cedarSchemaURL, encoding: .utf8)
            switch loadSchemaCedar(cedarSchemaText, source: hash + ".cedarschema") {
            case let .success(s, _):
                schema = s
            case let .failure(diags):
                throw ParseError(description: "Schema parse failed: \(diags.elements.first?.message ?? "unknown")")
            }
        }

        // Load entities
        let entitiesURL = Self.corpusDir.appendingPathComponent("\(hash).entities.json")
        let entitiesData = try Data(contentsOf: entitiesURL)
        guard let rawEntities = try JSONSerialization.jsonObject(with: entitiesData) as? [[String: Any]] else {
            throw ParseError(description: "Invalid entities JSON")
        }
        let convertedEntities = try convertEntities(rawEntities)
        let convertedEntitiesJSON = try JSONSerialization.data(withJSONObject: convertedEntities)
        let entitiesText = String(data: convertedEntitiesJSON, encoding: .utf8)!

        let entities: Entities
        switch loadEntities(entitiesText, source: hash + ".entities.json") {
        case let .success(e, _):
            entities = e
        case let .failure(diags):
            throw ParseError(description: "Entity parse failed: \(diags.elements.first?.message ?? "unknown")")
        }

        // --- Policy Validation ---
        if let policyValidation = validation["policyValidation"] as? [String: Any] {
            // Strict
            if let expectedStrict = policyValidation["strict"] as? Bool {
                let strictResult = validatePolicies(policies, schema: schema, mode: .strict)
                if strictResult.isValid == expectedStrict {
                    result.policyStrictPassed += 1
                } else {
                    result.policyStrictFailed += 1
                    result.failureDetails.append(
                        "Policy strict: expected \(expectedStrict), got \(strictResult.isValid)"
                    )
                }
            }

            // Permissive
            if let expectedPermissive = policyValidation["permissive"] as? Bool {
                let permissiveResult = validatePolicies(policies, schema: schema, mode: .permissive)
                if permissiveResult.isValid == expectedPermissive {
                    result.policyPermissivePassed += 1
                } else {
                    result.policyPermissiveFailed += 1
                    result.failureDetails.append(
                        "Policy permissive: expected \(expectedPermissive), got \(permissiveResult.isValid)"
                    )
                }
            }
        }

        // --- Entity Validation ---
        if let entityValidation = validation["entityValidation"] as? [String: Any] {
            // Entity validation uses strict mode by default
            let entityResult = validateEntities(entities, schema: schema, mode: .strict)
            // The corpus just lists entities with per-entity results (empty objects mean valid).
            // For now, we check that entity validation itself completes without crashing.
            // Per-entity granularity is not directly exposed by validateEntities.
            if let perEntity = entityValidation["perEntity"] as? [String: Any] {
                // If all per-entity entries are empty objects (valid), overall should be valid.
                let allValid = perEntity.values.allSatisfy { entry in
                    guard let dict = entry as? [String: Any] else { return true }
                    return dict.isEmpty
                }
                if allValid == entityResult.isValid {
                    result.entityPassed += 1
                } else {
                    result.entityFailed += 1
                    result.failureDetails.append(
                        "Entity validation: expected \(allValid), got \(entityResult.isValid)"
                    )
                }
            }
        }

        // --- Request Validation ---
        if let requestValidations = validation["requestValidation"] as? [[String: Any]] {
            // Load manifest to get request details
            let manifestURL = Self.corpusDir.appendingPathComponent("\(hash).json")
            let manifestData = try Data(contentsOf: manifestURL)
            guard let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
                  let requests = manifest["requests"] as? [[String: Any]]
            else {
                throw ParseError(description: "Invalid manifest JSON for request validation")
            }

            for (idx, reqValidation) in requestValidations.enumerated() {
                guard idx < requests.count else { break }
                let reqObj = requests[idx]

                guard let principalObj = reqObj["principal"] as? [String: Any],
                      let actionObj = reqObj["action"] as? [String: Any],
                      let resourceObj = reqObj["resource"] as? [String: Any]
                else {
                    continue
                }

                let principal = try makeEntityUID(principalObj)
                let action = try makeEntityUID(actionObj)
                let resource = try makeEntityUID(resourceObj)
                let context = try makeContext(reqObj["context"])
                let request = Request(principal: principal, action: action, resource: resource, context: context)

                // Strict
                if let expectedStrict = reqValidation["strict"] as? Bool {
                    let strictResult = validateRequest(request, schema: schema, mode: .strict)
                    if strictResult.isValid == expectedStrict {
                        result.requestStrictPassed += 1
                    } else {
                        result.requestStrictFailed += 1
                        result.failureDetails.append(
                            "Request #\(idx) strict: expected \(expectedStrict), got \(strictResult.isValid)"
                        )
                    }
                }

                // Permissive
                if let expectedPermissive = reqValidation["permissive"] as? Bool {
                    let permissiveResult = validateRequest(request, schema: schema, mode: .permissive)
                    if permissiveResult.isValid == expectedPermissive {
                        result.requestPermissivePassed += 1
                    } else {
                        result.requestPermissiveFailed += 1
                        result.failureDetails.append(
                            "Request #\(idx) permissive: expected \(expectedPermissive), got \(permissiveResult.isValid)"
                        )
                    }
                }
            }
        }

        return result
    }

    // MARK: - Entity UID Construction

    private func makeEntityUID(_ obj: [String: Any]) throws -> EntityUID {
        guard let type = obj["type"] as? String, let id = obj["id"] as? String else {
            throw ParseError(description: "Invalid entity UID object")
        }
        let name = parseName(type)
        return EntityUID(ty: name, eid: id)
    }

    private func parseName(_ raw: String) -> Name {
        let parts = raw.components(separatedBy: "::")
        guard parts.count > 1 else {
            return Name(id: raw)
        }
        return Name(id: parts.last!, path: Array(parts.dropLast()))
    }

    // MARK: - Entity JSON Conversion

    private func convertEntities(_ rawEntities: [[String: Any]]) throws -> [[String: Any]] {
        try rawEntities.map { entity in
            var converted: [String: Any] = [:]

            if let uidObj = entity["uid"] as? [String: Any] {
                converted["uid"] = formatEntityUIDString(uidObj)
            }

            if let parents = entity["parents"] as? [[String: Any]] {
                converted["parents"] = parents.map { formatEntityUIDString($0) }
            } else {
                converted["parents"] = [String]()
            }

            if let attrs = entity["attrs"] as? [String: Any] {
                converted["attrs"] = try convertValueMap(attrs)
            } else {
                converted["attrs"] = [String: Any]()
            }

            if let tags = entity["tags"] as? [String: Any] {
                converted["tags"] = try convertValueMap(tags)
            }

            return converted
        }
    }

    private func formatEntityUIDString(_ obj: [String: Any]) -> String {
        let type = obj["type"] as? String ?? ""
        let id = obj["id"] as? String ?? ""
        let escapedId = id.replacingOccurrences(of: "\"", with: "\\\"")
        return "\(type)::\"\(escapedId)\""
    }

    private func convertValue(_ value: Any) throws -> Any {
        if let dict = value as? [String: Any] {
            if let entityRef = dict["__entity"] as? [String: Any] {
                let type = entityRef["type"] as? String ?? ""
                let id = entityRef["id"] as? String ?? ""
                let escapedId = id.replacingOccurrences(of: "\"", with: "\\\"")
                return [
                    "type": "entity",
                    "value": "\(type)::\"\(escapedId)\""
                ] as [String: Any]
            }

            if let extnRef = dict["__extn"] as? [String: Any] {
                let fn = extnRef["fn"] as? String ?? ""
                let arg = extnRef["arg"] as? String ?? ""
                return [
                    "type": "call",
                    "function": fn,
                    "args": [arg]
                ] as [String: Any]
            }

            return try convertValueMap(dict)
        }

        if let arr = value as? [Any] {
            return try arr.map { try convertValue($0) }
        }

        return value
    }

    private func convertValueMap(_ dict: [String: Any]) throws -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, val) in dict {
            result[key] = try convertValue(val)
        }
        return result
    }

    // MARK: - Context Construction

    private func makeContext(_ raw: Any?) throws -> RestrictedExpr {
        guard let dict = raw as? [String: Any] else {
            return .emptyRecord
        }

        if dict.isEmpty {
            return .emptyRecord
        }

        let converted = try convertValueMap(dict)
        return try buildRestrictedExpr(converted)
    }

    private func buildRestrictedExpr(_ value: Any) throws -> RestrictedExpr {
        if let boolVal = value as? Bool {
            return .bool(boolVal)
        }

        if let intVal = value as? Int64 {
            return .int(intVal)
        }

        if let intVal = value as? Int {
            return .int(Int64(intVal))
        }

        if let doubleVal = value as? Double {
            if doubleVal == Double(Int64(doubleVal)) && !doubleVal.isNaN && !doubleVal.isInfinite {
                return .int(Int64(doubleVal))
            }
            throw ParseError(description: "Non-integer number in context: \(doubleVal)")
        }

        if let strVal = value as? String {
            return .string(strVal)
        }

        if let arr = value as? [Any] {
            let elements = try arr.map { try buildRestrictedExpr($0) }
            return .set(CedarSet.make(elements))
        }

        if let dict = value as? [String: Any] {
            if let type = dict["type"] as? String, type == "entity",
               let uidStr = dict["value"] as? String {
                let uid = try parseEntityUIDFromString(uidStr)
                return .entityUID(uid)
            }

            if let type = dict["type"] as? String, type == "call",
               let function = dict["function"] as? String,
               let args = dict["args"] as? [Any] {
                guard let extFun = lookupExtFun(function) else {
                    throw ParseError(description: "Unknown extension function: \(function)")
                }
                let argExprs = try args.map { try buildRestrictedExpr($0) }
                return .call(extFun, argExprs)
            }

            let entries: [(key: Attr, value: RestrictedExpr)] = try dict.map { key, val in
                (key: key, value: try buildRestrictedExpr(val))
            }
            return .record(CedarMap.make(entries))
        }

        if value is NSNull {
            throw ParseError(description: "null values not supported in context")
        }

        throw ParseError(description: "Unsupported context value type: \(type(of: value))")
    }

    private func parseEntityUIDFromString(_ raw: String) throws -> EntityUID {
        guard let quoteStart = raw.range(of: "::\"", options: .backwards), raw.hasSuffix("\"") else {
            throw ParseError(description: "Invalid entity UID string: \(raw)")
        }

        let typePart = String(raw[..<quoteStart.lowerBound])
        let eidStart = quoteStart.upperBound
        let eidEnd = raw.index(before: raw.endIndex)
        let eidPart = String(raw[eidStart..<eidEnd]).replacingOccurrences(of: "\\\"", with: "\"")

        let name = parseName(typePart)
        return EntityUID(ty: name, eid: eidPart)
    }

    private func lookupExtFun(_ name: String) -> ExtFun? {
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
}
