import AppKit
import Foundation

enum ConnectionState: Equatable {
    case connected, connecting, disconnected, error
}

struct VPNStatus: Equatable {
    let state: ConnectionState
    let rawState: String
    let server: String
    let address: String?
    let since: Date?
    let lastKeepalive: Date?
    let errorMsg: String?
    let updatedAt: Date?

    static let unknown = VPNStatus(
        state: .disconnected,
        rawState: "unknown",
        server: "",
        address: nil,
        since: nil,
        lastKeepalive: nil,
        errorMsg: nil,
        updatedAt: nil
    )

    static func parse(_ data: Data) -> VPNStatus? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let raw = json["state"] as? String ?? "disconnected"
        let state: ConnectionState
        switch raw {
        case "connected":          state = .connected
        case "connecting":         state = .connecting
        case "retrying":           state = .connecting
        case "error":              state = .error
        default:                   state = .disconnected
        }
        let since = (json["since"] as? Double).map { Date(timeIntervalSince1970: $0) }
        let keepalive = (json["last_keepalive"] as? Double).map { Date(timeIntervalSince1970: $0) }
        let updated = (json["updated"] as? Double).map { Date(timeIntervalSince1970: $0) }
        return VPNStatus(
            state: state,
            rawState: raw,
            server: json["server"] as? String ?? "",
            address: json["address"] as? String,
            since: since,
            lastKeepalive: keepalive,
            errorMsg: json["error"] as? String,
            updatedAt: updated
        )
    }

    var uptimeString: String? {
        guard let since else { return nil }
        let seconds = Int(-since.timeIntervalSinceNow)
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }
}
