import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

enum Screenshotter {
    static func capture(_ target: CaptureTarget, showsCursor: Bool) async throws -> CGImage {
        let resolved = try await ResolvedCapture.resolve(target)
        let size = resolved.pixelSize(even: false)
        let configuration = SCStreamConfiguration()
        if let sourceRect = resolved.sourceRect {
            configuration.sourceRect = sourceRect
        }
        configuration.width = size.width
        configuration.height = size.height
        configuration.showsCursor = showsCursor
        configuration.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: resolved.filter, configuration: configuration)
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CaptureError.imageWriteFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CaptureError.imageWriteFailed
        }
    }

    static func copyToClipboard(_ image: CGImage, scale: CGFloat) {
        let size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([NSImage(cgImage: image, size: size)])
    }

    static func playShutterSound() {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        NSSound(contentsOfFile: path, byReference: true)?.play()
    }
}
