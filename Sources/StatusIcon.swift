import AppKit

enum StatusIcon {
    static func image(for state: ConnectionState) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            let color: NSColor
            switch state {
            case .connected:    color = NSColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1)
            case .connecting:   color = NSColor(red: 1.00, green: 0.75, blue: 0.00, alpha: 1)
            case .disconnected: color = NSColor(red: 0.85, green: 0.20, blue: 0.20, alpha: 1)
            case .error:        color = NSColor(red: 0.85, green: 0.20, blue: 0.20, alpha: 1)
            }

            // Draw shield outline
            let path = shieldPath(in: rect.insetBy(dx: 2, dy: 1.5))
            color.setFill()
            path.fill()

            // Draw small keyhole on connected state only
            if state == .connected {
                let hole = keyholePath(in: rect)
                NSColor.white.withAlphaComponent(0.9).setFill()
                hole.fill()
            }
            return true
        }
        img.isTemplate = false
        return img
    }

    private static func shieldPath(in rect: NSRect) -> NSBezierPath {
        let w = rect.width, h = rect.height
        let x = rect.minX, y = rect.minY
        let r = w * 0.3  // corner radius for top
        let path = NSBezierPath()
        // Shield: rounded top, pointed bottom
        path.move(to: NSPoint(x: x + w * 0.5, y: y))
        path.line(to: NSPoint(x: x, y: y + h * 0.3))
        path.line(to: NSPoint(x: x, y: y + h * 0.85))
        path.appendArc(withCenter: NSPoint(x: x + r, y: y + h - r),
                       radius: r, startAngle: 180, endAngle: 90, clockwise: true)
        path.line(to: NSPoint(x: x + w - r, y: y + h))
        path.appendArc(withCenter: NSPoint(x: x + w - r, y: y + h - r),
                       radius: r, startAngle: 90, endAngle: 0, clockwise: true)
        path.line(to: NSPoint(x: x + w, y: y + h * 0.3))
        path.close()
        return path
    }

    private static func keyholePath(in rect: NSRect) -> NSBezierPath {
        let cx = rect.midX
        let cy = rect.midY + rect.height * 0.05
        let cr = rect.width * 0.12
        let path = NSBezierPath()
        path.appendOval(in: NSRect(x: cx - cr, y: cy, width: cr * 2, height: cr * 2))
        // Stem
        let sw = cr * 0.8
        path.appendRect(NSRect(x: cx - sw / 2, y: cy - cr * 1.4, width: sw, height: cr * 1.6))
        return path
    }
}
