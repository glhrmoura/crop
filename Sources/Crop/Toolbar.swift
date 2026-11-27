import AppKit

enum ToolbarIcons {
    static let canvas = NSSize(width: 38, height: 30)

    static func image(for mode: CaptureMode) -> NSImage {
        let image = NSImage(size: canvas, flipped: true) { _ in
            if mode.isRecording, let badged = symbol(badgedName(for: mode.target)) {
                badged.draw(in: NSRect(origin: .zero, size: badged.size))
            } else if let base = symbol(baseName(for: mode.target)) {
                base.draw(in: NSRect(origin: .zero, size: base.size))
                if mode.isRecording { drawRecordBadge() }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = mode.title
        return image
    }

    private static func baseName(for target: CaptureMode.Target) -> String {
        switch target {
        case .screen: return "menubar.dock.rectangle"
        case .window: return "macwindow"
        case .selection: return "rectangle.dashed"
        }
    }

    private static func badgedName(for target: CaptureMode.Target) -> String {
        "\(baseName(for: target)).badge.record"
    }

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 24, weight: .regular))
    }

    private static func drawRecordBadge() {
        guard let context = NSGraphicsContext.current else { return }
        let center = NSPoint(x: 30, y: 22.25)
        context.saveGraphicsState()
        context.compositingOperation = .clear
        NSBezierPath(ovalIn: NSRect(x: center.x - 7.25, y: center.y - 7.25, width: 14.5, height: 14.5)).fill()
        context.restoreGraphicsState()

        NSColor.black.set()
        let ring = NSBezierPath(ovalIn: NSRect(x: center.x - 4.875, y: center.y - 4.875, width: 9.75, height: 9.75))
        ring.lineWidth = 1.75
        ring.stroke()
        NSBezierPath(ovalIn: NSRect(x: center.x - 3.25, y: center.y - 3.25, width: 6.5, height: 6.5)).fill()
    }
}

enum ToolbarMetrics {
    static let barHeight: CGFloat = 50
    static let barRadius: CGFloat = 15
    static let inset: CGFloat = 7
    static let controlHeight: CGFloat = 36
    static let modeWidth: CGFloat = 44
    static let modeRadius: CGFloat = 8
    static let actionRadius: CGFloat = 10
    static let iconAlpha: CGFloat = 0.38
    static let selectedIconAlpha: CGFloat = 0.41
    static let selectedFillAlpha: CGFloat = 0.1
    static let hoverFillAlpha: CGFloat = 0.06
    static let separatorAlpha: CGFloat = 0.1
    static let font = NSFont.systemFont(ofSize: 13, weight: .regular)
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
        super.init(frame: NSRect(x: 0, y: 0, width: ToolbarMetrics.modeWidth, height: ToolbarMetrics.controlHeight))
        toolTip = mode.title
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(mode.title)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: ToolbarMetrics.modeWidth),
            heightAnchor.constraint(equalToConstant: ToolbarMetrics.controlHeight)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize { NSSize(width: ToolbarMetrics.modeWidth, height: ToolbarMetrics.controlHeight) }

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
        let alpha: CGFloat = isSelected ? ToolbarMetrics.selectedFillAlpha : (isPressed ? ToolbarMetrics.selectedFillAlpha : (isHovered ? ToolbarMetrics.hoverFillAlpha : 0))
        if alpha > 0 {
            NSColor.labelColor.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: ToolbarMetrics.modeRadius, yRadius: ToolbarMetrics.modeRadius).fill()
        }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = NSRect(x: 5, y: bounds.height - 5 - icon.size.height, width: icon.size.width, height: icon.size.height)
        context.saveGState()
        context.setAlpha(isSelected ? ToolbarMetrics.selectedIconAlpha : ToolbarMetrics.iconAlpha)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        icon.draw(in: rect)
        NSColor.labelColor.withAlphaComponent(1).set()
        rect.fill(using: .sourceAtop)
        context.endTransparencyLayer()
        context.restoreGState()
    }
}

final class ToolbarActionButton: PointerControl {
    var title: String = "" { didSet { refreshContent() } }
    var timerSeconds: Int = 0 { didSet { refreshContent() } }
    private var isPressed = false { didSet { refreshFill() } }
    private var isHovered = false { didSet { refreshFill() } }

