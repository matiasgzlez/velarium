import Foundation

/// Finds the LAN addresses the phone can actually reach us on.
enum NetworkInfo {

    struct Interface {
        let name: String
        let address: String
        /// Human label for the UI: "Wi-Fi", "Hotspot", "Ethernet"…
        let label: String
    }

    /// All usable IPv4 addresses, best candidate first.
    static func interfaces() -> [Interface] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var found: [Interface] = []
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            guard let sa = ptr.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let ok = getnameinfo(sa, socklen_t(sa.pointee.sa_len),
                                &host, socklen_t(host.count),
                                nil, 0, NI_NUMERICHOST)
            guard ok == 0 else { continue }

            let name = String(cString: ptr.pointee.ifa_name)
            let address = String(cString: host)
            guard !address.hasPrefix("169.254") else { continue }  // self-assigned, unreachable
            found.append(Interface(name: name, address: address, label: label(for: name)))
        }

        return found.sorted { rank($0.name) < rank($1.name) }
    }

    static var primary: Interface? { interfaces().first }

    /// en0 is Wi-Fi on every Mac shipped this decade; bridge100 is our own hotspot.
    private static func rank(_ name: String) -> Int {
        if name == "en0" { return 0 }
        if name.hasPrefix("bridge") { return 1 }
        if name.hasPrefix("en") { return 2 }
        return 3
    }

    private static func label(for name: String) -> String {
        if name == "en0" { return "Wi-Fi" }
        if name.hasPrefix("bridge") { return "Hotspot" }
        if name.hasPrefix("en") { return "Ethernet" }
        return name
    }
}
