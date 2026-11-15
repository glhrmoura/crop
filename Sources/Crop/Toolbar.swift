import AppKit

enum ToolbarIcons {
    static func image(for mode: CaptureMode) -> NSImage {
        let size = NSSize(width: 30, height: 24)
        let image = NSImage(size: size, flipped: false) { _ in
            let frame = NSRect(x: 2, y: 4.5, width: 24, height: 16.5)
            drawShape(mode.target, in: frame)
            if mode.isRecording {
                drawRecordBadge(center: NSPoint(x: frame.maxX, y: frame.minY + 0.5))
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = mode.title
        return image
    }

    private static func drawShape(_ target: CaptureMode.Target, in frame: NSRect) {
        NSColor.black.set()
        let outline = NSBezierPath(roundedRect: frame.insetBy(dx: 0.65, dy: 0.65), xRadius: 3, yRadius: 3)
        outline.lineWidth = 1.3

        switch target {
        case .screen:
            outline.stroke()
            let bar = NSRect(x: frame.minX + 2.6, y: frame.minY + 2.6, width: frame.width - 5.2, height: 3.6)
            NSBezierPath(roundedRect: bar, xRadius: 0.8, yRadius: 0.8).fill()
        case .window:
            outline.stroke()
            for index in 0..<3 {
                let center = NSPoint(x: frame.minX + 3.8 + CGFloat(index) * 2.6, y: frame.maxY - 3.4)
                NSBezierPath(ovalIn: NSRect(x: center.x - 0.8, y: center.y - 0.8, width: 1.6, height: 1.6)).fill()
            }
        case .selection:
            outline.setLineDash([2.6, 2], count: 2, phase: 0)
            outline.stroke()
        }
    }

    private static func drawRecordBadge(center: NSPoint) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        context.compositingOperation = .clear
        NSBezierPath(ovalIn: NSRect(x: center.x - 5.6, y: center.y - 5.6, width: 11.2, height: 11.2)).fill()
        context.restoreGraphicsState()

        NSColor.black.set()
        let ring = NSBezierPath(ovalIn: NSRect(x: center.x - 4.1, y: center.y - 4.1, width: 8.2, height: 8.2))
        ring.lineWidth = 1.2
        ring.stroke()
        NSBezierPath(ovalIn: NSRect(x: center.x - 2.3, y: center.y - 2.3, width: 4.6, height: 4.6)).fill()
    }
}

final class ToolbarModeButton: PointerControl {
    let mode: CaptureMode
    var isSelected = false { didSet { needsDisplay = true } }
    private var isHovered = false { didSet { needsDisplay = true } }
    private var isPressed = false { didSet { needsDisplay = true } }
    private let icon: NSImage

    init(mode: CaptureMode) {
        self.mode = mode
        self.icon = ToolbarIcons.image(for: mode)
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width(for: mode), height: 34))
        toolTip = mode.title
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(mode.title)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.width(for: mode)),
            heightAnchor.constraint(equalToConstant: 34)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    static func width(for mode: CaptureMode) -> CGFloat { mode.isRecording ? 46 : 42 }

    override var intrinsicContentSize: NSSize { NSSize(width: Self.width(for: mode), height: 34) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            sendAction(action, to: target)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let alpha: CGFloat = isSelected ? 0.14 : (isPressed ? 0.12 : (isHovered ? 0.06 : 0))
        if alpha > 0 {
            NSColor.labelColor.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }
        let tint = NSColor.labelColor.withAlphaComponent(isSelected ? 0.9 : 0.72)
        let tinted = NSImage(size: icon.size, flipped: false) { rect in
            self.icon.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        let origin = NSPoint(x: (bounds.width - icon.size.width) / 2, y: (bounds.height - icon.size.height) / 2)
        tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
    }
}

final class ToolbarActionButton: PointerControl {
    var title: String = "" { didSet { refreshContent() } }
    var timerSeconds: Int = 0 { didSet { refreshContent() } }
    private var isPressed = false { didSet { refreshFill() } }
    private var isHovered = false { didSet { refreshFill() } }

