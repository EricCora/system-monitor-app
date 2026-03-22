import CoreWLAN
import Darwin
import Foundation

struct NetworkContextSnapshot: Equatable {
    var activeInterface = "Unavailable"
    var ssid: String?
    var privateIPAddresses: [String] = []
    var vpnInterfaceNames: [String] = []
    var publicIPAddress: String?

    var vpnConnected: Bool { !vpnInterfaceNames.isEmpty }
    var primaryPrivateIP: String? { privateIPAddresses.first }
}

actor NetworkContextResolver {
    private var lastResolvedAt = Date.distantPast
    private var lastSnapshot = NetworkContextSnapshot()
    private let minimumRefreshInterval: TimeInterval

    init(minimumRefreshInterval: TimeInterval = 5) {
        self.minimumRefreshInterval = minimumRefreshInterval
    }

    func snapshot(interfaceRates: [NetworkInterfaceRate], now: Date = Date()) -> NetworkContextSnapshot {
        if now.timeIntervalSince(lastResolvedAt) < minimumRefreshInterval {
            return lastSnapshot
        }

        let snapshot = Self.resolve(interfaceRates: interfaceRates)
        lastResolvedAt = now
        lastSnapshot = snapshot
        return snapshot
    }

    static func resolve(
        interfaceRates: [NetworkInterfaceRate],
        interfaceAddresses: [String: [String]]? = nil,
        ssidResolver: ((String) -> String?)? = nil
    ) -> NetworkContextSnapshot {
        let activeInterface = interfaceRates.first?.interface ?? "Unavailable"
        let addresses = interfaceAddresses ?? readInterfaceAddresses()
        let privateIPs = (addresses[activeInterface] ?? []).sorted()
        let vpnInterfaces = interfaceRates
            .map(\.interface)
            .filter(Self.isVPNInterface)
            .sorted()

        return NetworkContextSnapshot(
            activeInterface: activeInterface,
            ssid: (ssidResolver ?? currentSSIDResolver)(activeInterface),
            privateIPAddresses: privateIPs,
            vpnInterfaceNames: vpnInterfaces,
            publicIPAddress: nil
        )
    }

    static func isVPNInterface(_ interface: String) -> Bool {
        let lower = interface.lowercased()
        return lower.hasPrefix("utun")
            || lower.hasPrefix("ipsec")
            || lower.hasPrefix("ppp")
            || lower.hasPrefix("wg")
            || lower.hasPrefix("tun")
    }

    private static let currentSSIDResolver: (String) -> String? = { interfaceName in
        guard let interfaces = CWWiFiClient.shared().interfaces() else {
            return nil
        }

        if let matched = interfaces.first(where: { $0.interfaceName == interfaceName }) {
            return matched.ssid()
        }

        return interfaces.first?.ssid()
    }

    private static func readInterfaceAddresses() -> [String: [String]] {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let start = addrs else {
            return [:]
        }

        defer { freeifaddrs(start) }

        var addresses: [String: [String]] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = start
        while let iface = cursor {
            let flags = Int32(iface.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            guard isUp,
                  !isLoopback,
                  let addr = iface.pointee.ifa_addr,
                  let namePointer = iface.pointee.ifa_name else {
                cursor = iface.pointee.ifa_next
                continue
            }

            let family = addr.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else {
                cursor = iface.pointee.ifa_next
                continue
            }

            let interface = String(cString: namePointer)
            if let address = formatAddress(addr) {
                addresses[interface, default: []].append(address)
            }

            cursor = iface.pointee.ifa_next
        }

        return addresses.mapValues { values in
            Array(NSOrderedSet(array: values)) as? [String] ?? values
        }
    }

    private static func formatAddress(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let length = socklen_t(address.pointee.sa_family == sa_family_t(AF_INET)
            ? MemoryLayout<sockaddr_in>.size
            : MemoryLayout<sockaddr_in6>.size)

        let result = getnameinfo(
            address,
            length,
            &hostBuffer,
            socklen_t(hostBuffer.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard result == 0 else { return nil }
        return String(cString: hostBuffer)
    }
}