    private let titleFont = ToolbarMetrics.font
    private let timerFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    private let topColor = NSColor(displayP3Red: 57 / 255, green: 200 / 255, blue: 1, alpha: 1)
    private let bottomColor = NSColor(displayP3Red: 46 / 255, green: 189 / 255, blue: 1, alpha: 1)
    private let labelView = ActionLabelView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.button)
        setContentHuggingPriority(.required, for: .horizontal)
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
            let secondary = NSColor.white.withAlphaComponent(0.5)
            if let symbol = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular).applying(.init(paletteColors: [.white]))) {
                let slot = NSSize(width: 23.8, height: symbol.size.height)
                let image = NSImage(size: slot, flipped: false) { rect in
                    symbol.draw(in: NSRect(x: (rect.width - symbol.size.width) / 2 + 0.5, y: 0, width: symbol.size.width, height: symbol.size.height),
                                from: .zero, operation: .sourceOver, fraction: secondary.alphaComponent)
                    return true
                }
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = NSRect(x: 0, y: (titleFont.capHeight - slot.height) / 2 + 0.5, width: slot.width, height: slot.height)
                result.append(NSAttributedString(attachment: attachment))
            }
            result.append(NSAttributedString(string: "\(timerSeconds)s", attributes: [.font: timerFont, .foregroundColor: secondary]))
        }
        return result
    }

    private func adjusted(_ color: NSColor) -> NSColor {
        if isPressed { return color.blended(withFraction: 0.2, of: .black) ?? color }
        if isHovered { return color.blended(withFraction: 0.1, of: .white) ?? color }
        return color
    }

    private func refreshContent() {
        labelView.content = content
        invalidateIntrinsicContentSize()
    }

    private func refreshFill() {
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        let size = content.size()
        return NSSize(width: size.width + 30, height: ToolbarMetrics.controlHeight)
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
        let path = NSBezierPath(roundedRect: bounds, xRadius: ToolbarMetrics.actionRadius, yRadius: ToolbarMetrics.actionRadius)
        NSGradient(starting: adjusted(topColor), ending: adjusted(bottomColor))?.draw(in: path, angle: isFlipped ? 90 : -90)
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
    private let labelFont = ToolbarMetrics.font
    private static let padding: CGFloat = 8
    private static let chevronGap: CGFloat = 4.8

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.popUpButton)
        setAccessibilityLabel(label)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func chevron(_ color: NSColor) -> NSImage? {
        NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 8, weight: .semibold).applying(.init(paletteColors: [color])))
    }

    override var intrinsicContentSize: NSSize {
        let size = (label as NSString).size(withAttributes: [.font: labelFont])
        let chevronWidth = chevron(.labelColor)?.size.width ?? 0
        return NSSize(width: Self.padding * 2 + size.width + Self.chevronGap + chevronWidth, height: ToolbarMetrics.controlHeight)
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        sendAction(action, to: target)
        isPressed = false
    }

    override func draw(_ dirtyRect: NSRect) {
        if isPressed {
            NSColor.labelColor.withAlphaComponent(ToolbarMetrics.selectedFillAlpha).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: ToolbarMetrics.modeRadius, yRadius: ToolbarMetrics.modeRadius).fill()
        }
        let color = NSColor.labelColor.withAlphaComponent(ToolbarMetrics.iconAlpha)
        let attributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: color]
        let size = (label as NSString).size(withAttributes: attributes)
        let originX = Self.padding
        (label as NSString).draw(at: NSPoint(x: originX, y: (bounds.height - size.height) / 2), withAttributes: attributes)

        guard let chevron = chevron(NSColor.labelColor.withAlphaComponent(1)) else { return }
        chevron.draw(at: NSPoint(x: originX + size.width + Self.chevronGap, y: (bounds.height - chevron.size.height) / 2),
                     from: .zero, operation: .sourceOver, fraction: ToolbarMetrics.iconAlpha)
    }
}