    private let titleFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    private let timerFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    private let baseColor = NSColor(srgbRed: 232 / 255, green: 38 / 255, blue: 30 / 255, alpha: 1)
    private let labelView = ActionLabelView()
    private var glass: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.button)
        setContentHuggingPriority(.required, for: .horizontal)
        if #available(macOS 26.0, *) {
            let effect = NSGlassEffectView(frame: bounds)
            effect.cornerRadius = 9
            effect.autoresizingMask = [.width, .height]
            addSubview(effect)
            glass = effect
        }
        labelView.frame = bounds
        labelView.autoresizingMask = [.width, .height]
        addSubview(labelView)
        refreshFill()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    private var content: NSAttributedString {
        let result = NSMutableAttributedString(string: title, attributes: [.font: titleFont, .foregroundColor: NSColor.white])
        if timerSeconds > 0 {
            let secondary = NSColor.white.withAlphaComponent(0.6)
            result.append(NSAttributedString(string: "  ", attributes: [.font: timerFont]))
            if let symbol = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 11, weight: .regular).applying(.init(paletteColors: [secondary]))) {
                let attachment = NSTextAttachment()
                attachment.image = symbol
                attachment.bounds = NSRect(x: 0, y: -1.5, width: symbol.size.width, height: symbol.size.height)
                result.append(NSAttributedString(attachment: attachment))
            }
            result.append(NSAttributedString(string: " \(timerSeconds)s", attributes: [.font: timerFont, .foregroundColor: secondary]))
        }
        return result
    }

    private var fillColor: NSColor {
        if isPressed { return baseColor.blended(withFraction: 0.2, of: .black) ?? baseColor }
        if isHovered { return baseColor.blended(withFraction: 0.1, of: .white) ?? baseColor }
        return baseColor
    }

    private func refreshContent() {
        labelView.content = content
        invalidateIntrinsicContentSize()
    }

    private func refreshFill() {
        if #available(macOS 26.0, *), let effect = glass as? NSGlassEffectView {
            effect.tintColor = fillColor
        } else {
            needsDisplay = true
        }
    }

    override var intrinsicContentSize: NSSize {
        let size = content.size()
        return NSSize(width: ceil(size.width) + 32, height: 36)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.options.contains(.mouseEnteredAndExited) }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            sendAction(action, to: target)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard glass == nil else { return }
        let fill = fillColor
        let top = fill.blended(withFraction: 0.015, of: .white) ?? fill
        let bottom = fill.blended(withFraction: 0.015, of: .black) ?? fill
        NSGradient(starting: top, ending: bottom)?.draw(in: NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9), angle: isFlipped ? 90 : -90)
    }
}

final class ActionLabelView: NSView {
    var content = NSAttributedString() { didSet { needsDisplay = true } }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let size = content.size()
        content.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}

final class ToolbarOptionsButton: PointerControl {
    private var isPressed = false { didSet { needsDisplay = true } }
    private let label = L("Options")
    private let labelFont = NSFont.systemFont(ofSize: 13, weight: .regular)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.popUpButton)
        setAccessibilityLabel(label)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var intrinsicContentSize: NSSize {
        let size = (label as NSString).size(withAttributes: [.font: labelFont])
        return NSSize(width: ceil(size.width) + 30, height: 34)
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        sendAction(action, to: target)
        isPressed = false
    }

    override func draw(_ dirtyRect: NSRect) {
        if isPressed {
            NSColor.labelColor.withAlphaComponent(0.1).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }
        let color = NSColor.labelColor.withAlphaComponent(0.72)
        let attributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: color]
        let size = (label as NSString).size(withAttributes: attributes)
        let originX: CGFloat = 8
        (label as NSString).draw(at: NSPoint(x: originX, y: (bounds.height - size.height) / 2), withAttributes: attributes)

        guard let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold).applying(.init(paletteColors: [color]))) else { return }
        chevron.draw(at: NSPoint(x: originX + size.width + 5, y: (bounds.height - chevron.size.height) / 2 - 0.5),
                     from: .zero, operation: .sourceOver, fraction: 1)
    }
}

final class ToolbarSeparator: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: 1, height: 22) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.14).setFill()
        bounds.fill()
    }
}

@MainActor
final class CaptureToolbarView: NSView {
    var onSelectMode: ((CaptureMode) -> Void)?
    var onClose: (() -> Void)?
    var onOptions: ((NSView) -> Void)?
    var onAction: (() -> Void)?

    private var modeButtons: [ToolbarModeButton] = []
    private let actionButton = ToolbarActionButton()
    private let optionsButton = ToolbarOptionsButton()

    init(mode: CaptureMode, timerSeconds: Int) {
        super.init(frame: .zero)

        let closeButton = PointerButton()
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: L("Close"))?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
        closeButton.contentTintColor = NSColor.labelColor.withAlphaComponent(0.55)
        closeButton.toolTip = L("Close")
        closeButton.target = self
        closeButton.action = #selector(close)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.widthAnchor.constraint(equalToConstant: 26).isActive = true

        modeButtons = CaptureMode.allCases.map { mode in
            let button = ToolbarModeButton(mode: mode)
            button.target = self
            button.action = #selector(selectMode(_:))
            return button
        }

        optionsButton.target = self
        optionsButton.action = #selector(showOptions)
        actionButton.target = self
        actionButton.action = #selector(performAction)

        let screenshotGroup = group(Array(modeButtons[0..<3]))
        let recordingGroup = group(Array(modeButtons[3..<6]))

