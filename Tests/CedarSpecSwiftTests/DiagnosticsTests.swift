import XCTest
@testable import CedarSpecSwift

final class DiagnosticsTests: XCTestCase {
    func testSourceLocationAndSourceSpanUseStableScalarStrictValueSemantics() {
        let location = SourceLocation(line: 2, column: 4, offset: 9)
        let sameLocation = SourceLocation(line: 2, column: 4, offset: 9)
        let earlierLocation = SourceLocation(line: 2, column: 3, offset: 8)
        let composed = "\u{00E9}.cedar"
        let decomposed = "e\u{0301}.cedar"
        let lhs = SourceSpan(start: location, end: SourceLocation(line: 2, column: 7, offset: 12), source: composed)
        let rhs = SourceSpan(start: location, end: SourceLocation(line: 2, column: 7, offset: 12), source: decomposed)

        XCTAssertEqual(location, sameLocation)
        XCTAssertLessThan(earlierLocation, location)
        XCTAssertNotEqual(lhs, rhs)
        XCTAssertLessThan(rhs, lhs)
    }

    func testDiagnosticsCanonicalizeIntoDeterministicOrdering() {
        let earlySpan = SourceSpan(
            start: SourceLocation(line: 1, column: 1, offset: 0),
            end: SourceLocation(line: 1, column: 5, offset: 4),
            source: "a.cedar"
        )
        let lateSpan = SourceSpan(
            start: SourceLocation(line: 2, column: 1, offset: 10),
            end: SourceLocation(line: 2, column: 5, offset: 14),
            source: "a.cedar"
        )
        let diagnostics = Diagnostics([
            Diagnostic(
                code: "internal.note",
                category: .internal,
                severity: .info,
                message: "note without source span"
            ),
            Diagnostic(
                code: "request.warning",
                category: .request,
                severity: .warning,
                message: "late warning",
                sourceSpan: lateSpan
            ),
            Diagnostic(
                code: "parse.error",
                category: .parse,
                severity: .error,
                message: "early error",
                sourceSpan: earlySpan
            ),
            Diagnostic(
                code: "parse.warning",
                category: .parse,
                severity: .warning,
                message: "early warning",
                sourceSpan: earlySpan
            ),
        ])

        XCTAssertEqual(
            diagnostics.elements.map(\.code),
            ["parse.warning", "parse.error", "request.warning", "internal.note"]
        )
    }

    func testDiagnosticsAggregationPreservesDuplicateStructuredDiagnosticsRepeatably() {
        let duplicate = Diagnostic(
            code: "policy.duplicate_id",
            category: .policy,
            severity: .error,
            message: "duplicate policy id",
            sourceSpan: SourceSpan(
                start: SourceLocation(line: 3, column: 2, offset: 21),
                end: SourceLocation(line: 3, column: 7, offset: 26),
                source: "policies.cedar"
            )
        )
        let lhs = Diagnostics([duplicate])
            .appending(duplicate)
            .appending(contentsOf: Diagnostics([duplicate]))
        let rhs = Diagnostics([duplicate, duplicate]).appending(duplicate)

        XCTAssertEqual(lhs, rhs)
        XCTAssertEqual(lhs.elements.count, 3)
        XCTAssertEqual(lhs.elements, [duplicate, duplicate, duplicate])
    }

    func testLoadResultSuccessCarriesWarningsWithoutFailure() {
        let warning = Diagnostic(
            code: "schema.warning",
            category: .schema,
            severity: .warning,
            message: "unused schema fragment"
        )
        let result: LoadResult<String> = .success("loaded", diagnostics: Diagnostics([warning]))

        switch result {
        case let .success(value, diagnostics):
            XCTAssertEqual(value, "loaded")
            XCTAssertEqual(diagnostics.elements, [warning])
            XCTAssertFalse(diagnostics.hasErrors)
            XCTAssertEqual(result.value, "loaded")
            XCTAssertTrue(result.isSuccess)
        case .failure:
            XCTFail("Expected success result")
        }
    }

    func testLoadResultFailureCarriesDiagnosticsWithoutPartialPayload() {
        let error = Diagnostic(
            code: "request.context_invalid",
            category: .request,
            severity: .error,
            message: "request context must be a record"
        )
        let result: LoadResult<String> = .failure(Diagnostics([error]))

        switch result {
        case .success:
            XCTFail("Expected failure result")
        case let .failure(diagnostics):
            XCTAssertEqual(diagnostics.elements, [error])
            XCTAssertTrue(diagnostics.hasErrors)
            XCTAssertNil(result.value)
            XCTAssertFalse(result.isSuccess)
        }
    }

    func testValidationResultSuccessAndFailureFollowFrozenConventions() {
        let warning = Diagnostic(
            code: "validation.shadowed_annotation",
            category: .validation,
            severity: .warning,
            message: "annotation is ignored during validation"
        )
        let error = Diagnostic(
            code: "validation.type_error",
            category: .validation,
            severity: .error,
            message: "condition does not typecheck"
        )
        let success = ValidationResult.success(diagnostics: Diagnostics([warning]))
        let failure = ValidationResult.failure(Diagnostics([error, warning]))

        XCTAssertTrue(success.isValid)
        XCTAssertEqual(success.diagnostics.elements, [warning])
        XCTAssertFalse(success.diagnostics.hasErrors)
        XCTAssertFalse(failure.isValid)
        XCTAssertEqual(failure.diagnostics.elements, [warning, error])
        XCTAssertTrue(failure.diagnostics.hasErrors)
    }
}