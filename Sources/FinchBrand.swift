import AppKit

enum FinchBrand {
    // Keep the compatibility bundle ID and cache location when changing the app name.
    static let name = "Codex Finch"
    static let appImage: NSImage = {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let image = NSImage(contentsOf: url) else { return menuImage }
        return image
    }()

    static let menuImage: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.scaleBy(x: 0.75, y: 0.75)
            context.translateBy(x: 0, y: 24)
            context.scaleBy(x: 1, y: -1)
            let bird = CGMutablePath()
            bird.move(to: CGPoint(x: 3.2, y: 19.6))
            bird.addLine(to: CGPoint(x: 7, y: 15.8))
            bird.addCurve(to: CGPoint(x: 11.4, y: 9.7), control1: CGPoint(x: 7.6, y: 12.8), control2: CGPoint(x: 9.2, y: 11.1))
            bird.addCurve(to: CGPoint(x: 12.5, y: 7.6), control1: CGPoint(x: 12, y: 9.3), control2: CGPoint(x: 12.3, y: 8.7))
            bird.addCurve(to: CGPoint(x: 17, y: 3.4), control1: CGPoint(x: 12.8, y: 5.1), control2: CGPoint(x: 14.6, y: 3.4))
            bird.addCurve(to: CGPoint(x: 21.8, y: 8.5), control1: CGPoint(x: 19.9, y: 3.4), control2: CGPoint(x: 21.8, y: 5.7))
            bird.addCurve(to: CGPoint(x: 20.6, y: 12.1), control1: CGPoint(x: 21.8, y: 9.9), control2: CGPoint(x: 21.4, y: 11.1))
            bird.addCurve(to: CGPoint(x: 21.7, y: 15.8), control1: CGPoint(x: 21.3, y: 13.3), control2: CGPoint(x: 21.7, y: 14.5))
            bird.addCurve(to: CGPoint(x: 14.2, y: 21.9), control1: CGPoint(x: 21.7, y: 19.5), control2: CGPoint(x: 18.2, y: 21.9))
            bird.addCurve(to: CGPoint(x: 8.5, y: 20.6), control1: CGPoint(x: 12, y: 21.9), control2: CGPoint(x: 10.2, y: 21.3))
            bird.addLine(to: CGPoint(x: 5.1, y: 22.1))
            bird.addCurve(to: CGPoint(x: 3.2, y: 19.6), control1: CGPoint(x: 3.5, y: 22.8), control2: CGPoint(x: 2, y: 21.4))
            bird.closeSubpath()
            bird.addEllipse(in: CGRect(x: 17.05, y: 5.5, width: 1.9, height: 1.9))
            let terminal = [CGPoint(x: 9.5, y: 13), CGPoint(x: 12.2, y: 15), CGPoint(x: 9.5, y: 17),
                            CGPoint(x: 10.8, y: 18), CGPoint(x: 14.8, y: 15), CGPoint(x: 10.8, y: 12)]
            bird.addLines(between: terminal); bird.closeSubpath()
            bird.addRect(CGRect(x: 15.5, y: 16, width: 4.3, height: 1.8))
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(bird); context.drawPath(using: .eoFill)
            let beak = CGMutablePath()
            beak.addLines(between: [CGPoint(x: 22.2, y: 7.8), CGPoint(x: 23.8, y: 8.9), CGPoint(x: 22.2, y: 10)])
            beak.closeSubpath(); context.addPath(beak); context.fillPath()
            context.restoreGState()
        }
        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "Codex Finch"
        return image
    }()
}
