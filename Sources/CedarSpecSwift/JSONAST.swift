import Foundation

internal struct JSONObjectEntry: Sendable {
    let key: String
    let keySpan: SourceSpan
    let value: JSONValue
}

internal indirect enum JSONValue: Sendable {
    case object([JSONObjectEntry], SourceSpan)
    case array([JSONValue], SourceSpan)
    case string(String, SourceSpan)
    case number(String, SourceSpan)
    case bool(Bool, SourceSpan)
    case null(SourceSpan)

    var sourceSpan: SourceSpan {
        switch self {
        case let .object(_, span), let .array(_, span), let .string(_, span), let .number(_, span), let .bool(_, span), let .null(span):
            return span
        }
    }
}

private enum JSONASCII {
    static let openBrace: UInt8 = 0x7B
    static let closeBrace: UInt8 = 0x7D
    static let openBracket: UInt8 = 0x5B
    static let closeBracket: UInt8 = 0x5D
    static let quote: UInt8 = 0x22
    static let comma: UInt8 = 0x2C
    static let colon: UInt8 = 0x3A
    static let backslash: UInt8 = 0x5C
    static let slash: UInt8 = 0x2F
    static let minus: UInt8 = 0x2D
    static let plus: UInt8 = 0x2B
    static let dot: UInt8 = 0x2E
    static let zero: UInt8 = 0x30
    static let nine: UInt8 = 0x39
    static let lowerA: UInt8 = 0x61
    static let lowerB: UInt8 = 0x62
    static let lowerE: UInt8 = 0x65
    static let lowerF: UInt8 = 0x66
    static let lowerN: UInt8 = 0x6E
    static let lowerR: UInt8 = 0x72
    static let lowerT: UInt8 = 0x74
    static let lowerU: UInt8 = 0x75
    static let upperA: UInt8 = 0x41
    static let upperE: UInt8 = 0x45
    static let upperF: UInt8 = 0x46
    static let whitespaceSpace: UInt8 = 0x20
    static let whitespaceTab: UInt8 = 0x09
    static let whitespaceLineFeed: UInt8 = 0x0A
    static let whitespaceCarriageReturn: UInt8 = 0x0D
}

internal struct JSONParser {
    private enum Storage {
        case string(String)
        case data(Data)
    }

    private let sourceName: String?
    private let maxDepth: Int
    private let storage: Storage

    init(source: String, sourceName: String?, maxDepth: Int) {
        self.sourceName = sourceName
        self.maxDepth = maxDepth
        storage = .string(source)
    }

    init(data: Data, sourceName: String?, maxDepth: Int) {
        self.sourceName = sourceName
        self.maxDepth = maxDepth
        storage = .data(data)
    }

    mutating func parse() -> Result<JSONValue, Diagnostic> {
        switch storage {
        case let .string(source):
            var source = source
            return source.withUTF8 { utf8 in
                var parser = BorrowedJSONParser(
                    sourceName: sourceName,
                    maxDepth: maxDepth,
                    bytes: UnsafeBufferPointer(start: utf8.baseAddress, count: utf8.count)
                )
                return parser.parse()
            }
        case let .data(data):
            return data.withUnsafeBytes { rawBuffer in
                let bytes = rawBuffer.bindMemory(to: UInt8.self)
                var parser = BorrowedJSONParser(
                    sourceName: sourceName,
                    maxDepth: maxDepth,
                    bytes: UnsafeBufferPointer(start: bytes.baseAddress, count: bytes.count)
                )
                return parser.parse()
            }
        }
    }
}

private struct BorrowedJSONParser {
    private let sourceName: String?
    private let maxDepth: Int
    private let bytes: UnsafeBufferPointer<UInt8>
    private var index: Int = 0
    private var offset: Int = 0
    private var line: Int = 1
    private var column: Int = 1

    init(sourceName: String?, maxDepth: Int, bytes: UnsafeBufferPointer<UInt8>) {
        self.sourceName = sourceName
        self.maxDepth = maxDepth
        self.bytes = bytes
    }

    mutating func parse() -> Result<JSONValue, Diagnostic> {
        skipWhitespace()

        switch parseValue(depth: 1) {
        case let .success(value):
            skipWhitespace()
            guard isAtEnd else {
                return .failure(makeDiagnostic(
                    code: "json.trailingCharacters",
                    message: "Unexpected trailing characters after JSON value"
                ))
            }

            return .success(value)
        case let .failure(diagnostic):
            return .failure(diagnostic)
        }
    }

    private var isAtEnd: Bool {
        index >= bytes.count
    }

