import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusManager: StatusManager!
    private var vpnController: VPNController!
    private var menuController: MenuController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusManager = StatusManager()
        vpnController = VPNController()
        menuController = MenuController(
            statusItem: statusItem,
            statusManager: statusManager,
            vpnController: vpnController
        )

        statusManager.onChanged = { [weak self] status in
            self?.menuController.update(status: status)
        }

        // Render initial icon
        menuController.update(status: statusManager.status)
        statusManager.start()
    }
}
