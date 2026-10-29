import AppKit

class MenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let statusManager: StatusManager
    private let vpnController: VPNController
    private let menu = NSMenu()
    private var logViewer: LogViewer?

    // Menu items we update dynamically
    private let headerItem       = NSMenuItem()
    private let toggleItem       = NSMenuItem()
    private let statsItem        = NSMenuItem()
    private let passwordlessItem = NSMenuItem()

    init(statusItem: NSStatusItem, statusManager: StatusManager, vpnController: VPNController) {
        self.statusItem = statusItem
        self.statusManager = statusManager
        self.vpnController = vpnController
        super.init()
        buildMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func buildMenu() {
        headerItem.isEnabled = false
        headerItem.attributedTitle = styledHeader("Disconnected")
        menu.addItem(headerItem)

        menu.addItem(.separator())

        toggleItem.title = "Connect"
        toggleItem.target = self
        toggleItem.action = #selector(toggleConnection)
        menu.addItem(toggleItem)

        statsItem.isEnabled = false
        statsItem.isHidden = true
        menu.addItem(statsItem)

        menu.addItem(.separator())

        let importItem = NSMenuItem(title: "Import Profile…", action: #selector(importProfile), keyEquivalent: "")
        importItem.target = self
        menu.addItem(importItem)

        let logItem = NSMenuItem(title: "Show Logs", action: #selector(showLogs), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        passwordlessItem.target = self
        passwordlessItem.action = #selector(enablePasswordless)
        menu.addItem(passwordlessItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    func update(status: VPNStatus) {
        statusItem.button?.image = StatusIcon.image(for: status.state)

        switch status.state {
        case .connected:
            let uptime = status.uptimeString.map { " · \($0)" } ?? ""
            let addr = status.address.map { " · \($0)" } ?? ""
            headerItem.attributedTitle = styledHeader("Connected\(uptime)\(addr)")
            toggleItem.title = "Disconnect"
            statsItem.isHidden = false
            if let kp = status.lastKeepalive {
                let ago = Int(-kp.timeIntervalSinceNow)
                statsItem.title = "  Last ping: \(ago)s ago"
            }

        case .connecting:
            headerItem.attributedTitle = styledHeader("Connecting…")
            toggleItem.title = "Disconnect"
            statsItem.isHidden = true

        case .disconnected:
            headerItem.attributedTitle = styledHeader("Disconnected")
            toggleItem.title = "Connect"
            statsItem.isHidden = true

        case .error:
            let msg = status.errorMsg ?? "Error"
            headerItem.attributedTitle = styledHeader("Error: \(msg)")
            toggleItem.title = "Reconnect"
            statsItem.isHidden = true
        }

        if !status.server.isEmpty {
            let tooltip = "Pritunl WG · \(status.server)"
            statusItem.button?.toolTip = tooltip
        }
    }

    @objc private func toggleConnection() {
        switch statusManager.status.state {
        case .connected, .connecting:
            vpnController.disconnect()
        default:
            vpnController.connect()
        }
    }

    @objc private func importProfile() {
        let panel = NSOpenPanel()
        panel.title = "Select Pritunl Profile"
        panel.message = "Choose a .tar or .ovpn file exported from Pritunl"
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        NSApplication.shared.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let ext = url.pathExtension.lowercased()
        guard ext == "tar" || ext == "ovpn" else {
            alert("Profile must be a .tar or .ovpn file.")
            return
        }

        vpnController.installProfile(url) { err in
            if let err {
                self.alert("Installation failed: \(err.localizedDescription)")
            } else {
                self.alert("Profile installed. You can now connect.")
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        if vpnController.isPasswordlessEnabled() {
            passwordlessItem.title = "Passwordless Connect Enabled"
            passwordlessItem.isEnabled = false
            passwordlessItem.action = nil
        } else {
            passwordlessItem.title = "Enable Passwordless Connect…"
            passwordlessItem.isEnabled = true
            passwordlessItem.action = #selector(enablePasswordless)
        }
    }

    @objc private func enablePasswordless() {
        vpnController.enablePasswordless { err in
            if let err {
                self.alert("Setup failed: \(err.localizedDescription)")
            } else {
                self.alert("Done. Connect and disconnect no longer require a password.")
            }
        }
    }

    @objc private func showLogs() {
        if logViewer == nil {
            logViewer = LogViewer()
        }
        logViewer?.show()
    }

    private func styledHeader(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ])
    }

    private func alert(_ msg: String) {
        DispatchQueue.main.async {
            let a = NSAlert()
            a.messageText = msg
            a.addButton(withTitle: "OK")
            NSApplication.shared.activate(ignoringOtherApps: true)
            a.runModal()
        }
    }
}