    private mutating func parseValue(depth: Int) -> Result<JSONValue, Diagnostic> {
        guard depth <= maxDepth else {
            return .failure(makeDiagnostic(
                code: "json.depthLimitExceeded",
                message: "JSON nesting exceeds the configured depth limit"
            ))
        }

        guard let byte = peekByte() else {
            return .failure(makeDiagnostic(code: "json.unexpectedEOF", message: "Unexpected end of JSON input"))
        }

        switch byte {
        case JSONASCII.openBrace:
            return parseObject(depth: depth)
        case JSONASCII.openBracket:
            return parseArray(depth: depth)
        case JSONASCII.quote:
            return parseJSONString().map { .string($0.value, $0.span) }
        case JSONASCII.lowerT:
            return parseKeyword("true", value: { .bool(true, $0) })
        case JSONASCII.lowerF:
            return parseKeyword("false", value: { .bool(false, $0) })
        case JSONASCII.lowerN:
            return parseKeyword("null", value: { .null($0) })
        case JSONASCII.minus, JSONASCII.zero...JSONASCII.nine:
            return parseNumber().map { .number($0.value, $0.span) }
        default:
            return .failure(makeDiagnostic(code: "json.invalidCharacter", message: "Unexpected character in JSON input"))
        }
    }

    private mutating func parseObject(depth: Int) -> Result<JSONValue, Diagnostic> {
        let start = location()
        advanceASCII()
        skipWhitespace()

        var entries: [JSONObjectEntry] = []

        if consumeIf(JSONASCII.closeBrace) {
            return .success(.object(entries, span(from: start)))
        }

        while true {
            guard case let .success((key, keySpan)) = parseJSONString() else {
                return .failure(makeDiagnostic(code: "json.objectKeyExpected", message: "Expected a JSON object key string"))
            }

            skipWhitespace()
            guard consumeIf(JSONASCII.colon) else {
                return .failure(makeDiagnostic(code: "json.colonExpected", message: "Expected ':' after object key"))
            }

            skipWhitespace()
            switch parseValue(depth: depth + 1) {
            case let .success(value):
                entries.append(JSONObjectEntry(key: key, keySpan: keySpan, value: value))
            case let .failure(diagnostic):
                return .failure(diagnostic)
            }

            skipWhitespace()
            if consumeIf(JSONASCII.closeBrace) {
                return .success(.object(entries, span(from: start)))
            }

            guard consumeIf(JSONASCII.comma) else {
                return .failure(makeDiagnostic(code: "json.commaExpected", message: "Expected ',' between object members"))
            }

            skipWhitespace()
        }
    }

    private mutating func parseArray(depth: Int) -> Result<JSONValue, Diagnostic> {
        let start = location()
        advanceASCII()
        skipWhitespace()

        var values: [JSONValue] = []

        if consumeIf(JSONASCII.closeBracket) {
            return .success(.array(values, span(from: start)))
        }

        while true {
            switch parseValue(depth: depth + 1) {
            case let .success(value):
                values.append(value)
            case let .failure(diagnostic):
                return .failure(diagnostic)
            }

            skipWhitespace()
            if consumeIf(JSONASCII.closeBracket) {
                return .success(.array(values, span(from: start)))
            }

            guard consumeIf(JSONASCII.comma) else {
                return .failure(makeDiagnostic(code: "json.commaExpected", message: "Expected ',' between array elements"))
            }

            skipWhitespace()
        }
    }

    private mutating func parseJSONString() -> Result<(value: String, span: SourceSpan), Diagnostic> {
        guard consumeIf(JSONASCII.quote) else {
            return .failure(makeDiagnostic(code: "json.stringExpected", message: "Expected a JSON string"))
        }

        let start = location(beforeCurrent: true)
        var result = ""
        var segmentStart = index

        while let byte = peekByte() {
            switch byte {
            case JSONASCII.quote:
                if result.isEmpty, segmentStart == index || segmentStart < index {
                    let decoded = decodedString(from: segmentStart, to: index)
                    advanceASCII()
                    return .success((decoded, span(from: start)))
                }

                appendStringSegment(from: segmentStart, to: index, into: &result)
                advanceASCII()
                return .success((result, span(from: start)))
            case JSONASCII.backslash:
                appendStringSegment(from: segmentStart, to: index, into: &result)
                advanceASCII()

                guard let escaped = peekByte() else {
                    return .failure(makeDiagnostic(code: "json.unterminatedString", message: "Unterminated JSON string"))
                }

                advanceASCII()
                switch escaped {
                case JSONASCII.quote, JSONASCII.backslash, JSONASCII.slash:
                    result.unicodeScalars.append(Unicode.Scalar(UInt32(escaped))!)
                case JSONASCII.lowerB:
                    result.append("\u{0008}")
                case JSONASCII.lowerF:
                    result.append("\u{000C}")
                case JSONASCII.lowerN:
                    result.append("\n")
                case JSONASCII.lowerR:
                    result.append("\r")
                case JSONASCII.lowerT:
                    result.append("\t")
                case JSONASCII.lowerU:
                    switch parseUnicodeEscape() {
                    case let .success(decoded):
                        result.unicodeScalars.append(decoded)
                    case let .failure(diagnostic):
                        return .failure(diagnostic)
                    }
                default:
                    return .failure(makeDiagnostic(code: "json.invalidEscape", message: "Invalid JSON string escape sequence"))
                }

                segmentStart = index
            case 0x00..<0x20:
                return .failure(makeDiagnostic(code: "json.invalidCharacter", message: "Control characters must be escaped in JSON strings"))
            case 0x80...:
                switch advanceUTF8Scalar() {
                case .success:
                    continue
                case let .failure(diagnostic):
                    return .failure(diagnostic)
                }
            default:
                advanceASCII()
            }
        }

        return .failure(makeDiagnostic(code: "json.unterminatedString", message: "Unterminated JSON string"))
    }

