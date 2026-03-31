import XCTest
@testable import CedarSpecSwift

func unwrapLoad<Success>(_ result: LoadResult<Success>, file: StaticString = #filePath, line: UInt = #line) -> Success {
    switch result {
    case let .success(value, diagnostics):
        XCTAssertFalse(diagnostics.hasErrors, file: file, line: line)
        return value
    case let .failure(diagnostics):
        XCTFail("Expected success, got diagnostics: \(diagnostics.elements)", file: file, line: line)
        fatalError("unreachable")
    }
}

func unwrapResult<Success>(_ result: CedarResult<Success>, file: StaticString = #filePath, line: UInt = #line) -> Success {
    switch result {
    case let .success(value):
        return value
    case let .failure(error):
        XCTFail("Expected success, got error: \(error)", file: file, line: line)
        fatalError("unreachable")
    }
}

func unwrapFailure<Success>(_ result: LoadResult<Success>, file: StaticString = #filePath, line: UInt = #line) -> Diagnostics {
    switch result {
    case .success:
        XCTFail("Expected failure", file: file, line: line)
        return .empty
    case let .failure(diagnostics):
        return diagnostics
    }
}