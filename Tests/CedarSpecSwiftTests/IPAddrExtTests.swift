import XCTest
@testable import CedarSpecSwift

final class IPAddrExtTests: XCTestCase {
    func testIPAddrParseMatchesLeanCanonicalRenderingAndPrefixDefaults() throws {
        XCTAssertEqual(try XCTUnwrap(ipaddrParse("192.168.0.1/32")).canonicalString, "192.168.0.1/32")
        XCTAssertEqual(try XCTUnwrap(ipaddrParse("127.0.0.1")).canonicalString, "127.0.0.1/32")
        XCTAssertEqual(try XCTUnwrap(ipaddrParse("1:2:3:4:a:b:c:d/128")).canonicalString, "0001:0002:0003:0004:000a:000b:000c:000d/128")
        XCTAssertEqual(try XCTUnwrap(ipaddrParse("7:70:700:7000::a00/128")).canonicalString, "0007:0070:0700:7000:0000:0000:0000:0a00/128")
        XCTAssertEqual(try XCTUnwrap(ipaddrParse("::")).canonicalString, "0000:0000:0000:0000:0000:0000:0000:0000/128")
        XCTAssertEqual(try XCTUnwrap(ipaddrParse("ffff::/4")).canonicalString, "ffff:0000:0000:0000:0000:0000:0000:0000/4")
    }

    func testIPAddrParseRejectsMalformedInputsAndEmbeddedIPv4InIPv6() {
        XCTAssertNil(ipaddrParse("127.0.0.1."))
        XCTAssertNil(ipaddrParse(".127.0.0.1"))
        XCTAssertNil(ipaddrParse("127.0..0.1"))
        XCTAssertNil(ipaddrParse("256.0.0.1"))
        XCTAssertNil(ipaddrParse("127.0.a.1"))
        XCTAssertNil(ipaddrParse("127.3.4.1/33"))
        XCTAssertNil(ipaddrParse("::::"))
        XCTAssertNil(ipaddrParse("::f::"))
        XCTAssertNil(ipaddrParse("F:AE::F:5:F:F:0:0"))
        XCTAssertNil(ipaddrParse("F:A:F:5:F:F:0:0:1"))
        XCTAssertNil(ipaddrParse("F:A"))
        XCTAssertNil(ipaddrParse("::ffff1"))
        XCTAssertNil(ipaddrParse("F:AE::F:5:F:F:0/129"))
        XCTAssertNil(ipaddrParse("::ffff:127.0.0.1"))
        XCTAssertNil(ipaddrParse("::/00"))
        XCTAssertNil(ipaddrParse("127.0.0.1/01"))
    }

    func testIPAddrInvalidDirectPayloadFallbacksRemainDeterministicAcrossPublicSemanticSurfaces() {
        let valid = Ext.IPAddr(rawValue: "127.0.0.1")
        let invalid = Ext.IPAddr(rawValue: "127.0.0.1/01")
        let invalidAlias = Ext.IPAddr(rawValue: "127.0.0.1/01")

        XCTAssertEqual(Ext.ipaddr(invalid), Ext.ipaddr(invalidAlias))
        XCTAssertEqual(CedarValue.ext(.ipaddr(invalid)), CedarValue.ext(.ipaddr(invalidAlias)))
        XCTAssertLessThan(Ext.ipaddr(valid), Ext.ipaddr(invalid))
        XCTAssertLessThan(CedarValue.ext(.ipaddr(valid)), CedarValue.ext(.ipaddr(invalid)))

        let set = CedarSet.make([
            CedarValue.ext(.ipaddr(invalid)),
            CedarValue.ext(.ipaddr(valid)),
            CedarValue.ext(.ipaddr(invalidAlias)),
        ])
        let map = CedarMap.make([
            (key: "beta", value: CedarValue.ext(.ipaddr(invalid))),
            (key: "alpha", value: CedarValue.ext(.ipaddr(valid))),
        ])

        XCTAssertEqual(set.elements, [
            CedarValue.ext(.ipaddr(valid)),
            CedarValue.ext(.ipaddr(invalid)),
        ])
        XCTAssertEqual(map.entries.map(\.key), ["alpha", "beta"])
        XCTAssertEqual(map.find("beta"), .ext(.ipaddr(invalid)))
    }

