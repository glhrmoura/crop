import AppKit
import ScreenCaptureKit

enum CaptureMode: Int, CaseIterable {
    case screenshotScreen
    case screenshotWindow
    case screenshotSelection
    case recordScreen
    case recordWindow
    case recordSelection

    enum Target {
        case screen
        case window
        case selection
    }

    var target: Target {
        switch self {
        case .screenshotScreen, .recordScreen: return .screen
        case .screenshotWindow, .recordWindow: return .window
        case .screenshotSelection, .recordSelection: return .selection
        }
    }

    var isRecording: Bool {
        switch self {
        case .recordScreen, .recordWindow, .recordSelection: return true
        default: return false
        }
    }

    var title: String {
        switch self {
        case .screenshotScreen: return L("Capture Entire Screen")
        case .screenshotWindow: return L("Capture Selected Window")
        case .screenshotSelection: return L("Capture Selected Portion")
        case .recordScreen: return L("Record Entire Screen")
        case .recordWindow: return L("Record Selected Window")
        case .recordSelection: return L("Record Selected Portion")
        }
    }

    var actionTitle: String {
        isRecording ? L("Record") : L("Capture")
    }
}

enum CaptureTarget {
    case display(displayID: CGDirectDisplayID, screenFrame: NSRect)
    case window(windowID: CGWindowID, frame: NSRect)
    case region(displayID: CGDirectDisplayID, screenFrame: NSRect, localRect: NSRect)

    var displayID: CGDirectDisplayID? {
        switch self {
        case .display(let id, _), .region(let id, _, _): return id
        case .window: return nil
        }
    }

    var recordedRect: NSRect? {
        switch self {
        case .display: return nil
        case .window(_, let frame): return frame
        case .region(_, let screenFrame, let localRect):
            return localRect.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)
        }
    }

    var screen: NSScreen? {
        switch self {
        case .display(let id, _), .region(let id, _, _):
            return NSScreen.screens.first { $0.displayID == id }
        case .window(_, let frame):
            return NSScreen.screens.first { $0.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) } ?? NSScreen.main
        }
    }
}

struct CaptureRequest {
    let mode: CaptureMode
    let target: CaptureTarget
}

enum CaptureError: LocalizedError {
    case alreadyRecording
    case displayUnavailable
    case windowUnavailable
    case emptySelection
    case imageWriteFailed

    var errorDescription: String? {
        switch self {
        case .alreadyRecording: return L("A recording is already in progress.")
        case .displayUnavailable: return L("The selected display is no longer available.")
        case .windowUnavailable: return L("The selected window is no longer available.")
        case .emptySelection: return L("The selected area is empty.")
        case .imageWriteFailed: return L("The image could not be saved.")
        }
    }
}

struct ResolvedCapture {
    let filter: SCContentFilter
    let sourceRect: CGRect?
    let pointSize: CGSize

    var scale: CGFloat { CGFloat(filter.pointPixelScale) }

    func pixelSize(even: Bool) -> (width: Int, height: Int) {
        func convert(_ value: CGFloat) -> Int {
            let rounded = max(2, Int((value * scale).rounded()))
            return even ? rounded - rounded % 2 : rounded
        }
        return (convert(pointSize.width), convert(pointSize.height))
    }

    static func resolve(_ target: CaptureTarget) async throws -> ResolvedCapture {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let processID = ProcessInfo.processInfo.processIdentifier
        let ownApplications = content.applications.filter { $0.processID == processID }

        switch target {
        case .display(let displayID, _):
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw CaptureError.displayUnavailable
            }
            let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
            return ResolvedCapture(filter: filter, sourceRect: nil, pointSize: CGSize(width: display.width, height: display.height))

        case .region(let displayID, let screenFrame, let localRect):
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw CaptureError.displayUnavailable
            }
            let bounds = CGRect(x: 0, y: 0, width: display.width, height: display.height)
            let flipped = CGRect(
                x: localRect.minX,
                y: screenFrame.height - localRect.maxY,
                width: localRect.width,
                height: localRect.height
            )
            let rect = flipped.intersection(bounds).integral
            guard !rect.isEmpty else { throw CaptureError.emptySelection }
            let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
            return ResolvedCapture(filter: filter, sourceRect: rect, pointSize: rect.size)

        case .window(let windowID, _):
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw CaptureError.windowUnavailable
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            return ResolvedCapture(filter: filter, sourceRect: nil, pointSize: filter.contentRect.size)
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    static var underMouse: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(location, $0.frame, false) } ?? main
    }
}

struct WindowCandidate {
    let windowID: CGWindowID
    let frame: NSRect

    static func onScreen() -> [WindowCandidate] {
        guard let primaryHeight = NSScreen.screens.first?.frame.height,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let ownProcessID = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32) != ownProcessID,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let number = info[kCGWindowNumber as String] as? UInt32,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  bounds.width >= 40, bounds.height >= 40 else {
                return nil
            }
            let frame = NSRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
            return WindowCandidate(windowID: CGWindowID(number), frame: frame)
        }
    }
}