        let stack = NSStackView(views: [
            closeButton,
            screenshotGroup,
            ToolbarSeparator(),
            recordingGroup,
            ToolbarSeparator(),
            optionsButton,
            actionButton
        ])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.setCustomSpacing(8, after: closeButton)
        stack.setCustomSpacing(6, after: optionsButton)
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 10, bottom: 5, right: 5)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        update(mode: mode, timerSeconds: timerSeconds)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(mode: CaptureMode, timerSeconds: Int) {
        for button in modeButtons {
            button.isSelected = button.mode == mode
        }
        actionButton.title = mode.actionTitle
        actionButton.timerSeconds = timerSeconds
        actionButton.setAccessibilityLabel(mode.actionTitle)
    }

    private func group(_ buttons: [NSView]) -> NSStackView {
        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.spacing = 4
        return stack
    }

    @objc private func close() {
        onClose?()
    }

    @objc private func selectMode(_ sender: ToolbarModeButton) {
        onSelectMode?(sender.mode)
    }

    @objc private func showOptions() {
        onOptions?(optionsButton)
    }

    @objc private func performAction() {
        onAction?()
    }
}

class CaptureKeyWindow: NSWindow {
    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onCancel?()
        case 36, 76: onConfirm?()
        default: super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

@MainActor
final class ToolbarWindow: CaptureKeyWindow {
    private let toolbarView: NSView

    init(toolbar: NSView) {
        self.toolbarView = toolbar
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let size = toolbar.fittingSize
        let bounds = NSRect(origin: .zero, size: size)
        toolbar.translatesAutoresizingMaskIntoConstraints = true
        toolbar.autoresizingMask = [.width, .height]
        toolbar.frame = bounds

        let radius: CGFloat = 14
        let container: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.cornerRadius = radius
            glass.autoresizingMask = [.width, .height]
            let stack = NSView(frame: bounds)
            stack.addSubview(glass)
            stack.addSubview(toolbar)
            container = stack
        } else {
            let effect = NSVisualEffectView(frame: bounds)
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.maskImage = Self.roundedMask(radius: radius)
            effect.addSubview(toolbar)
            container = effect
        }
        container.autoresizingMask = [.width, .height]
        contentView = container
        setContentSize(size)
    }

    func fitToContent() {
        toolbarView.layoutSubtreeIfNeeded()
        let size = toolbarView.fittingSize
        let anchor = NSPoint(x: frame.midX, y: frame.minY)
        setFrame(NSRect(x: (anchor.x - size.width / 2).rounded(), y: anchor.y, width: size.width, height: size.height), display: true)
        toolbarView.frame = NSRect(origin: .zero, size: size)
        invalidateShadow()
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

final class ToolbarPlainButton: PointerControl {
    private let title: String
    private var isPressed = false { didSet { needsDisplay = true } }
    private let titleFont = NSFont.systemFont(ofSize: 13, weight: .regular)

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var intrinsicContentSize: NSSize {
        let size = (title as NSString).size(withAttributes: [.font: titleFont])
        return NSSize(width: ceil(size.width) + 32, height: 36)
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            sendAction(action, to: target)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(isPressed ? 0.2 : 0.12).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.85)
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
}

@MainActor
final class CountdownPillView: NSView {
    var onCancel: (() -> Void)?

    private let timerLabel = NSTextField(labelWithString: "")

    init(seconds: Int) {
        super.init(frame: .zero)

        let cancelButton = ToolbarPlainButton(title: L("Cancel"))
        cancelButton.target = self
        cancelButton.action = #selector(cancel)

        timerLabel.setContentHuggingPriority(.required, for: .horizontal)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setContentHuggingPriority(.required, for: .horizontal)

        let stack = NSStackView(views: [cancelButton, timerLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 46),
            cancelButton.heightAnchor.constraint(equalToConstant: 34),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        update(seconds)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(_ seconds: Int) {
        let color = NSColor.labelColor.withAlphaComponent(0.6)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        let text = NSMutableAttributedString()
        if let symbol = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular).applying(.init(paletteColors: [color]))) {
            let attachment = NSTextAttachment()
            attachment.image = symbol
            attachment.bounds = NSRect(x: 0, y: -2, width: symbol.size.width, height: symbol.size.height)
            text.append(NSAttributedString(attachment: attachment))
        }
        text.append(NSAttributedString(string: " \(seconds)s", attributes: [.font: font, .foregroundColor: color]))
        timerLabel.attributedStringValue = text
    }

    @objc private func cancel() {
        onCancel?()
    }
}

class PointerControl: NSControl {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.options.contains(.cursorUpdate) }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.cursorUpdate, .activeAlways, .inVisibleRect], owner: self))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }
}

final class PointerButton: NSButton {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self && $0.options.contains(.cursorUpdate) }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.cursorUpdate, .activeAlways, .inVisibleRect], owner: self))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }
}