    func testIPAddrDispatchCoversConstructorPredicatesRangesAndReferenceEdgeCases() {
        XCTAssertEqual(
            dispatchExtensionCall(.ip, arguments: [.prim(.string("127.0.0.1"))]),
            .success(.ext(.ipaddr(.init(rawValue: "127.0.0.1"))))
        )
        XCTAssertEqual(
            dispatchExtensionCall(.ip, arguments: [.prim(.string("::ffff:127.0.0.1"))]),
            .failure(.extensionError)
        )
        XCTAssertEqual(
            dispatchExtensionCall(.ip, arguments: []),
            .failure(.typeError)
        )
        XCTAssertEqual(
            dispatchExtensionCall(.ip, arguments: [.prim(.int(1))]),
            .failure(.typeError)
        )

        XCTAssertEqual(
            dispatchExtensionCall(.isIpv4, arguments: [.ext(.ipaddr(.init(rawValue: "127.0.0.1")))]),
            .success(.prim(.bool(true)))
        )
        XCTAssertEqual(
            dispatchExtensionCall(.isIpv6, arguments: [.ext(.ipaddr(.init(rawValue: "::1")))]),
            .success(.prim(.bool(true)))
        )
        XCTAssertEqual(
            dispatchExtensionCall(.isLoopback, arguments: [.ext(.ipaddr(.init(rawValue: "127.0.0.1")))]),
            .success(.prim(.bool(true)))
        )
        XCTAssertEqual(
            dispatchExtensionCall(.isLoopback, arguments: [.ext(.ipaddr(.init(rawValue: "::B")))]),
            .success(.prim(.bool(false)))
        )
        XCTAssertEqual(
            dispatchExtensionCall(.isMulticast, arguments: [.ext(.ipaddr(.init(rawValue: "238.238.238.238")))]),
            .success(.prim(.bool(true)))
        )
        XCTAssertEqual(
            dispatchExtensionCall(.isMulticast, arguments: [.ext(.ipaddr(.init(rawValue: "ff00::1")))]),
            .success(.prim(.bool(true)))
        )

        XCTAssertEqual(
            dispatchExtensionCall(
                .isInRange,
                arguments: [
                    .ext(.ipaddr(.init(rawValue: "238.238.238.238"))),
                    .ext(.ipaddr(.init(rawValue: "238.238.238.41/12"))),
                ]
            ),
            .success(.prim(.bool(true)))
        )
        XCTAssertEqual(
            dispatchExtensionCall(
                .isInRange,
                arguments: [
                    .ext(.ipaddr(.init(rawValue: "0.0.0.0"))),
                    .ext(.ipaddr(.init(rawValue: "::"))),
                ]
            ),
            .success(.prim(.bool(false)))
        )
        XCTAssertEqual(
            dispatchExtensionCall(
                .isInRange,
                arguments: [
                    .ext(.ipaddr(.init(rawValue: "10.0.0.0/24"))),
                    .ext(.ipaddr(.init(rawValue: "10.0.0.0/32"))),
                ]
            ),
            .success(.prim(.bool(false)))
        )
        XCTAssertEqual(
            dispatchExtensionCall(
                .isInRange,
                arguments: [
                    .ext(.ipaddr(.init(rawValue: "10.0.0.0/32"))),
                    .ext(.ipaddr(.init(rawValue: "10.0.0.0"))),
                ]
            ),
            .success(.prim(.bool(true)))
        )
        XCTAssertEqual(
            dispatchExtensionCall(
                .isInRange,
                arguments: [
                    .ext(.ipaddr(.init(rawValue: "0.0.0.0/31"))),
                    .ext(.ipaddr(.init(rawValue: "0.0.0.1/31"))),
                ]
            ),
            .success(.prim(.bool(true)))
        )
        XCTAssertEqual(
            dispatchExtensionCall(
                .isInRange,
                arguments: [
                    .ext(.ipaddr(.init(rawValue: "a::f/120"))),
                    .ext(.ipaddr(.init(rawValue: "000a:0000:0000:0000:0000:0000:0000:000f/120"))),
                ]
            ),
            .success(.prim(.bool(true)))
        )

        XCTAssertEqual(
            dispatchExtensionCall(.isIpv4, arguments: [.prim(.string("127.0.0.1"))]),
            .failure(.typeError)
        )
        XCTAssertEqual(
            dispatchExtensionCall(.isInRange, arguments: [.ext(.ipaddr(.init(rawValue: "127.0.0.1")))]),
            .failure(.typeError)
        )
    }
}

private extension IPAddrParsed {
    var canonicalString: String {
        ipaddrCanonicalString(self)
    }
}
