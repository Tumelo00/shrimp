import Foundation
import Darwin

/// Wake-on-LAN magic packet — ham UDP + SO_BROADCAST.
/// ÖNEMLİ: Paketi FİZİKSEL arayüze (en0/en1) `IP_BOUND_IF` ile bağlar → Tailscale'in
/// `utun` arayüzünü BYPASS eder. (Aksi halde broadcast Tailscale'den çıkıp LAN'a ulaşmaz.)
/// KOŞUL: PC ile Mac aynı L2 ağda; PC'de WOL açık; hedef KALICI MAC.
/// (Farklı ağdan/uzaktan çalışmaz — broadcast internet/Tailscale'den geçmez.)
enum WakeOnLan {
    struct Phys { let name: String; let index: UInt32; let broadcast: String }

    static func sendAll(mac: String, lanIP: String?) {
        guard let macBytes = parseMAC(mac) else { return }
        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: macBytes) }

        let ifaces = physicalInterfaces()
        // 1) Her FİZİKSEL arayüzden gönder (Tailscale bypass — asıl düzeltme)
        for f in ifaces {
            for _ in 0..<3 {
                send(packet, to: "255.255.255.255", port: 9, boundTo: f.index)
                send(packet, to: f.broadcast,       port: 9, boundTo: f.index)
                send(packet, to: f.broadcast,       port: 7, boundTo: f.index)
            }
        }
        // 2) PC'nin bilinen subnet broadcast'ini de her fiziksel arayüzden dene
        if let lanIP, let sub = subnetBroadcast(lanIP) {
            for f in ifaces { send(packet, to: sub, port: 9, boundTo: f.index); send(packet, to: sub, port: 7, boundTo: f.index) }
        }
        // 3) Hiç fiziksel arayüz bulunamadıysa route'a bırak (bağlanmadan)
        if ifaces.isEmpty {
            send(packet, to: "255.255.255.255", port: 9, boundTo: 0)
            if let lanIP, let sub = subnetBroadcast(lanIP) { send(packet, to: sub, port: 9, boundTo: 0) }
        }
    }

    static func send(_ packet: [UInt8], to broadcast: String, port: UInt16, boundTo ifIndex: UInt32) {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        if fd < 0 { return }
        defer { close(fd) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        // Tailscale bypass: paketi bu fiziksel arayüzden çıkmaya zorla
        if ifIndex > 0 {
            var idx = ifIndex
            setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &idx, socklen_t(MemoryLayout<UInt32>.size))
        }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr(broadcast)

        _ = packet.withUnsafeBytes { buf in
            withUnsafePointer(to: &addr) { aptr in
                aptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(fd, buf.baseAddress, buf.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    /// Fiziksel (utun/Tailscale olmayan), UP + broadcast destekli IPv4 arayüzleri.
    static func physicalInterfaces() -> [Phys] {
        var out: [Phys] = []
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0 else { return out }
        defer { freeifaddrs(ifap) }
        var p = ifap
        while let cur = p {
            let ifa = cur.pointee
            p = ifa.ifa_next
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(ifa.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0, (flags & IFF_BROADCAST) != 0 else { continue }
            let name = String(cString: ifa.ifa_name)
            // sanal/tünel arayüzleri ele (Tailscale = utun)
            if ["utun", "tun", "tap", "ppp", "ipsec", "llw", "awdl"].contains(where: { name.hasPrefix($0) }) { continue }
            // broadcast adresi: ifa_dstaddr (broadcast arayüzlerde broadcast'i tutar)
            var bcast = "255.255.255.255"
            if let dst = ifa.ifa_dstaddr, let s = ipString(dst), !s.isEmpty, s != "0.0.0.0" { bcast = s }
            else if let mask = ifa.ifa_netmask { bcast = directed(ip: addr, mask: mask) }
            out.append(Phys(name: name, index: if_nametoindex(ifa.ifa_name), broadcast: bcast))
        }
        return out
    }

    private static func ipString(_ sa: UnsafeMutablePointer<sockaddr>) -> String? {
        guard sa.pointee.sa_family == UInt8(AF_INET) else { return nil }
        return sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
            let a = sin.pointee.sin_addr.s_addr
            return "\(a & 0xff).\((a >> 8) & 0xff).\((a >> 16) & 0xff).\((a >> 24) & 0xff)"
        }
    }

    private static func directed(ip: UnsafeMutablePointer<sockaddr>, mask: UnsafeMutablePointer<sockaddr>) -> String {
        let ipv = ip.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
        let mv = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
        let b = ipv | ~mv
        return "\(b & 0xff).\((b >> 8) & 0xff).\((b >> 16) & 0xff).\((b >> 24) & 0xff)"
    }

    private static func parseMAC(_ mac: String) -> [UInt8]? {
        let parts = mac.split(whereSeparator: { $0 == ":" || $0 == "-" })
        guard parts.count == 6 else { return nil }
        var bytes = [UInt8]()
        for p in parts { guard let b = UInt8(p, radix: 16) else { return nil }; bytes.append(b) }
        return bytes
    }

    /// 192.168.31.62 → 192.168.31.255 (/24 varsayımı)
    private static func subnetBroadcast(_ ip: String) -> String? {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        return "\(parts[0]).\(parts[1]).\(parts[2]).255"
    }
}
