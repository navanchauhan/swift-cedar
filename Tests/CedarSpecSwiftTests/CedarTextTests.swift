import XCTest
@testable import CedarSpecSwift

final class CedarTextTests: XCTestCase {
    func testPolicyTextRoundTripParseEmitParseIsStable() {
        let text = #"""
@id("forbid-download")
forbid (
    principal,
    action == Action::"download",
    resource
)
when { ip("10.0.0.1").isIpv4() && ["a", "b"].contains("a") && {department: context.department}.department == context.department };

@id("permit-photo")
@owner("security")
permit (
    principal in Team::"eng",
    action in [Action::"edit", Action::"view"],
    resource is Photo in Album::"vacation"
)
when { context has department && context.department == "Engineering" }
unless { resource.hasTag("blocked") || "folder-42" like "folder-*" };
"""#

        let first = unwrapLoad(loadPoliciesCedar(text, source: "policies.cedar"))
        let emitted = emitCedar(first)
        let second = unwrapLoad(loadPoliciesCedar(emitted, source: "re-emitted.cedar"))

        XCTAssertEqual(second, first)
        XCTAssertEqual(emitCedar(second), emitted)
    }

    func testTemplateTextRoundTripParseEmitParseIsStable() {
        let text = #"""
@id("template-read")
@owner("security")
permit (
    principal == ?principal,
    action == Action::"read",
    resource in ?resource
)
when { principal is User && context has owner };

@id("template-admin")
forbid (
    principal is User in ?principal,
    action in [Action::"delete", Action::"write"],
    resource == ?resource
)
unless { resource.getTag("classification") == "public" };
"""#

        let first = unwrapLoad(loadTemplatesCedar(text, source: "templates.cedar"))
        let emitted = emitCedar(first)
        let second = unwrapLoad(loadTemplatesCedar(emitted, source: "re-emitted-templates.cedar"))

        XCTAssertEqual(second, first)
        XCTAssertEqual(emitCedar(second), emitted)
    }

    func testPolicyTextParsingReportsSourceAwareDiagnostics() {
        let result = loadPoliciesCedar(
            #"""
permit (
    principal,
    action,
    resource
)
when { context has department }
"""#,
            source: "missing-semicolon.cedar"
        )

        guard case let .failure(diagnostics) = result else {
            return XCTFail("Expected parse failure")
        }

        XCTAssertTrue(diagnostics.hasErrors)
        XCTAssertEqual(diagnostics.elements.first?.code, "parse.expectedToken")
        XCTAssertEqual(diagnostics.elements.first?.sourceSpan?.source, "missing-semicolon.cedar")
        XCTAssertEqual(diagnostics.elements.first?.sourceSpan?.start.line, 6)
    }

    func testPolicyTextRejectsTemplateSlotsInStaticPolicies() {
        let result = loadPoliciesCedar(
            #"""
permit (
    principal == ?principal,
    action,
    resource
);
"""#,
            source: "policy-with-slot.cedar"
        )

        guard case let .failure(diagnostics) = result else {
            return XCTFail("Expected parse failure")
        }

        XCTAssertEqual(diagnostics.elements.first?.code, "parse.invalidPolicySlot")
    }

    func testPolicyTextRoundTripPreservesConditionalAndActionSetEdgeCases() {
        let text = #"""
@id("conditional-roundtrip")
permit (
    principal is User,
    action in [Action::"approve", Action::"view"],
    resource
)
when {
    if context has department
    then {allowed: context.department == "Engineering", tags: ["a", "b"]}.allowed
    else false
};
"""#

        let first = unwrapLoad(loadPoliciesCedar(text, source: "conditional.cedar"))
        let emitted = emitCedar(first)
        let second = unwrapLoad(loadPoliciesCedar(emitted, source: "conditional-reemitted.cedar"))

        XCTAssertEqual(second, first)
        XCTAssertEqual(emitCedar(second), emitted)
    }

    private func unwrapLoad<T>(_ result: LoadResult<T>, file: StaticString = #filePath, line: UInt = #line) -> T {
        switch result {
        case let .success(value, diagnostics):
            XCTAssertFalse(diagnostics.hasErrors, file: file, line: line)
            return value
        case let .failure(diagnostics):
            XCTFail("Expected successful load, got diagnostics: \(diagnostics.elements)", file: file, line: line)
            fatalError("unreachable")
        }
    }
}
