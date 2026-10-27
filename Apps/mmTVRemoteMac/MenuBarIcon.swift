import AppKit

enum MenuBarIcon {
    /// A compact remote-control silhouette designed for the 18 pt macOS menu bar.
    /// AppKit supplies the correct foreground color for light, dark and tinted bars.
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let body = NSBezierPath(
                roundedRect: NSRect(x: 4.25, y: 0.75, width: 9.5, height: 16.5),
                xRadius: 4.5,
                yRadius: 4.5
            )
            body.lineWidth = 1.7
            body.stroke()

            let navigationRing = NSBezierPath(
                ovalIn: NSRect(x: 6.25, y: 10, width: 5.5, height: 5.5)
            )
            navigationRing.lineWidth = 1.45
            navigationRing.stroke()

            NSBezierPath(ovalIn: NSRect(x: 8.15, y: 11.9, width: 1.7, height: 1.7)).fill()
            NSBezierPath(ovalIn: NSRect(x: 7.2, y: 6.8, width: 3.6, height: 1.45)).fill()
            NSBezierPath(ovalIn: NSRect(x: 7.2, y: 3.9, width: 3.6, height: 1.45)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "mmTV Remote"
        return image
    }()
}
