internal let decimalDigits = 4

private let decimalScale: Int64 = 10_000
private let decimalScaleMagnitude: UInt64 = 10_000
private let decimalPow10: [Int64] = [1, 10, 100, 1_000, 10_000]

internal enum DecimalSemanticValue: Equatable, Sendable {
    case valid(Int64)
    case invalid(String)
}

internal func decimalParse(_ rawValue: String) -> Int64? {
    let parts = rawValue.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 2 else {
        return nil
    }

    let left = String(parts[0])
    let right = String(parts[1])

    if left == "-" {
        return nil
    }

    guard !right.isEmpty, right.count <= decimalDigits else {
        return nil
    }

    guard let leftValue = Int64(left), let rightValue = decimalParseNat(right) else {
        return nil
    }

    guard let scaledLeft = CedarInt64.mul(leftValue, decimalScale) else {
        return nil
    }

    let scaledRight = Int64(rightValue) * decimalPow10[decimalDigits - right.count]

    if left.hasPrefix("-") {
        return CedarInt64.sub(scaledLeft, scaledRight)
    }

    return CedarInt64.add(scaledLeft, scaledRight)
}

internal func decimalCanonicalString(_ value: Int64) -> String {
    let sign = value < 0 ? "-" : ""
    let magnitude = value.magnitude
    let left = magnitude / decimalScaleMagnitude
    let right = magnitude % decimalScaleMagnitude
    let rightDigits = String(right)
    let paddedRight = String(repeating: "0", count: decimalDigits - rightDigits.count) + rightDigits

    return "\(sign)\(left).\(paddedRight)"
}

internal func decimalSemanticValue(_ payload: Ext.Decimal) -> DecimalSemanticValue {
    guard let parsed = decimalParse(payload.rawValue) else {
        return .invalid(payload.rawValue)
    }

    return .valid(parsed)
}

internal func decimalPayloadIsSupported(_ payload: Ext.Decimal) -> Bool {
    decimalParse(payload.rawValue) != nil
}

internal func decimalSemanticEqual(_ lhs: Ext.Decimal, _ rhs: Ext.Decimal) -> Bool {
    switch (decimalSemanticValue(lhs), decimalSemanticValue(rhs)) {
    case let (.valid(left), .valid(right)):
        return left == right
    case let (.invalid(left), .invalid(right)):
        return cedarStringEqual(left, right)
    default:
        return false
    }
}

internal func decimalSemanticLess(_ lhs: Ext.Decimal, _ rhs: Ext.Decimal) -> Bool {
    switch (decimalSemanticValue(lhs), decimalSemanticValue(rhs)) {
    case let (.valid(left), .valid(right)):
        return left < right
    case (.valid, .invalid):
        return true
    case (.invalid, .valid):
        return false
    case let (.invalid(left), .invalid(right)):
        return cedarStringLess(left, right)
    }
}

internal func decimalSemanticHash(_ payload: Ext.Decimal, into hasher: inout Hasher) {
    switch decimalSemanticValue(payload) {
    case let .valid(value):
        hasher.combine(0)
        hasher.combine(value)
    case let .invalid(rawValue):
        hasher.combine(1)
        cedarHashString(rawValue, into: &hasher)
    }
}

internal func extResult(_ ext: Ext?) -> CedarResult<CedarValue> {
    guard let ext else {
        return .failure(.extensionError)
    }

    return .success(.ext(ext))
}

internal func decimalComparisonResult(
    _ lhs: Ext.Decimal,
    _ rhs: Ext.Decimal,
    predicate: (Int64, Int64) -> Bool
) -> CedarResult<CedarValue> {
    guard let left = decimalParse(lhs.rawValue), let right = decimalParse(rhs.rawValue) else {
        return .failure(.extensionError)
    }

    return .success(.prim(.bool(predicate(left, right))))
}

private func decimalParseNat(_ rawValue: String) -> UInt64? {
    guard !rawValue.isEmpty else {
        return nil
    }

    var value: UInt64 = 0

    for scalar in rawValue.unicodeScalars {
        guard scalar.value >= 48, scalar.value <= 57 else {
            return nil
        }

        value = value * 10 + UInt64(scalar.value - 48)
    }

    return value
}