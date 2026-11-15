import AppKit
import AVFoundation
import ScreenCaptureKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let screenRecordingSettingsURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture")!

    private let preferences = Preferences.shared
    private let recorder = Recorder()
    private let captureController = CaptureController()
    private let recordingMask = RecordingMask()
    private let optionsMenu = OptionsMenu()

    private var statusItem: NSStatusItem!
    private var isBusy = false
    private var pendingTerminationReply = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "rectangle.dashed.badge.record", accessibilityDescription: "Crop")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Crop"
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        optionsMenu.onChange = { [weak self] in self?.captureController.refreshToolbar() }
        recorder.onFinish = { [weak self] result in
            self?.recordingDidFinish(result)
        }
        captureController.onCapture = { [weak self] request in
            self?.handle(request)
        }
        warmUpMenu(menu)
    }

    private func warmUpMenu(_ menu: NSMenu) {
        Task {
            await Task.detached(priority: .userInitiated) {
                _ = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.microphone, .external],
                    mediaType: .audio,
                    position: .unspecified
                ).devices
            }.value
            menuNeedsUpdate(menu)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if recorder.isRecording {
            stopRecording()
        } else {
            showCaptureToolbar(recording: true)
        }
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard recorder.isRecording else { return .terminateNow }
        pendingTerminationReply = true
        Task { await recorder.stop() }
        return .terminateLater
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(actionItem(L("Record Screen"), symbol: "record.circle", #selector(recordScreen)))
        menu.addItem(actionItem(L("Take Screenshot"), symbol: "camera.viewfinder", #selector(takeScreenshotFromMenu)))

        menu.addItem(.separator())
        menu.addItem(optionsMenu.submenuItem(L("Save to"), symbol: "folder", items: optionsMenu.saveItems(isRecording: false)))
        menu.addItem(optionsMenu.submenuItem(L("Timer"), symbol: "timer", items: optionsMenu.timerItems()))
        menu.addItem(optionsMenu.submenuItem(L("Microphone"), symbol: "mic", items: optionsMenu.microphoneItems()))
        menu.addItem(optionsMenu.submenuItem(L("Frame Rate"), symbol: "film", items: optionsMenu.frameRateItems()))

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: L("Options")))
        optionsMenu.toggleItems(isRecording: true).forEach(menu.addItem)

        menu.addItem(.separator())
        let launchItem = actionItem(L("Open at Login"), symbol: nil, #selector(toggleLaunchAtLogin))
        launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())
        menu.addItem(actionItem(L("About Crop"), symbol: nil, #selector(showAbout)))
        menu.addItem(actionItem(L("Quit Crop"), symbol: nil, #selector(quit), key: "q"))
    }

    private func actionItem(_ title: String, symbol: String?, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        return item
    }

    @objc private func recordScreen() {
        showCaptureToolbar(recording: true)
    }

    @objc private func takeScreenshotFromMenu() {
        showCaptureToolbar(recording: false)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            present(error, title: L("Couldn’t change login item"))
        }
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showCaptureToolbar(recording: Bool) {
        guard !recorder.isRecording, !isBusy else { return }
        isBusy = true
        Task {
            let granted = await ensureScreenRecordingAccess()
            isBusy = false
            if granted {
                captureController.show(recording: recording)
            }
        }
    }

    private func stopRecording() {
        guard recorder.isRecording else { return }
        Task { await recorder.stop() }
    }

    private func handle(_ request: CaptureRequest) {
        isBusy = true
        Task {
            defer { isBusy = false }
            if request.mode.isRecording {
                await startRecording(request)
            } else {
                await takeScreenshot(request)
            }
        }
    }

    private func takeScreenshot(_ request: CaptureRequest) async {
        do {
            let image = try await Screenshotter.capture(request.target, showsCursor: preferences.showsCursor)
            Screenshotter.playShutterSound()
            if preferences.screenshotsToClipboard {
                let scale = request.target.screen?.backingScaleFactor ?? 2
                Screenshotter.copyToClipboard(image, scale: scale)
                return
            }
            let url = try makeOutputURL(prefix: L("Screenshot"), pathExtension: "png")
            try Screenshotter.writePNG(image, to: url)
            if preferences.opensWhenDone {
                NSWorkspace.shared.open(url)
            }
        } catch {
            present(error, title: L("Couldn’t take screenshot"))
        }
    }

    private func startRecording(_ request: CaptureRequest) async {
        do {
            let microphoneID = await authorizedMicrophoneID()
            let url = try makeOutputURL(prefix: L("Screen Recording"), pathExtension: "mov")
            let options = RecordingOptions(
                framesPerSecond: preferences.framesPerSecond,
                showsCursor: preferences.showsCursor,
                showsClicks: preferences.showsClicks,
                capturesSystemAudio: preferences.capturesSystemAudio,
                microphoneID: microphoneID
            )
            try await recorder.start(target: request.target, options: options, outputURL: url)
            recordingDidStart(request)
        } catch {
            present(error, title: L("Couldn’t start recording"))
        }
    }

    private func ensureScreenRecordingAccess() async -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        if (try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)) != nil {
            return true
        }
        if CGRequestScreenCaptureAccess() || CGPreflightScreenCaptureAccess() {
            return true
        }
        let alert = NSAlert()
        alert.messageText = L("Crop needs permission to record your screen")
        alert.informativeText = L("Allow Crop in System Settings › Privacy & Security › Screen & System Audio Recording, then try again.")
        alert.addButton(withTitle: L("Open System Settings"))
        alert.addButton(withTitle: L("Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(Self.screenRecordingSettingsURL)
        }
        return false
    }

    private func authorizedMicrophoneID() async -> String? {
        guard let microphoneID = preferences.microphoneID else { return nil }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return microphoneID
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio) ? microphoneID : nil
        default:
            return nil
        }
    }

    private func recordingDidStart(_ request: CaptureRequest) {
        ProcessInfo.processInfo.disableSuddenTermination()
        ProcessInfo.processInfo.disableAutomaticTermination("Crop is recording the screen.")
        statusItem.isVisible = false
        if let rect = request.target.recordedRect {
            recordingMask.show(around: rect)
        }
    }

    private func recordingDidFinish(_ result: Result<URL, Error>) {
        recordingMask.hide()
        statusItem.isVisible = true
        ProcessInfo.processInfo.enableSuddenTermination()
        ProcessInfo.processInfo.enableAutomaticTermination("Crop is recording the screen.")

        if pendingTerminationReply {
            pendingTerminationReply = false
            NSApp.reply(toApplicationShouldTerminate: true)
            return
        }

        switch result {
        case .success(let url):
            if preferences.opensWhenDone {
                NSWorkspace.shared.open(url)
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        case .failure(let error):
            present(error, title: L("Recording failed"))
        }
    }

    private func makeOutputURL(prefix: String, pathExtension: String) throws -> URL {
        let directory = preferences.saveDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: "at", with: L("at"))
        let baseName = "\(prefix) \(stamp)"
        var url = directory.appendingPathComponent(baseName).appendingPathExtension(pathExtension)
        var index = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(baseName) \(index)").appendingPathExtension(pathExtension)
            index += 1
        }
        return url
    }

    private func present(_ error: Error, title: String) {
        let alert = NSAlert(error: error)
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