final class ToolbarSeparator: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: 1, height: 23) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(ToolbarMetrics.separatorAlpha).setFill()
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
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = NSColor.labelColor.withAlphaComponent(ToolbarMetrics.iconAlpha)
        closeButton.toolTip = L("Close")
        closeButton.target = self
        closeButton.action = #selector(close)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.widthAnchor.constraint(equalToConstant: 19).isActive = true

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

        let screenshotGroup = group(Array(modeButtons[0..<3]), spacing: 4)
        let recordingGroup = group(Array(modeButtons[3..<6]), spacing: 13)
        let firstSeparator = ToolbarSeparator()
        let secondSeparator = ToolbarSeparator()

        let stack = NSStackView(views: [
            closeButton,
            screenshotGroup,
            firstSeparator,
            recordingGroup,
            secondSeparator,
            optionsButton,
            actionButton
        ])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 0
        stack.setCustomSpacing(10, after: closeButton)
        stack.setCustomSpacing(8, after: screenshotGroup)
        stack.setCustomSpacing(13, after: firstSeparator)
        stack.setCustomSpacing(13, after: recordingGroup)
        stack.setCustomSpacing(6, after: secondSeparator)
        stack.setCustomSpacing(4.5, after: optionsButton)
        stack.edgeInsets = NSEdgeInsets(top: ToolbarMetrics.inset, left: 13, bottom: ToolbarMetrics.inset, right: ToolbarMetrics.inset)
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

    private func group(_ buttons: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.spacing = spacing
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
    var acceptsKey = true

    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { acceptsKey }

    init(toolbar: NSView) {
        self.toolbarView = toolbar
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        level = .statusBar
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let size = toolbar.fittingSize
        let bounds = NSRect(origin: .zero, size: size)
        toolbar.translatesAutoresizingMaskIntoConstraints = true
        toolbar.autoresizingMask = [.width, .height]
        toolbar.frame = bounds

        let radius = ToolbarMetrics.barRadius
        let bar: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.cornerRadius = radius
            glass.autoresizingMask = [.width, .height]
            let stack = NSView(frame: bounds)
            stack.addSubview(glass)
            stack.addSubview(toolbar)
            bar = stack
        } else {
            let effect = NSVisualEffectView(frame: bounds)
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.maskImage = Self.roundedMask(radius: radius)
            effect.addSubview(toolbar)
            bar = effect
        }
        bar.frame = bounds.offsetBy(dx: Self.margin, dy: Self.margin)
        bar.autoresizingMask = [.width, .height]

        let container = NSView(frame: bounds.insetBy(dx: -Self.margin, dy: -Self.margin))
        container.wantsLayer = true
        let shadow = ToolbarShadowView(frame: bar.frame, radius: radius)
        shadow.autoresizingMask = [.width, .height]
        container.addSubview(shadow)
        container.addSubview(bar)
        setContentSize(container.frame.size)
        contentView = container
    }

    static let margin: CGFloat = 24

    func fitToContent() {
        toolbarView.layoutSubtreeIfNeeded()
        let size = toolbarView.fittingSize
        let outer = NSSize(width: size.width + Self.margin * 2, height: size.height + Self.margin * 2)
        let anchor = NSPoint(x: frame.midX, y: frame.minY)
        setFrame(NSRect(x: (anchor.x - outer.width / 2).rounded(), y: anchor.y, width: outer.width, height: outer.height), display: true)
        toolbarView.frame = NSRect(origin: .zero, size: size)
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

final class ToolbarShadowView: NSView {
    private let radius: CGFloat
    private let shadowLayer = CALayer()
    private let maskLayer = CAShapeLayer()
    private let hairline = CAShapeLayer()

    init(frame frameRect: NSRect, radius: CGFloat) {
        self.radius = radius
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = 0.18
        shadowLayer.shadowRadius = 9
        shadowLayer.shadowOffset = CGSize(width: 0, height: -3)
        maskLayer.fillRule = .evenOdd
        shadowLayer.mask = maskLayer
        hairline.fillColor = nil
        hairline.strokeColor = NSColor.black.withAlphaComponent(0.4).cgColor
        hairline.lineWidth = 0.5
        layer?.addSublayer(shadowLayer)
        layer?.addSublayer(hairline)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let shape = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let reach = ToolbarWindow.margin
        shadowLayer.frame = bounds
        shadowLayer.shadowPath = shape
        let mask = CGMutablePath()
        mask.addRect(bounds.insetBy(dx: -reach, dy: -reach))
        mask.addPath(shape)
        maskLayer.frame = bounds
        maskLayer.path = mask
        let edge = bounds.insetBy(dx: -0.25, dy: -0.25)
        hairline.frame = bounds
        hairline.path = CGPath(roundedRect: edge, cornerWidth: radius + 0.25, cornerHeight: radius + 0.25, transform: nil)
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
