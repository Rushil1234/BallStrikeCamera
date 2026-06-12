import Foundation
import Network
import Darwin

/// Scans the current /24 subnet for a host with a specific TCP port open.
///
/// Used to auto-discover the PC running GSPro or OGS on any local network —
/// including when the iPhone is used as a personal hotspot (PC gets 172.20.10.x),
/// or the user is on a network where they don't know the PC's IP.
actor SimNetworkScanner {

    // MARK: - Public API

    enum ScanError: LocalizedError {
        case noLocalIP
        var errorDescription: String? {
            "Could not determine this device's local IP. Make sure Wi-Fi or hotspot is active."
        }
    }

    /// Returns IPs in the current /24 subnet that accept a TCP connection on `port`.
    /// Probes all 254 hosts concurrently; typical duration = `timeout` seconds (~0.6 s).
    func scan(port: UInt16, timeout: TimeInterval = 0.6) async throws -> [String] {
        guard let myIP = deviceLocalIP() else { throw ScanError.noLocalIP }
        let parts = myIP.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { throw ScanError.noLocalIP }
        let prefix = "\(parts[0]).\(parts[1]).\(parts[2])"

        return await withTaskGroup(of: String?.self) { group in
            for i in 1...254 {
                let host = "\(prefix).\(i)"
                group.addTask {
                    await self.probeTCP(host: host, port: port, timeout: timeout) ? host : nil
                }
            }
            var found: [String] = []
            for await result in group {
                if let ip = result { found.append(ip) }
            }
            // Sort by the final octet so results are in natural order.
            return found.sorted {
                let a = $0.split(separator: ".").last.flatMap { Int($0) } ?? 0
                let b = $1.split(separator: ".").last.flatMap { Int($0) } ?? 0
                return a < b
            }
        }
    }

    // MARK: - Private

    private func probeTCP(host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { cont in
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                cont.resume(returning: false)
                return
            }
            let conn = NWConnection(
                to: .hostPort(host: NWEndpoint.Host(host), port: nwPort),
                using: .tcp
            )
            let q = DispatchQueue(label: "scan.\(host)", qos: .utility)
            var done = false

            func finish(_ open: Bool) {
                guard !done else { return }
                done = true
                conn.stateUpdateHandler = nil
                conn.cancel()
                cont.resume(returning: open)
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:  finish(true)
                case .failed: finish(false)
                default: break
                }
            }
            conn.start(queue: q)
            q.asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
    }

    /// Returns the first non-loopback, non-link-local IPv4 address on this device.
    private func deviceLocalIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(first) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            let flags = Int32(p.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard p.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let len = socklen_t(p.pointee.ifa_addr.pointee.sa_len)
            guard getnameinfo(p.pointee.ifa_addr, len,
                              &hostname, socklen_t(hostname.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: hostname)
            guard !ip.hasPrefix("127."), !ip.hasPrefix("169.254.") else { continue }
            return ip
        }
        return nil
    }
}
