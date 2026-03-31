import Foundation

enum LoaderFixtures {
    static let schemaJSON = #"""
    {
      "entityTypes": {
        "User": {
          "memberOfTypes": ["Group"],
          "attrs": {
            "department": { "type": "string" },
            "manager": { "type": "entity", "name": "Group" }
          },
          "tags": { "type": "bool" }
        },
        "Group": {
          "memberOfTypes": ["Group"],
          "attrs": {
            "department": { "type": "string", "required": false }
          }
        },
        "Photo": {
          "memberOfTypes": [],
          "attrs": {
            "owner": { "type": "entity", "name": "User", "required": false }
          }
        }
      },
      "actions": {
        "Action::\"all\"": {
          "principalTypes": ["User"],
          "resourceTypes": ["Photo"],
          "memberOf": [],
          "context": {
            "department": { "type": "string" },
            "ttl": { "type": "duration" }
          }
        },
        "Action::\"read\"": {
          "principalTypes": ["User"],
          "resourceTypes": ["Photo"],
          "memberOf": ["Action::\"all\""],
          "context": {
            "department": { "type": "string" },
            "ttl": { "type": "duration" }
          }
        },
        "Action::\"view\"": {
          "principalTypes": ["User"],
          "resourceTypes": ["Photo"],
          "memberOf": ["Action::\"read\""],
          "context": {
            "department": { "type": "string" },
            "ttl": { "type": "duration" }
          }
        }
      }
    }
    """#

    static let entitiesJSON = #"""
    [
      {
        "uid": "User::\"alice\"",
        "parents": ["Group::\"staff\""],
        "attrs": {
          "department": "Engineering",
          "manager": { "type": "entity", "value": "Group::\"staff\"" }
        },
        "tags": {
          "active": true
        }
      },
      {
        "uid": "Group::\"staff\"",
        "parents": ["Group::\"company\""],
        "attrs": {},
        "tags": {}
      },
      {
        "uid": "Group::\"company\"",
        "parents": [],
        "attrs": {},
        "tags": {}
      },
      {
        "uid": "Action::\"view\"",
        "parents": ["Action::\"read\""],
        "attrs": {},
        "tags": {}
      },
      {
        "uid": "Action::\"read\"",
        "parents": ["Action::\"all\""],
        "attrs": {},
        "tags": {}
      },
      {
        "uid": "Action::\"all\"",
        "parents": [],
        "attrs": {},
        "tags": {}
      },
      {
        "uid": "Photo::\"vacation\"",
        "parents": [],
        "attrs": {},
        "tags": {}
      }
    ]
    """#

    static let requestJSON = #"""
    {
      "principal": "User::\"alice\"",
      "action": "Action::\"view\"",
      "resource": "Photo::\"vacation\"",
      "context": {
        "department": "Engineering",
        "ttl": { "type": "call", "function": "duration", "args": ["1h"] }
      }
    }
    """#

    static let invalidRequestJSON = #"""
    {
      "principal": "User::\"alice\"",
      "action": "Action::\"view\"",
      "resource": "Photo::\"vacation\"",
      "context": {
        "ttl": { "type": "call", "function": "duration", "args": ["PT1H"] }
      }
    }
    """#

    static let policiesJSON = #"""
    [
      {
        "id": "permit-view",
        "annotations": { "owner": "security" },
        "effect": "permit",
        "principal": { "op": "eq", "entity": "User::\"alice\"" },
        "action": { "op": "eq", "entity": "Action::\"view\"" },
        "resource": { "op": "eq", "entity": "Photo::\"vacation\"" },
        "conditions": [
          {
            "kind": "when",
            "body": {
              "type": "binary",
              "op": "equal",
              "left": {
                "type": "getAttr",
                "expr": { "type": "var", "name": "context" },
                "attr": "department"
              },
              "right": {
                "type": "lit",
                "value": { "type": "string", "value": "Engineering" }
              }
            }
          },
          {
            "kind": "when",
            "body": {
              "type": "like",
              "expr": {
                "type": "getAttr",
                "expr": { "type": "var", "name": "context" },
                "attr": "department"
              },
              "pattern": "Eng*"
            }
          }
        ]
      }
    ]
    """#

    static let templatesJSON = #"""
    [
      {
        "id": "template-view",
        "annotations": { "template": "true" },
        "effect": "permit",
        "principal": { "op": "eq", "entity": { "slot": "principal" } },
        "action": { "op": "eq", "entity": "Action::\"view\"" },
        "resource": { "op": "eq", "entity": { "slot": "resource" } },
        "conditions": [
          {
            "kind": "when",
            "body": {
              "type": "binary",
              "op": "equal",
              "left": {
                "type": "getAttr",
                "expr": { "type": "var", "name": "context" },
                "attr": "department"
              },
              "right": {
                "type": "lit",
                "value": { "type": "string", "value": "Engineering" }
              }
            }
          }
        ]
      }
    ]
    """#

    static let templateLinksJSON = #"""
    [
      {
        "id": "linked-view",
        "templateId": "template-view",
        "slots": [
          { "slot": "principal", "entity": "User::\"alice\"" },
          { "slot": "resource", "entity": "Photo::\"vacation\"" }
        ],
        "annotations": { "link": "true" }
      }
    ]
    """#

    static let duplicatePolicyIDsPoliciesJSON = #"""
    [
      {
        "id": "duplicate-policy-id",
        "effect": "permit",
        "principal": { "op": "any" },
        "action": { "op": "any" },
        "resource": { "op": "any" },
        "conditions": []
      },
      {
        "id": "duplicate-policy-id",
        "effect": "permit",
        "principal": { "op": "any" },
        "action": { "op": "any" },
        "resource": { "op": "any" },
        "conditions": []
      }
    ]
    """#

    static let duplicatePolicyIDsTemplateLinksJSON = #"""
    [
      {
        "id": "duplicate-policy-id",
        "templateId": "template-view",
        "slots": []
      },
      {
        "id": "duplicate-policy-id",
        "templateId": "template-view",
        "slots": []
      }
    ]
    """#

    static let cycleEntitiesJSON = #"""
    [
      { "uid": "Group::\"a\"", "parents": ["Group::\"b\""], "attrs": {}, "tags": {} },
      { "uid": "Group::\"b\"", "parents": ["Group::\"a\""], "attrs": {}, "tags": {} }
    ]
    """#

    static var corpusJSON: String {
        "{" +
            "\"schema\":" + schemaJSON + "," +
            "\"templates\":" + templatesJSON + "," +
            "\"templateLinks\":" + templateLinksJSON + "," +
            "\"policies\":" + policiesJSON + "," +
            "\"entities\":" + entitiesJSON + "," +
            "\"request\":" + requestJSON +
        "}"
    }

    static var duplicateNamespaceCorpusJSON: String {
        let template = #"""
        [{
          "id": "duplicate-policy-id",
          "effect": "permit",
          "principal": { "op": "any" },
          "action": { "op": "any" },
          "resource": { "op": "any" },
          "conditions": []
        }]
        """#

        return "{" +
            "\"templates\":" + template + "," +
            "\"policies\":" + duplicatePolicyIDsPoliciesJSON +
        "}"
    }

    static func longChainEntitiesJSON(length: Int) -> String {
        var entries: [String] = []
        for index in 0...length {
            let uid = "Group::\\\"chain-\(index)\\\""
            let parents: String
            if index < length {
                parents = "[\"Group::\\\"chain-\(index + 1)\\\"\"]"
            } else {
                parents = "[]"
            }

            entries.append("{\"uid\": \"\(uid)\", \"parents\": \(parents), \"attrs\": {}, \"tags\": {}}")
        }

        return "[\(entries.joined(separator: ","))]"
    }
}
