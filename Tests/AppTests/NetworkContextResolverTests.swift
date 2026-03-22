import XCTest
@testable import PulseBarApp

final class NetworkContextResolverTests: XCTestCase {
    func testVPNHeuristicRecognizesTunnelInterfaces() {
        XCTAssertTrue(NetworkContextResolver.isVPNInterface("utun4"))
        XCTAssertTrue(NetworkContextResolver.isVPNInterface("wg0"))
        XCTAssertFalse(NetworkContextResolver.isVPNInterface("en0"))
    }

    func testResolveUsesActiveInterfaceContext() {
        let snapshot = NetworkContextResolver.resolve(
            interfaceRates: [
                NetworkInterfaceRate(interface: "en0", inboundBytesPerSecond: 50, outboundBytesPerSecond: 20),
                NetworkInterfaceRate(interface: "utun4", inboundBytesPerSecond: 10, outboundBytesPerSecond: 10)
            ],
            interfaceAddresses: [
                "en0": ["192.168.1.5", "fe80::1"],
                "utun4": ["10.10.0.2"]
            ],
            ssidResolver: { interface in
                interface == "en0" ? "Office Wi-Fi" : nil
            }
        )

        XCTAssertEqual(snapshot.activeInterface, "en0")
        XCTAssertEqual(snapshot.ssid, "Office Wi-Fi")
        XCTAssertEqual(snapshot.privateIPAddresses, ["192.168.1.5", "fe80::1"])
        XCTAssertEqual(snapshot.vpnInterfaceNames, ["utun4"])
        XCTAssertNil(snapshot.publicIPAddress)
    }
}
