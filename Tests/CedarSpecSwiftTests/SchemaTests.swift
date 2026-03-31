import XCTest
@testable import CedarSpecSwift

final class SchemaTests: XCTestCase {
    func testLoadSchemaParsesEntityTypesAndActions() {
        let schema = unwrapLoad(loadSchema(LoaderFixtures.schemaJSON, source: "schema.json"))

        XCTAssertEqual(schema.entityType(Name(id: "User"))?.memberOfTypes, CedarSet.make([Name(id: "Group")]))
        XCTAssertEqual(
            schema.entityType(Name(id: "User"))?.attributes.find("department"),
            .required(.string)
        )
        XCTAssertEqual(schema.entityType(Name(id: "User"))?.tags, .bool)
        XCTAssertEqual(schema.action(EntityUID(ty: Name(id: "Action"), eid: "view"))?.memberOf, CedarSet.make([
            EntityUID(ty: Name(id: "Action"), eid: "read")
        ]))
        XCTAssertEqual(
            schema.action(EntityUID(ty: Name(id: "Action"), eid: "view"))?.context.find("ttl"),
            .required(.ext(.duration))
        )
    }

    func testLoadSchemaRejectsInvalidActionUID() {
        let diagnostics = unwrapFailure(loadSchema(#"{"actions":{"not-a-uid":{}}}"#))
        XCTAssertEqual(diagnostics.elements.first?.code, "schema.invalidActionUID")
    }

    func testLoadSchemaCedarMatchesEquivalentJSONSchema() {
        let textSchema = unwrapLoad(loadSchemaCedar(#"""
namespace Demo {
    type Department = String;

    entity User in [Group] = {
        department: Department,
        nickname?: String
    } tags String;

    entity Group;
    entity Photo;

    action "read";
    action "view" in ["read"] appliesTo {
        principal: [User],
        resource: [Photo],
        context: {
            department?: Department,
            ttl: duration
        }
    };
}
"""#, source: "schema.cedarschema"))
        let jsonSchema = unwrapLoad(loadSchema(#"""
{
      "entityTypes": {
        "Demo::User": {
          "memberOfTypes": ["Demo::Group"],
          "attrs": {
        "department": "string",
        "nickname": { "type": "string", "required": false }
          },
      "tags": "string"
        },
        "Demo::Group": {},
        "Demo::Photo": {}
      },
  "actions": {
    "Demo::Action::\"read\"": {},
    "Demo::Action::\"view\"": {
      "principalTypes": ["Demo::User"],
      "resourceTypes": ["Demo::Photo"],
      "memberOf": ["Demo::Action::\"read\""],
      "context": {
        "department": { "type": "string", "required": false },
        "ttl": "duration"
      }
    }
  }
}
"""#, source: "schema.json"))

        XCTAssertEqual(textSchema, jsonSchema)
    }

    func testLoadSchemaCedarReportsSourceAwareDiagnostics() {
        let result = loadSchemaCedar(#"""
namespace Demo {
    entity User
}
"""#, source: "broken.cedarschema")

        guard case let .failure(diagnostics) = result else {
            return XCTFail("Expected schema parse failure")
        }

        XCTAssertTrue(diagnostics.hasErrors)
        XCTAssertEqual(diagnostics.elements.first?.code, "schema.unexpectedToken")
        XCTAssertEqual(diagnostics.elements.first?.sourceSpan?.source, "broken.cedarschema")
    }
}
