import XCTest
@testable import CedarSpecSwift

final class WildcardTests: XCTestCase {
    func testEmptyPatternMatchesOnlyEmptyInput() {
        XCTAssertTrue(wildcardMatch(Pattern([]), value: scalars("")))
        XCTAssertFalse(wildcardMatch(Pattern([]), value: scalars("cedar")))
    }

    func testLiteralOnlyPatternRequiresExactScalarSequence() {
        let pattern = Pattern(literals("cedar"))

        XCTAssertTrue(wildcardMatch(pattern, value: scalars("cedar")))
        XCTAssertFalse(wildcardMatch(pattern, value: scalars("cedars")))
        XCTAssertFalse(wildcardMatch(pattern, value: scalars("Cedar")))
    }

    func testLeadingTrailingAndInteriorWildcardsMatchGreedily() {
        let leading = Pattern([.wildcard] + literals("admin"))
        let trailing = Pattern(literals("admin") + [.wildcard])
        let interior = Pattern(literals("a") + [.wildcard] + literals("min"))

        XCTAssertTrue(wildcardMatch(leading, value: scalars("superadmin")))
        XCTAssertTrue(wildcardMatch(trailing, value: scalars("administrator")))
        XCTAssertTrue(wildcardMatch(interior, value: scalars("alxxmin")))
        XCTAssertFalse(wildcardMatch(interior, value: scalars("aluminum")))
    }

    func testRepeatedWildcardsCollapseToExpectedMatches() {
        let pattern = Pattern([.wildcard, .wildcard] + literals("ab") + [.wildcard, .wildcard])

        XCTAssertTrue(wildcardMatch(pattern, value: scalars("ab")))
        XCTAssertTrue(wildcardMatch(pattern, value: scalars("zzabyy")))
        XCTAssertFalse(wildcardMatch(pattern, value: scalars("zzayyy")))
    }

    func testWildcardUsesUnicodeScalarSemanticsForCombiningMarks() {
        let pattern = Pattern(literals("e") + [.wildcard])
        let decomposed = "e\u{0301}clair"
        let composed = "\u{00E9}clair"

        XCTAssertTrue(wildcardMatch(pattern, value: scalars(decomposed)))
        XCTAssertFalse(wildcardMatch(pattern, value: scalars(composed)))
    }

    func testWildcardMatchesEmojiAsUnicodeScalarSequences() {
        let emoji = "👩‍💻"
        let pattern = Pattern([.wildcard] + literals(emoji) + [.wildcard])

        XCTAssertTrue(wildcardMatch(pattern, value: scalars("dev👩‍💻mode")))
        XCTAssertFalse(wildcardMatch(pattern, value: scalars("dev👨‍💻mode")))
    }

    private func literals(_ string: String) -> [PatElem] {
        string.unicodeScalars.map(PatElem.literal)
    }

    private func scalars(_ string: String) -> [Unicode.Scalar] {
        Array(string.unicodeScalars)
    }
}
