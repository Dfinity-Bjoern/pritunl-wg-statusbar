import Foundation

private let statusPath = "/var/run/pritunl-wg.status"
private let staleInterval: TimeInterval = 300

class StatusManager {
    var onChanged: ((VPNStatus) -> Void)?
    private(set) var status: VPNStatus = .unknown
    private var timer: Timer?

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        let next = readStatus()
        if next != status {
            status = next
            DispatchQueue.main.async { self.onChanged?(next) }
        }
    }

    private func readStatus() -> VPNStatus {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: statusPath)),
              let parsed = VPNStatus.parse(data)
        else { return .unknown }

        // Mark stale if not updated recently
        if let updated = parsed.updatedAt,
           parsed.state != .disconnected,
           Date().timeIntervalSince(updated) > staleInterval {
            return VPNStatus(
                state: .disconnected,
                rawState: "stale",
                server: parsed.server,
                address: nil,
                since: nil,
                lastKeepalive: parsed.lastKeepalive,
                errorMsg: "Service not responding",
                updatedAt: parsed.updatedAt
            )
        }
        return parsed
    }
}