    private mutating func parseUnicodeEscape() -> Result<Unicode.Scalar, Diagnostic> {
        var value: UInt32 = 0

        for _ in 0..<4 {
            guard let byte = peekByte() else {
                return .failure(makeDiagnostic(code: "json.invalidEscape", message: "Incomplete unicode escape in JSON string"))
            }

            advanceASCII()
            guard let digit = hexDigitValue(for: byte) else {
                return .failure(makeDiagnostic(code: "json.invalidEscape", message: "Invalid unicode escape in JSON string"))
            }

            value = (value << 4) | UInt32(digit)
        }

        guard let decoded = Unicode.Scalar(value) else {
            return .failure(makeDiagnostic(code: "json.invalidEscape", message: "Invalid unicode scalar in JSON string"))
        }

        return .success(decoded)
    }

    private mutating func parseNumber() -> Result<(value: String, span: SourceSpan), Diagnostic> {
        let start = location()
        let startIndex = index

        _ = consumeIf(JSONASCII.minus)

        guard let firstDigit = peekByte() else {
            return .failure(makeDiagnostic(code: "json.invalidNumber", message: "Invalid JSON number"))
        }

        switch firstDigit {
        case JSONASCII.zero:
            advanceASCII()
        case 0x31...JSONASCII.nine:
            while let digit = peekByte(), isDigit(digit) {
                advanceASCII()
            }
        default:
            return .failure(makeDiagnostic(code: "json.invalidNumber", message: "Invalid JSON number"))
        }

        if consumeIf(JSONASCII.dot) {
            guard let digit = peekByte(), isDigit(digit) else {
                return .failure(makeDiagnostic(code: "json.invalidNumber", message: "Invalid JSON number"))
            }

            while let digit = peekByte(), isDigit(digit) {
                advanceASCII()
            }
        }

        if let byte = peekByte(), byte == JSONASCII.lowerE || byte == JSONASCII.upperE {
            advanceASCII()

            if let sign = peekByte(), sign == JSONASCII.plus || sign == JSONASCII.minus {
                advanceASCII()
            }

            guard let exponentDigit = peekByte(), isDigit(exponentDigit) else {
                return .failure(makeDiagnostic(code: "json.invalidNumber", message: "Invalid JSON number"))
            }

            while let digit = peekByte(), isDigit(digit) {
                advanceASCII()
            }
        }

        let raw = String(decoding: bytes[startIndex..<index], as: UTF8.self)
        return .success((raw, span(from: start)))
    }

    private mutating func parseKeyword(
        _ keyword: String,
        value constructor: (SourceSpan) -> JSONValue
    ) -> Result<JSONValue, Diagnostic> {
        let start = location()

        for expected in keyword.utf8 {
            guard peekByte() == expected else {
                return .failure(makeDiagnostic(code: "json.invalidCharacter", message: "Unexpected token in JSON input"))
            }

            advanceASCII()
        }

        return .success(constructor(span(from: start)))
    }

    private func peekByte(offset: Int = 0) -> UInt8? {
        let candidateIndex = index + offset
        guard candidateIndex >= 0, candidateIndex < bytes.count else {
            return nil
        }

        return bytes[candidateIndex]
    }

    private mutating func advanceASCII() {
        guard index < bytes.count else {
            return
        }

        let byte = bytes[index]
        index += 1
        offset += 1

        if byte == JSONASCII.whitespaceLineFeed {
            line += 1
            column = 1
        } else {
            column += 1
        }
    }

    private mutating func advanceUTF8Scalar() -> Result<Void, Diagnostic> {
        guard let (_, length) = decodeUTF8Scalar(at: index) else {
            return .failure(makeInvalidUTF8Diagnostic())
        }

        index += length
        offset += 1
        column += 1
        return .success(())
    }

