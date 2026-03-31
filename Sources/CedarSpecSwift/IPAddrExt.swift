internal enum IPAddrSemanticValue: Equatable, Sendable {
    case valid(IPAddrParsed)
    case invalid(String)
}

internal enum IPAddrParsed: Equatable, Sendable {
    case v4(address: UInt32, prefix: Int)
    case v6(segments: [UInt16], prefix: Int)
}

internal func ipaddrParse(_ rawValue: String) -> IPAddrParsed? {
    if let ipv4 = parseIPv4Net(rawValue) {
        return ipv4
    }

    return parseIPv6Net(rawValue)
}

internal func ipaddrCanonicalString(_ value: IPAddrParsed) -> String {
    switch value {
    case let .v4(address, prefix):
        let a0 = Int((address >> 24) & 0xFF)
        let a1 = Int((address >> 16) & 0xFF)
        let a2 = Int((address >> 8) & 0xFF)
        let a3 = Int(address & 0xFF)
        return "\(a0).\(a1).\(a2).\(a3)/\(prefix)"
    case let .v6(segments, prefix):
        let rendered = segments.map { segment in
            let digits = String(segment, radix: 16, uppercase: false)
            return String(repeating: "0", count: 4 - digits.count) + digits
        }

        return rendered.joined(separator: ":") + "/\(prefix)"
    }
}

internal func ipaddrSemanticValue(_ payload: Ext.IPAddr) -> IPAddrSemanticValue {
    guard let parsed = ipaddrParse(payload.rawValue) else {
        return .invalid(payload.rawValue)
    }

    return .valid(parsed)
}

internal func ipaddrPayloadIsSupported(_ payload: Ext.IPAddr) -> Bool {
    ipaddrParse(payload.rawValue) != nil
}

internal func ipaddrSemanticEqual(_ lhs: Ext.IPAddr, _ rhs: Ext.IPAddr) -> Bool {
    switch (ipaddrSemanticValue(lhs), ipaddrSemanticValue(rhs)) {
    case let (.valid(left), .valid(right)):
        return left == right
    case let (.invalid(left), .invalid(right)):
        return cedarStringEqual(left, right)
    default:
        return false
    }
}

internal func ipaddrSemanticLess(_ lhs: Ext.IPAddr, _ rhs: Ext.IPAddr) -> Bool {
    switch (ipaddrSemanticValue(lhs), ipaddrSemanticValue(rhs)) {
    case let (.valid(left), .valid(right)):
        return ipaddrParsedLess(left, right)
    case (.valid, .invalid):
        return true
    case (.invalid, .valid):
        return false
    case let (.invalid(left), .invalid(right)):
        return cedarStringLess(left, right)
    }
}

internal func ipaddrSemanticHash(_ payload: Ext.IPAddr, into hasher: inout Hasher) {
    switch ipaddrSemanticValue(payload) {
    case let .valid(value):
        hasher.combine(0)
        hashIPAddrParsed(value, into: &hasher)
    case let .invalid(rawValue):
        hasher.combine(1)
        cedarHashString(rawValue, into: &hasher)
    }
}

internal func ipaddrConstructorResult(_ rawValue: String) -> CedarResult<CedarValue> {
    extResult(ipaddrParse(rawValue).map { _ in .ipaddr(.init(rawValue: rawValue)) })
}

internal func ipaddrPredicateResult(
    _ payload: Ext.IPAddr,
    predicate: (IPAddrParsed) -> Bool
) -> CedarResult<CedarValue> {
    guard let parsed = ipaddrParse(payload.rawValue) else {
        return .failure(.extensionError)
    }

    return .success(.prim(.bool(predicate(parsed))))
}

internal func ipaddrInRangeResult(_ lhs: Ext.IPAddr, _ rhs: Ext.IPAddr) -> CedarResult<CedarValue> {
    guard let left = ipaddrParse(lhs.rawValue), let right = ipaddrParse(rhs.rawValue) else {
        return .failure(.extensionError)
    }

    return .success(.prim(.bool(ipaddrInRange(left, right))))
}

private func parseIPv4Net(_ rawValue: String) -> IPAddrParsed? {
    let parts = rawValue.split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count == 1 || parts.count == 2 else {
        return nil
    }

    guard let address = parseIPv4Segments(String(parts[0])) else {
        return nil
    }

    let prefix: Int
    if parts.count == 1 {
        prefix = 32
    } else {
        guard let parsedPrefix = parsePrefixNat(String(parts[1]), digits: 2, size: 32) else {
            return nil
        }

        prefix = parsedPrefix
    }

    return .v4(address: address, prefix: prefix)
}

private func parseIPv6Net(_ rawValue: String) -> IPAddrParsed? {
    let parts = rawValue.split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count == 1 || parts.count == 2 else {
        return nil
    }

    guard let segments = parseIPv6Segments(String(parts[0])) else {
        return nil
    }

    let prefix: Int
    if parts.count == 1 {
        prefix = 128
    } else {
        guard let parsedPrefix = parsePrefixNat(String(parts[1]), digits: 3, size: 128) else {
            return nil
        }

        prefix = parsedPrefix
    }

    return .v6(segments: segments, prefix: prefix)
}

private func parsePrefixNat(_ rawValue: String, digits: Int, size: Int) -> Int? {
    guard !rawValue.isEmpty, rawValue.count <= digits else {
        return nil
    }

    if rawValue.hasPrefix("0") && !cedarStringEqual(rawValue, "0") {
        return nil
    }

    guard let value = parseDecimalNat(rawValue), value <= size else {
        return nil
    }

    return value
}

private func parseIPv4Segments(_ rawValue: String) -> UInt32? {
    let parts = rawValue.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4 else {
        return nil
    }

    var address: UInt32 = 0

    for part in parts {
        guard let octet = parseIPv4Octet(String(part)) else {
            return nil
        }

        address = (address << 8) | UInt32(octet)
    }

    return address
}

