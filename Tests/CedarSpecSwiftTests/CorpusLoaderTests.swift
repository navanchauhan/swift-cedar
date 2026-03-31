import XCTest
@testable import CedarSpecSwift

final class CorpusLoaderTests: XCTestCase {
    func testLoadCorpusComposesSchemaPoliciesEntitiesAndRequest() {
        let corpus = unwrapLoad(loadCorpus(LoaderFixtures.corpusJSON, source: "corpus.json"))

        XCTAssertNotNil(corpus.schema)
        XCTAssertEqual(corpus.templates.find("template-view")?.annotations.find("template"), "true")
        XCTAssertEqual(corpus.templateLinks.first?.id, "linked-view")
        XCTAssertEqual(corpus.policies.find("permit-view")?.id, "permit-view")
        XCTAssertTrue(corpus.entities.contains(EntityUID(ty: Name(id: "User"), eid: "alice")))
        XCTAssertEqual(corpus.request?.principal, EntityUID(ty: Name(id: "User"), eid: "alice"))
    }

    func testLoadCorpusRejectsCrossNamespaceDuplicates() {
        let diagnostics = unwrapFailure(loadCorpus(LoaderFixtures.duplicateNamespaceCorpusJSON))
        XCTAssertEqual(diagnostics.elements.first?.code, "policy.duplicateID")
    }
}