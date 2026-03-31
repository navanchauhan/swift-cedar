# swift-cedar

`swift-cedar` is a library-first Swift implementation of the Cedar policy language. It parses Cedar text and JSON inputs, evaluates authorization requests, validates policies and entities against Cedar schemas, slices entity stores for focused evaluation, formats Cedar policy files, and ships a small `cedar` CLI plus a `Benchmarks` executable.

## Installation

Add `swift-cedar` to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/navanchauhan/swift-cedar.git", from: "0.1.0")
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "CedarSpecSwift", package: "swift-cedar")
        ]
    )
]
```

## Usage

This example mirrors the Cedar Go README flow with `alice`, `view`, and `VacationPhoto94.jpg`:

```swift
import CedarSpecSwift

let policiesResult = loadPoliciesCedar(#"""
permit (
    principal == User::"alice",
    action == Action::"view",
    resource in Album::"jane_vacation"
);
"""#).value.unwrap()
guard case let .success(policies, _) = policiesResult else {
    fatalError("Unable to load policies")
}

let entitiesResult = loadEntities(#"""
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
"""#)
guard case let .success(entities, _) = entitiesResult else {
    fatalError("Unable to load entities")
}

let request = Request(
    principal: EntityUID(ty: Name(id: "User"), eid: "alice"),
    action: EntityUID(ty: Name(id: "Action"), eid: "view"),
    resource: EntityUID(ty: Name(id: "Photo"), eid: "VacationPhoto94.jpg")
)

let response = isAuthorized(request: request, entities: entities, policies: policies)
print(response.decision)
```

## API Overview

- Authorization: `isAuthorized(request:entities:policies:)`
- Evaluation: `evaluate(_:request:entities:)`, `loadExpressionCedar(_:)`
- Parsing and loading: `loadPoliciesCedar`, `loadPolicies`, `loadEntities`, `loadRequest`, `loadSchemaCedar`, `loadSchemaJSON`
- Validation: `validatePolicies`, `validateEntities`, `validateRequest`
- Entity slicing: `sliceEUIDs`, `sliceAtLevel`, `sliceEntities`, `sliceEntitiesForPartialEvaluation`
- Batch authorization: `BatchRequestTemplate`, `BatchVariableDomains`, `batchAuthorize`
- Formatting: `formatCedar`, `emitCedar`

## CLI

The package now ships a separate executable target named `cedar`.

### `cedar authorize`

```bash
swift run cedar authorize \
  --policies policies.cedar \
  --entities entities.json \
  --request request.json
```

### `cedar validate`

```bash
swift run cedar validate \
  --schema schema.cedarschema \
  --policies policies.cedar \
  --entities entities.json \
  --request request.json \
  --mode strict \
  --level 2
```

### `cedar format`

```bash
swift run cedar format policy.cedar
swift run cedar format --in-place policy.cedar other-policy.cedar
```

### `cedar evaluate`

```bash
swift run cedar evaluate \
  --expression 'principal == User::"alice"' \
  --request request.json \
  --entities entities.json
```

## Benchmarks

Run the benchmark executable against the same corpus directories used by the test suite:

```bash
swift run Benchmarks --limit 100
```

Environment overrides:

- `CEDAR_CORPUS_DIR`
- `CEDAR_VALIDATION_DIR`
- `CEDAR_JSON_SCHEMA_DIR`
- `CEDAR_BENCH_LIMIT`

## Feature Comparison

| Feature | Swift | Go | Rust | .NET |
| --- | --- | --- | --- | --- |
| Cedar text parsing | Yes | Yes | Yes | Yes |
| Cedar JSON loading | Yes | Yes | Yes | Yes |
| Authorization | Yes | Yes | Yes | Yes |
| Schema validation | Yes | Yes | Yes | Yes |
| Entity slicing | Yes | Yes | Yes | Varies |
| Batch authorization | Yes | Yes | Yes | Varies |
| Canonical formatting | Yes | Yes | Yes | Varies |
| CLI executable | Yes | Yes | Yes | Varies |
| Corpus benchmarks | Yes | Yes | Yes | Varies |

## Corpus Results

- Authorization corpus parity: 100%
- Validation corpus parity: 100%
- Validation corpus and DRT status remain green in this final-polish branch

## License

This project is licensed under the Apache License 2.0.
