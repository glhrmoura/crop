import AppKit
import AVFoundation

@MainActor
final class CaptureController: NSObject {
    var onCapture: ((CaptureRequest) -> Void)?

    private enum Interaction {
        case idle
        case creating(origin: NSPoint, screenFrame: NSRect, previous: NSRect?)
        case moving(start: NSPoint, original: NSRect, screenFrame: NSRect)
        case resizing(handle: SelectionHandle, original: NSRect, screenFrame: NSRect)
    }

    private let preferences = Preferences.shared
    private let optionsMenu = OptionsMenu()
    private var toolbarWindow: ToolbarWindow?
    private var toolbarView: CaptureToolbarView?
    private var overlayWindows: [CaptureKeyWindow] = []
    private var overlayViews: [OverlayView] = []
    private var windowCandidates: [WindowCandidate] = []
    private var interaction: Interaction = .idle
    private var countdownWindow: ToolbarWindow?
    private var countdownTask: Task<Void, Never>?

    private(set) var mode: CaptureMode
    private(set) var selection: NSRect?
    private(set) var hoveredWindow: WindowCandidate?

    var isActive: Bool { toolbarWindow != nil }
    var isCountingDown: Bool { countdownWindow != nil }

    var showsDimensions: Bool {
        if case .idle = interaction { return false }
        return true
    }

    override init() {
        mode = CaptureMode(rawValue: Preferences.shared.lastMode) ?? .recordSelection
        super.init()
        optionsMenu.onChange = { [weak self] in self?.refreshToolbar() }
        optionsMenu.onChooseLocation = { [weak self] in self?.presentSaveLocationPanel() }
    }

    func show() {
        if let toolbarWindow {
            NSApp.activate(ignoringOtherApps: true)
            toolbarWindow.orderFrontRegardless()
            focusOverlay()
            return
        }

        let anchorScreen = NSScreen.underMouse ?? NSScreen.screens[0]
        restoreSelection(on: anchorScreen)
        windowCandidates = WindowCandidate.onScreen()

        let overlayLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
        for screen in NSScreen.screens {
            let window = CaptureKeyWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = overlayLevel
            window.sharingType = .none
            window.isReleasedWhenClosed = false
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.onCancel = { [weak self] in self?.dismiss() }
            window.onConfirm = { [weak self] in self?.performAction() }
            let view = OverlayView(screenFrame: screen.frame, controller: self)
            window.contentView = view
            window.setFrame(screen.frame, display: false)
            window.orderFrontRegardless()
            overlayWindows.append(window)
            overlayViews.append(view)
        }

        let toolbar = CaptureToolbarView(mode: mode, timerSeconds: preferences.timerSeconds)
        toolbar.onSelectMode = { [weak self] mode in self?.select(mode) }
        toolbar.onClose = { [weak self] in self?.dismiss() }
        toolbar.onOptions = { [weak self] anchor in self?.showOptions(from: anchor) }
        toolbar.onAction = { [weak self] in self?.performAction() }

        let window = ToolbarWindow(toolbar: toolbar)
        window.acceptsKey = false
        window.onCancel = { [weak self] in self?.dismiss() }
        window.onConfirm = { [weak self] in self?.performAction() }
        let size = window.frame.size
        let bottomInset = max(anchorScreen.visibleFrame.minY - anchorScreen.frame.minY, 0)
        window.setFrameOrigin(NSPoint(
            x: anchorScreen.frame.midX - size.width / 2,
            y: anchorScreen.frame.minY + bottomInset + 40 - ToolbarWindow.margin
        ))
        toolbarWindow = window
        toolbarView = toolbar

        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        focusOverlay()
        redraw()
    }

    private func focusOverlay() {
        let screen = toolbarWindow?.screen
        let overlay = overlayWindows.first { $0.screen == screen } ?? overlayWindows.first
        overlay?.makeKey()
    }

    func dismiss() {
        countdownTask?.cancel()
        countdownTask = nil
        countdownWindow?.orderOut(nil)
        countdownWindow = nil
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
        overlayViews.removeAll()
        toolbarWindow?.orderOut(nil)
        toolbarWindow = nil
        toolbarView = nil
        interaction = .idle
        hoveredWindow = nil
        NSCursor.arrow.set()
    }

