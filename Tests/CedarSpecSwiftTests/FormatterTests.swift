import XCTest
@testable import CedarSpecSwift

final class FormatterTests: XCTestCase {
    func testFormatCedarCanonicalizesPolicyIndentation() {
        let input = #"""
@id("policy-a")
permit(principal,action == Action::"view",resource)
when {context has department};
"""#

        let formatted = unwrapLoad(formatCedar(input, source: "policy.cedar"))

        XCTAssertEqual(formatted, #"""
@id("policy-a")
permit (
  principal,
  action == Action::"view",
  resource
)
when { context has department };
"""#)
    }

    func testLoadExpressionCedarParsesStandaloneExpressions() {
        let expression = unwrapLoad(loadExpressionCedar(#"principal == User::"alice""#, source: "expr.cedar"))

        XCTAssertEqual(
            expression,
            .binaryApp(
                .equal,
                .variable(.principal),
                .lit(.prim(.entityUID(EntityUID(ty: Name(id: "User"), eid: "alice"))))
            )
        )
    }
}
