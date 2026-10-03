// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign

package struct PortManagerEntry: Identifiable, Equatable {
    package let port: Int
    package let protocolName: String
    package let address: String
    package let pid: Int32
    package let processName: String
    package let startedAt: UInt64?
    package var id: String { "\(protocolName)-\(port)-\(pid)-\(address)" }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(port: Int, protocolName: String, address: String, pid: Int32, processName: String, startedAt: UInt64?) {
        self.port = port
        self.protocolName = protocolName
        self.address = address
        self.pid = pid
        self.processName = processName
        self.startedAt = startedAt
    }
}

package enum PortManagerSupport {
    /// Whether an lsof endpoint such as `*:3000` or `127.0.0.1:3000` is bound
    /// to every interface rather than one specific address. A wildcard bind
    /// accepts connections from other machines on the network unless a
    /// firewall stops them, so it is worth pointing out.
    package static func listensOnAllInterfaces(_ endpoint: String) -> Bool {
        guard let separator = endpoint.lastIndex(of: ":") else { return false }
        var host = endpoint[..<separator]
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = host.dropFirst().dropLast()
        }
        return host == "*" || host == "0.0.0.0" || host == "::"
    }

    package static func parseLsof(_ text: String) -> [PortManagerEntry] {
        var name = "", pid: Int32 = 0, address = "", port = 0, proto = "TCP"
        var rows: [PortManagerEntry] = []
        var seen = Set<String>()
        for line in text.split(separator: "\n").map(String.init) {
            guard let type = line.first else { continue }
            let value = String(line.dropFirst())
            switch type {
            case "p":
                pid = Int32(value) ?? 0; port = 0; address = ""
            case "c": name = value
            case "P": proto = value
            case "n":
                address = value
                guard let last = value.split(separator: ":").last, let parsed = Int(last) else {
                    port = 0
                    continue
                }
                port = parsed
                if pid > 0 && port > 0 {
                    let key = "\(proto)|\(port)|\(address)|\(pid)"
                    if seen.insert(key).inserted {
                        rows.append(.init(port: port, protocolName: proto, address: address,
                                          pid: pid, processName: name, startedAt: nil))
                    }
                }
            case "T": continue
            default: continue
            }
        }
        return rows.sorted { $0.port == $1.port ? $0.processName < $1.processName : $0.port < $1.port }
    }
}
