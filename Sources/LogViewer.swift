import AppKit

private let logPath = "/var/log/pritunl-wg.log"
private let maxLines = 500

class LogViewer: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var textView: NSTextView?
    private var timer: Timer?

    func show() {
        if window == nil { buildWindow() }
        loadLog()
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        startAutoRefresh()
    }

    private func buildWindow() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 420),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Pritunl WG Logs"
        w.center()
        w.delegate = self

        let scroll = NSScrollView(frame: w.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false

        let tv = NSTextView(frame: scroll.bounds)
        tv.isEditable = false
        tv.isSelectable = true
        tv.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true

        scroll.documentView = tv
        w.contentView?.addSubview(scroll)

        let toolbar = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 36))
        toolbar.autoresizingMask = [.width, .maxYMargin]
        let btn = NSButton(title: "Refresh", target: self, action: #selector(refresh))
        btn.bezelStyle = .rounded
        btn.frame = NSRect(x: 8, y: 6, width: 80, height: 24)
        toolbar.addSubview(btn)
        w.contentView?.addSubview(toolbar)

        self.window = w
        self.textView = tv
    }

    @objc private func refresh() { loadLog() }

    private func loadLog() {
        let content: String
        if let raw = try? String(contentsOfFile: logPath, encoding: .utf8) {
            let lines = raw.components(separatedBy: "\n")
            let tail = lines.suffix(maxLines)
            content = tail.joined(separator: "\n")
        } else {
            content = "(Log file not found at \(logPath))"
        }
        textView?.string = content
        // Scroll to bottom
        if let tv = textView {
            tv.scrollToEndOfDocument(nil)
        }
    }

    private func startAutoRefresh() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, self.window?.isVisible == true else { return }
            self.loadLog()
        }
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }
}