    func select(_ newMode: CaptureMode) {
        mode = newMode
        preferences.lastMode = newMode.rawValue
        hoveredWindow = nil
        if newMode.target == .window {
            windowCandidates = WindowCandidate.onScreen()
        }
        refreshToolbar()
        redraw()
    }

    func performAction() {
        guard !isCountingDown else { return }
        guard let request = makeRequest() else {
            NSSound.beep()
            return
        }
        if mode.target == .selection, preferences.remembersLastSelection {
            preferences.lastSelection = selection
        }
        begin(request)
    }

    private func begin(_ request: CaptureRequest) {
        let seconds = preferences.timerSeconds
        guard seconds > 0, let toolbarWindow else {
            dismiss()
            onCapture?(request)
            return
        }

        interaction = .idle
        let pill = CountdownPillView(seconds: seconds)
        pill.onCancel = { [weak self] in self?.dismiss() }
        let window = ToolbarWindow(toolbar: pill)
        window.onCancel = { [weak self] in self?.dismiss() }
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(
            x: toolbarWindow.frame.maxX - size.width,
            y: toolbarWindow.frame.minY + (toolbarWindow.frame.height - size.height) / 2
        ))
        toolbarWindow.orderOut(nil)
        window.makeKeyAndOrderFront(nil)
        countdownWindow = window
        redraw()

        countdownTask = Task { [weak self] in
            for remaining in stride(from: seconds, to: 0, by: -1) {
                pill.update(remaining)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            guard let self else { return }
            self.dismiss()
            self.onCapture?(request)
        }
    }

    func cursor(at point: NSPoint) -> NSCursor {
        if isCountingDown { return .arrow }
        switch mode.target {
        case .screen:
            return .pointingHand
        case .window:
            updateHoveredWindow(at: point)
            return .pointingHand
        case .selection:
            if case .moving = interaction { return .closedHand }
            if let selection {
                if let handle = SelectionHandle.hit(point, in: selection) { return handle.cursor }
                if selection.contains(point) { return .openHand }
            }
            return .crosshair
        }
    }

    func mouseDown(at point: NSPoint, screenFrame clickedScreenFrame: NSRect) {
        guard !isCountingDown else { return }
        switch mode.target {
        case .screen:
            guard let screen = NSScreen.screens.first(where: { $0.frame == clickedScreenFrame }), let displayID = screen.displayID else { return }
            begin(CaptureRequest(mode: mode, target: .display(displayID: displayID, screenFrame: screen.frame)))

        case .window:
            updateHoveredWindow(at: point)
            performAction()

        case .selection:
            if let selection, let handle = SelectionHandle.hit(point, in: selection) {
                interaction = .resizing(handle: handle, original: selection, screenFrame: frameOfScreen(containing: selection) ?? clickedScreenFrame)
            } else if let selection, selection.contains(point) {
                interaction = .moving(start: point, original: selection, screenFrame: frameOfScreen(containing: selection) ?? clickedScreenFrame)
                NSCursor.closedHand.set()
            } else {
                interaction = .creating(origin: point, screenFrame: clickedScreenFrame, previous: selection)
            }
        }
    }

    func mouseDragged(to point: NSPoint) {
        switch interaction {
        case .idle:
            return
        case .creating(let origin, let screenFrame, _):
            let end = clamp(point, to: screenFrame)
            selection = NSRect(
                x: min(origin.x, end.x),
                y: min(origin.y, end.y),
                width: abs(end.x - origin.x),
                height: abs(end.y - origin.y)
            )
        case .moving(let start, let original, let screenFrame):
            var moved = original.offsetBy(dx: point.x - start.x, dy: point.y - start.y)
            moved.origin.x = min(max(moved.minX, screenFrame.minX), screenFrame.maxX - moved.width)
            moved.origin.y = min(max(moved.minY, screenFrame.minY), screenFrame.maxY - moved.height)
            selection = moved
        case .resizing(let handle, let original, let screenFrame):
            selection = handle.resize(original, to: clamp(point, to: screenFrame))
        }
        redraw()
    }

