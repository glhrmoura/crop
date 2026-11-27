import AppKit

struct SelectionHandle: Equatable {
    let x: Int
    let y: Int

    static let all: [SelectionHandle] = [
        SelectionHandle(x: -1, y: -1), SelectionHandle(x: 0, y: -1), SelectionHandle(x: 1, y: -1),
        SelectionHandle(x: -1, y: 0), SelectionHandle(x: 1, y: 0),
        SelectionHandle(x: -1, y: 1), SelectionHandle(x: 0, y: 1), SelectionHandle(x: 1, y: 1)
    ]

    func point(in rect: NSRect) -> NSPoint {
        let px = x < 0 ? rect.minX : (x == 0 ? rect.midX : rect.maxX)
        let py = y < 0 ? rect.minY : (y == 0 ? rect.midY : rect.maxY)
        return NSPoint(x: px, y: py)
    }

    static func hit(_ point: NSPoint, in rect: NSRect) -> SelectionHandle? {
        all.first { handle in
            let center = handle.point(in: rect)
            return hypot(point.x - center.x, point.y - center.y) <= 9
        }
    }

    func resize(_ rect: NSRect, to point: NSPoint) -> NSRect {
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY
        if x < 0 { minX = point.x }
        if x > 0 { maxX = point.x }
        if y < 0 { minY = point.y }
        if y > 0 { maxY = point.y }
        return NSRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
    }

    var cursor: NSCursor {
        let position: NSCursor.FrameResizePosition
        switch (x, y) {
        case (-1, 1): position = .topLeft
        case (0, 1): position = .top
        case (1, 1): position = .topRight
        case (-1, 0): position = .left
        case (1, 0): position = .right
        case (-1, -1): position = .bottomLeft
        case (0, -1): position = .bottom
        default: position = .bottomRight
        }
        return NSCursor.frameResize(position: position, directions: .all)
    }
}

@MainActor
final class OverlayView: NSView {
    weak var controller: CaptureController?
    let screenFrame: NSRect

    init(screenFrame: NSRect, controller: CaptureController) {
        self.screenFrame = screenFrame
        self.controller = controller
        super.init(frame: NSRect(origin: .zero, size: screenFrame.size))
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    private func globalPoint(_ event: NSEvent) -> NSPoint {
        let local = convert(event.locationInWindow, from: nil)
        return NSPoint(x: local.x + screenFrame.minX, y: local.y + screenFrame.minY)
    }

    private func updateCursor(_ event: NSEvent) {
        let topWindow = NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0)
        guard topWindow == window?.windowNumber else { return }
        controller?.cursor(at: globalPoint(event)).set()
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(event)
    }

    override func mouseDown(with event: NSEvent) {
        controller?.mouseDown(at: globalPoint(event), screenFrame: screenFrame)
    }

    override func mouseDragged(with event: NSEvent) {
        controller?.mouseDragged(to: globalPoint(event))
    }

    override func mouseUp(with event: NSEvent) {
        controller?.mouseUp(at: globalPoint(event))
    }

    private func local(_ rect: NSRect) -> NSRect {
        rect.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let controller else { return }
        let invisible = NSColor(calibratedWhite: 0, alpha: 0.004)

        switch controller.mode.target {
        case .screen:
            invisible.setFill()
            bounds.fill(using: .copy)

        case .window:
            invisible.setFill()
            bounds.fill(using: .copy)
            if let hovered = controller.hoveredWindow {
                let rect = local(hovered.frame).intersection(bounds)
                if !rect.isEmpty {
                    NSColor.systemBlue.withAlphaComponent(0.25).setFill()
                    rect.fill(using: .sourceOver)
                }
            }

        case .selection:
            NSColor(calibratedWhite: 0, alpha: 0.38).setFill()
            bounds.fill(using: .copy)
            guard let selection = controller.selection else { return }
            let rect = local(selection)
            guard rect.intersects(bounds) else { return }

            invisible.setFill()
            rect.fill(using: .copy)

            let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            NSColor.black.withAlphaComponent(0.45).setStroke()
            border.stroke()
            border.setLineDash([4, 3], count: 2, phase: 0)
            NSColor.white.setStroke()
            border.stroke()

            for handle in SelectionHandle.all where !controller.isCountingDown {
                let center = handle.point(in: rect)
                let circle = NSBezierPath(ovalIn: NSRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
                NSColor.white.setFill()
                circle.fill()
                circle.lineWidth = 1
                NSColor.black.withAlphaComponent(0.55).setStroke()
                circle.stroke()
            }

            if controller.showsDimensions {
                drawDimensions(for: rect, size: selection.size)
            }
        }
    }

    private func drawDimensions(for rect: NSRect, size: NSSize) {
        let text = "\(Int(size.width)) × \(Int(size.height))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let background = NSRect(
            x: rect.midX - textSize.width / 2 - 8,
            y: rect.midY - textSize.height / 2 - 4,
            width: textSize.width + 16,
            height: textSize.height + 8
        )
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: background, xRadius: 7, yRadius: 7).fill()
        text.draw(at: NSPoint(x: background.minX + 8, y: background.minY + 4), withAttributes: attributes)
    }
}

@MainActor
final class RecordingMask {
    private var windows: [NSWindow] = []

    func show(around rect: NSRect) {
        hide()
        let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = level
            window.sharingType = .none
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let hole = rect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
            window.contentView = RecordingMaskView(hole: hole)
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

final class RecordingMaskView: NSView {
    private let hole: NSRect

    init(hole: NSRect) {
        self.hole = hole
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0, alpha: 0.38).setFill()
        bounds.fill(using: .copy)
        let rect = hole.intersection(bounds)
        guard !rect.isEmpty else { return }
        NSColor.clear.setFill()
        rect.fill(using: .copy)
    }
}
