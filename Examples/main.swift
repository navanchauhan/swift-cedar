import CedarSpecSwift
import Foundation

// -- Cedar policy in the Cedar text format (identical to Go/Rust) --
let policyCedar = """
    permit (
        principal == User::"alice",
        action == Action::"view",
        resource in Album::"jane_vacation"
    );
    """

// -- Entities as JSON (identical to Go/Rust official format) --
let entitiesJSON = """
    [
      {
        "uid": { "type": "User", "id": "alice" },
        "attrs": { "age": 18 },
        "parents": []
      },
      {
        "uid": { "type": "Photo", "id": "VacationPhoto94.jpg" },
        "attrs": {},
        "parents": [{ "type": "Album", "id": "jane_vacation" }]
      }
    ]
    """

// 1. Parse policies from Cedar text
let policiesResult = loadPoliciesCedar(policyCedar)
guard case let .success(policies, _) = policiesResult else {
    print("Failed to parse policies: \(policiesResult)")
    exit(1)
}

// 2. Load entities from JSON (accepts both {"type","id"} and string formats)
let entitiesResult = loadEntities(entitiesJSON)
guard case let .success(entities, _) = entitiesResult else {
    print("Failed to load entities: \(entitiesResult)")
    exit(1)
}

// 3. Build a request
let request = Request(
    principal: EntityUID(ty: Name(id: "User"), eid: "alice"),
    action:    EntityUID(ty: Name(id: "Action"), eid: "view"),
    resource:  EntityUID(ty: Name(id: "Photo"), eid: "VacationPhoto94.jpg"),
    context:   .record(CedarMap.make([
        CedarMap.Entry(key: "demoRequest", value: .bool(true))
    ]))
)

// 4. Authorize
let response = isAuthorized(request: request, entities: entities, policies: policies)

print("Decision: \(response.decision)")  // allow
print("Determining policies: \(response.determining)")
if !response.erroring.isEmpty {
    print("Erroring policies: \(response.erroring)")
}