    func mouseUp(at point: NSPoint) {
        if case .creating(_, _, let previous) = interaction {
            if let current = selection, current.width >= 8, current.height >= 8 {
                selection = current
            } else {
                selection = previous
            }
        }
        if let current = selection {
            selection = NSRect(
                x: current.minX.rounded(),
                y: current.minY.rounded(),
                width: max(current.width.rounded(), 8),
                height: max(current.height.rounded(), 8)
            )
        }
        interaction = .idle
        if preferences.remembersLastSelection {
            preferences.lastSelection = selection
        }
        redraw()
        cursor(at: point).set()
    }

    private func makeRequest() -> CaptureRequest? {
        switch mode.target {
        case .screen:
            guard let screen = toolbarWindow?.screen ?? NSScreen.underMouse, let displayID = screen.displayID else { return nil }
            return CaptureRequest(mode: mode, target: .display(displayID: displayID, screenFrame: screen.frame))
        case .window:
            guard let hoveredWindow else { return nil }
            return CaptureRequest(mode: mode, target: .window(windowID: hoveredWindow.windowID, frame: hoveredWindow.frame))
        case .selection:
            guard let selection,
                  let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: selection.midX, y: selection.midY)) }),
                  let displayID = screen.displayID else { return nil }
            let clipped = selection.intersection(screen.frame)
            guard clipped.width >= 2, clipped.height >= 2 else { return nil }
            let local = clipped.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
            return CaptureRequest(mode: mode, target: .region(displayID: displayID, screenFrame: screen.frame, localRect: local))
        }
    }

    private func restoreSelection(on screen: NSScreen) {
        if preferences.remembersLastSelection,
           let saved = preferences.lastSelection,
           NSScreen.screens.contains(where: { $0.frame.contains(saved) }) {
            selection = saved
            return
        }
        if let current = selection, NSScreen.screens.contains(where: { $0.frame.contains(current) }) {
            return
        }
        let frame = screen.frame
        let size = NSSize(width: (frame.width * 0.5).rounded(), height: (frame.height * 0.5).rounded())
        selection = NSRect(x: (frame.midX - size.width / 2).rounded(), y: (frame.midY - size.height / 2).rounded(), width: size.width, height: size.height)
    }

    private func updateHoveredWindow(at point: NSPoint) {
        let hit = windowCandidates.first { $0.frame.contains(point) }
        guard hit?.windowID != hoveredWindow?.windowID else { return }
        hoveredWindow = hit
        redraw()
    }

    private func frameOfScreen(containing rect: NSRect) -> NSRect? {
        NSScreen.screens.first { $0.frame.contains(NSPoint(x: rect.midX, y: rect.midY)) }?.frame
    }

    private func clamp(_ point: NSPoint, to frame: NSRect) -> NSPoint {
        NSPoint(x: min(max(point.x, frame.minX), frame.maxX), y: min(max(point.y, frame.minY), frame.maxY))
    }

    private func redraw() {
        overlayViews.forEach { $0.needsDisplay = true }
    }

    func show(recording: Bool) {
        let target = mode.target
        let match = CaptureMode.allCases.first { $0.target == target && $0.isRecording == recording } ?? mode
        if match != mode {
            select(match)
        }
        show()
    }

    func refreshToolbar() {
        toolbarView?.update(mode: mode, timerSeconds: preferences.timerSeconds)
        toolbarWindow?.fitToContent()
    }

    private func showOptions(from anchor: NSView) {
        let menu = optionsMenu.sectionedMenu(isRecording: mode.isRecording)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height + 6), in: anchor)
    }

    private func presentSaveLocationPanel() {
        overlayWindows.forEach { $0.orderOut(nil) }
        toolbarWindow?.orderOut(nil)
        optionsMenu.presentDirectoryPanel { [weak self] in
            guard let self, let toolbarWindow = self.toolbarWindow else { return }
            self.overlayWindows.forEach { $0.orderFrontRegardless() }
            NSApp.activate(ignoringOtherApps: true)
            toolbarWindow.orderFrontRegardless()
            self.focusOverlay()
        }
    }
}