private func parseIPv4Octet(_ rawValue: String) -> UInt8? {
    guard !rawValue.isEmpty, rawValue.count <= 3 else {
        return nil
    }

    if rawValue.hasPrefix("0") && !cedarStringEqual(rawValue, "0") {
        return nil
    }

    guard let value = parseDecimalNat(rawValue), value <= 0xFF else {
        return nil
    }

    return UInt8(value)
}

private func parseIPv6Segments(_ rawValue: String) -> [UInt16]? {
    let characters = Array(rawValue)
    var gapIndex: Int?
    var index = 0

    while index + 1 < characters.count {
        if characters[index] == ":", characters[index + 1] == ":" {
            guard gapIndex == nil else {
                return nil
            }

            gapIndex = index
            index += 2
            continue
        }

        index += 1
    }

    if let gapIndex {
        let left = String(characters[..<gapIndex])
        let right = String(characters[(gapIndex + 2)...])

        guard let leftSegments = parseIPv6SegmentList(left), let rightSegments = parseIPv6SegmentList(right) else {
            return nil
        }

        let explicitCount = leftSegments.count + rightSegments.count
        guard explicitCount < 8 else {
            return nil
        }

        return leftSegments + Array(repeating: 0, count: 8 - explicitCount) + rightSegments
    }

    guard let segments = parseIPv6SegmentList(rawValue), segments.count == 8 else {
        return nil
    }

    return segments
}

private func parseIPv6SegmentList(_ rawValue: String) -> [UInt16]? {
    if rawValue.isEmpty {
        return []
    }

    var segments: [UInt16] = []

    for part in rawValue.split(separator: ":", omittingEmptySubsequences: false) {
        guard let value = parseIPv6Segment(String(part)) else {
            return nil
        }

        segments.append(value)
    }

    return segments
}

private func parseIPv6Segment(_ rawValue: String) -> UInt16? {
    guard !rawValue.isEmpty, rawValue.count <= 4 else {
        return nil
    }

    var value: UInt16 = 0

    for scalar in rawValue.unicodeScalars {
        guard let digit = hexValue(of: scalar) else {
            return nil
        }

        value = value * 16 + UInt16(digit)
    }

    return value
}

private func parseDecimalNat(_ rawValue: String) -> Int? {
    guard !rawValue.isEmpty else {
        return nil
    }

    var value = 0

    for scalar in rawValue.unicodeScalars {
        guard scalar.value >= 48, scalar.value <= 57 else {
            return nil
        }

        value = value * 10 + Int(scalar.value - 48)
    }

    return value
}

private func hexValue(of scalar: UnicodeScalar) -> UInt32? {
    switch scalar.value {
    case 48 ... 57:
        return scalar.value - 48
    case 65 ... 70:
        return scalar.value - 65 + 10
    case 97 ... 102:
        return scalar.value - 97 + 10
    default:
        return nil
    }
}

private func ipaddrParsedLess(_ lhs: IPAddrParsed, _ rhs: IPAddrParsed) -> Bool {
    switch (lhs, rhs) {
    case let (.v4(leftAddress, leftPrefix), .v4(rightAddress, rightPrefix)):
        if leftAddress != rightAddress {
            return leftAddress < rightAddress
        }

        return leftPrefix < rightPrefix
    case let (.v6(leftSegments, leftPrefix), .v6(rightSegments, rightPrefix)):
        for (left, right) in zip(leftSegments, rightSegments) {
            if left != right {
                return left < right
            }
        }

        return leftPrefix < rightPrefix
    case (.v4, .v6):
        return true
    case (.v6, .v4):
        return false
    }
}

internal func ipaddrInRange(_ lhs: IPAddrParsed, _ rhs: IPAddrParsed) -> Bool {
    switch (lhs, rhs) {
    case let (.v4(leftAddress, leftPrefix), .v4(rightAddress, rightPrefix)):
        return leftPrefix >= rightPrefix
            && maskIPv4(leftAddress, prefix: rightPrefix) == maskIPv4(rightAddress, prefix: rightPrefix)
    case let (.v6(leftSegments, leftPrefix), .v6(rightSegments, rightPrefix)):
        return leftPrefix >= rightPrefix
            && maskIPv6(leftSegments, prefix: rightPrefix) == maskIPv6(rightSegments, prefix: rightPrefix)
    case (.v4, .v6), (.v6, .v4):
        return false
    }
}

private func hashIPAddrParsed(_ value: IPAddrParsed, into hasher: inout Hasher) {
    switch value {
    case let .v4(address, prefix):
        hasher.combine(0)
        hasher.combine(address)
        hasher.combine(prefix)
    case let .v6(segments, prefix):
        hasher.combine(1)
        hasher.combine(segments.count)
        for segment in segments {
            hasher.combine(segment)
        }
        hasher.combine(prefix)
    }
}

private func maskIPv4(_ address: UInt32, prefix: Int) -> UInt32 {
    if prefix == 0 {
        return 0
    }

    if prefix == 32 {
        return address
    }

    let mask = UInt32.max << UInt32(32 - prefix)
    return address & mask
}

private func maskIPv6(_ segments: [UInt16], prefix: Int) -> [UInt16] {
    var remaining = prefix
    var masked: [UInt16] = []
    masked.reserveCapacity(segments.count)

    for segment in segments {
        if remaining >= 16 {
            masked.append(segment)
            remaining -= 16
            continue
        }

        if remaining <= 0 {
            masked.append(0)
            continue
        }

        let mask = UInt16.max << (16 - remaining)
        masked.append(segment & mask)
        remaining = 0
    }

    return masked
}
