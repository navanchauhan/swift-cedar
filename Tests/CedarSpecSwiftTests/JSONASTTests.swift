import XCTest
import Foundation
@testable import CedarSpecSwift

final class JSONASTTests: XCTestCase {
    func testDecodeJSONCapturesSpansAndEscapes() {
        let result = decodeJSONValue(#"{"message":"line\nvalue","pattern":"Eng\\*"}"#, source: "input.json")
        let root = unwrapLoad(result)

        guard case let .object(entries, span) = root else {
            return XCTFail("Expected object")
        }

        XCTAssertEqual(span.source, "input.json")
        XCTAssertEqual(entries.first?.key, "message")
        if case let .string(message, messageSpan)? = entries.first?.value {
            XCTAssertEqual(message, "line\nvalue")
            XCTAssertEqual(messageSpan.source, "input.json")
        } else {
            XCTFail("Expected string value")
        }
    }

    func testDecodeJSONFailsDeterministicallyOnDepthLimit() {
        let diagnostics = unwrapFailure(decodeJSONValue("[[[[[]]]]]", source: "deep.json", maxDepth: 3))
        XCTAssertEqual(diagnostics.elements.first?.code, "json.depthLimitExceeded")
        XCTAssertEqual(diagnostics.elements.first?.sourceSpan?.source, "deep.json")
    }

    func testDecodeJSONDataPathPreservesUTF8StringsAndSpans() {
        let data = Data(#"{"label":"café","nested":[{"emoji":"🙂"}]}"#.utf8)
        let root = unwrapLoad(decodeJSONValue(data, source: "utf8.json"))

        guard case let .object(entries, span) = root else {
            return XCTFail("Expected object")
        }

        XCTAssertEqual(span.source, "utf8.json")
        guard let labelField = findJSONField(entries, "label"),
              case let .string(label, labelSpan) = labelField.value
        else {
            return XCTFail("Expected label string")
        }

        XCTAssertEqual(label, "café")
        XCTAssertEqual(labelSpan.source, "utf8.json")
    }
}
