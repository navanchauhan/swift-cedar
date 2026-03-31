import XCTest
@testable import CedarSpecSwift

final class CorpusAuthorizationTests: XCTestCase {
    func testEndToEndLoadingLinkingAndAuthorizationSucceeds() {
        let schema = unwrapLoad(loadSchema(Data(LoaderFixtures.schemaJSON.utf8), source: "schema.json"))
        let templates = unwrapLoad(loadTemplates(Data(LoaderFixtures.templatesJSON.utf8), source: "templates.json"))
        let templateLinks = unwrapLoad(loadTemplateLinks(Data(LoaderFixtures.templateLinksJSON.utf8), source: "links.json"))
        let staticPolicies = unwrapLoad(loadPolicies(Data(LoaderFixtures.policiesJSON.utf8), source: "policies.json"))
        let entities = unwrapLoad(loadEntities(Data(LoaderFixtures.entitiesJSON.utf8), schema: schema, source: "entities.json"))
        let request = unwrapLoad(loadRequest(Data(LoaderFixtures.requestJSON.utf8), schema: schema, source: "request.json"))
        let linkedPolicies = templateLinks.map { unwrapLoad(link(templateLinkedPolicy: $0, templates: templates)) }
        let policies = CedarMap.make(staticPolicies.entries + linkedPolicies.map { ($0.id, $0) })
        let response = isAuthorized(request: request, entities: entities, policies: policies)

        XCTAssertEqual(response.decision, .allow)
        XCTAssertEqual(response.determining, CedarSet.make(["linked-view", "permit-view"]))
        XCTAssertEqual(response.erroring, .empty)
    }

    func testEndToEndLinkFailureProducesDeterministicDiagnostics() {
        let templates = unwrapLoad(loadTemplates(LoaderFixtures.templatesJSON))
        let links = unwrapLoad(loadTemplateLinks(#"[{"id":"linked-view","templateId":"template-view","slots":[{"slot":"principal","entity":"User::\"alice\""}]}]"#))
        let diagnostics = unwrapFailure(link(templateLinkedPolicy: links[0], templates: templates))

        XCTAssertEqual(diagnostics.elements.first?.code, "template.missingSlotBinding")
    }
}