    private mutating func skipWhitespace() {
        while let byte = peekByte() {
            switch byte {
            case JSONASCII.whitespaceSpace, JSONASCII.whitespaceTab, JSONASCII.whitespaceLineFeed, JSONASCII.whitespaceCarriageReturn:
                advanceASCII()
            default:
                return
            }
        }
    }

    private mutating func consumeIf(_ expected: UInt8) -> Bool {
        guard peekByte() == expected else {
            return false
        }

        advanceASCII()
        return true
    }

    private func location(beforeCurrent: Bool = false) -> SourceLocation {
        if beforeCurrent {
            return SourceLocation(line: line, column: max(column - 1, 1), offset: max(offset - 1, 0))
        }

        return SourceLocation(line: line, column: column, offset: offset)
    }

    private func span(from start: SourceLocation) -> SourceSpan {
        SourceSpan(start: start, end: location(), source: sourceName)
    }

    private func makeDiagnostic(code: String, message: String) -> Diagnostic {
        Diagnostic(
            code: code,
            category: .parse,
            severity: .error,
            message: message,
            sourceSpan: SourceSpan(start: location(), end: location(), source: sourceName)
        )
    }

    private func makeInvalidUTF8Diagnostic() -> Diagnostic {
        Diagnostic(
            code: "io.invalidUTF8",
            category: .io,
            severity: .error,
            message: "Input data is not valid UTF-8",
            sourceSpan: SourceSpan(start: location(), end: location(), source: sourceName)
        )
    }

    private func appendStringSegment(from start: Int, to end: Int, into result: inout String) {
        guard start < end else {
            return
        }

        result.append(decodedString(from: start, to: end))
    }

    private func decodedString(from start: Int, to end: Int) -> String {
        String(decoding: bytes[start..<end], as: UTF8.self)
    }

    private func decodeUTF8Scalar(at index: Int) -> (Unicode.Scalar, Int)? {
        guard index < bytes.count else {
            return nil
        }

        let leading = bytes[index]
        if leading < 0x80 {
            return (Unicode.Scalar(UInt32(leading))!, 1)
        }

        func continuationByte(at index: Int) -> UInt8? {
            guard index < bytes.count else {
                return nil
            }

            let byte = bytes[index]
            guard (byte & 0b1100_0000) == 0b1000_0000 else {
                return nil
            }

            return byte
        }

        if (leading & 0b1110_0000) == 0b1100_0000 {
            guard let trailing = continuationByte(at: index + 1) else {
                return nil
            }

            let scalarValue = (UInt32(leading & 0b0001_1111) << 6) | UInt32(trailing & 0b0011_1111)
            guard scalarValue >= 0x80, let scalar = Unicode.Scalar(scalarValue) else {
                return nil
            }

            return (scalar, 2)
        }

        if (leading & 0b1111_0000) == 0b1110_0000 {
            guard let second = continuationByte(at: index + 1),
                  let third = continuationByte(at: index + 2)
            else {
                return nil
            }

            let scalarValue = (UInt32(leading & 0b0000_1111) << 12)
                | (UInt32(second & 0b0011_1111) << 6)
                | UInt32(third & 0b0011_1111)
            guard scalarValue >= 0x800,
                  !(0xD800...0xDFFF).contains(scalarValue),
                  let scalar = Unicode.Scalar(scalarValue)
            else {
                return nil
            }

            return (scalar, 3)
        }

        if (leading & 0b1111_1000) == 0b1111_0000 {
            guard let second = continuationByte(at: index + 1),
                  let third = continuationByte(at: index + 2),
                  let fourth = continuationByte(at: index + 3)
            else {
                return nil
            }

            let scalarValue = (UInt32(leading & 0b0000_0111) << 18)
                | (UInt32(second & 0b0011_1111) << 12)
                | (UInt32(third & 0b0011_1111) << 6)
                | UInt32(fourth & 0b0011_1111)
            guard (0x10000...0x10FFFF).contains(scalarValue),
                  let scalar = Unicode.Scalar(scalarValue)
            else {
                return nil
            }

            return (scalar, 4)
        }

        return nil
    }
}

private func isDigit(_ byte: UInt8) -> Bool {
    (JSONASCII.zero...JSONASCII.nine).contains(byte)
}

private func hexDigitValue(for byte: UInt8) -> Int? {
    switch byte {
    case JSONASCII.zero...JSONASCII.nine:
        return Int(byte - JSONASCII.zero)
    case JSONASCII.lowerA...JSONASCII.lowerF:
        return Int(byte - JSONASCII.lowerA) + 10
    case JSONASCII.upperA...JSONASCII.upperF:
        return Int(byte - JSONASCII.upperA) + 10
    default:
        return nil
    }
}
