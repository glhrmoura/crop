import AppKit
import AVFoundation

@MainActor
final class OptionsMenu: NSObject {
    var onChange: (() -> Void)?
    var onChooseLocation: (() -> Void)?

    private let preferences = Preferences.shared

    func sectionedMenu(isRecording: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(.sectionHeader(title: L("Save to")))
        saveItems(isRecording: isRecording).forEach(menu.addItem)

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: L("Timer")))
        timerItems().forEach(menu.addItem)

        if isRecording {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: L("Microphone")))
            microphoneItems().forEach(menu.addItem)
        }

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: L("Options")))
        toggleItems(isRecording: isRecording).forEach(menu.addItem)

        if isRecording {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: L("Frame Rate")))
            frameRateItems().forEach(menu.addItem)
        }
        return menu
    }

    func submenuItem(_ title: String, symbol: String, items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        items.forEach(submenu.addItem)
        item.submenu = submenu
        return item
    }

    func saveItems(isRecording: Bool) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let currentDirectory = preferences.saveDirectory.standardizedFileURL
        var locations = [Preferences.desktopDirectory, Preferences.documentsDirectory, Preferences.moviesDirectory]
        if let custom = preferences.customSaveDirectory?.standardizedFileURL,
           !locations.map(\.standardizedFileURL).contains(custom) {
            locations.append(custom)
        }
        let usesClipboard = !isRecording && preferences.screenshotsToClipboard
        for location in locations {
            let item = menuItem(FileManager.default.displayName(atPath: location.path), #selector(selectSaveLocation(_:)))
            item.representedObject = location
            item.toolTip = location.path
            item.state = !usesClipboard && location.standardizedFileURL == currentDirectory ? .on : .off
            items.append(item)
        }
        let clipboardItem = menuItem(L("Clipboard"), #selector(selectClipboard))
        clipboardItem.state = usesClipboard ? .on : .off
        clipboardItem.isEnabled = !isRecording
        if !isRecording {
            clipboardItem.toolTip = L("Screenshots only")
        }
        items.append(clipboardItem)
        items.append(menuItem(L("Other Location…"), #selector(chooseSaveLocation)))
        return items
    }

    func timerItems() -> [NSMenuItem] {
        [0, 5, 10].map { seconds in
            let title = seconds == 0 ? L("None") : String(format: L("%d Seconds"), seconds)
            let item = menuItem(title, #selector(selectTimer(_:)))
            item.tag = seconds
            item.state = preferences.timerSeconds == seconds ? .on : .off
            return item
        }
    }

    func microphoneItems() -> [NSMenuItem] {
        let noneItem = menuItem(L("None"), #selector(selectMicrophone(_:)))
        noneItem.state = preferences.microphoneID == nil ? .on : .off
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
        return [noneItem] + devices.map { device in
            let item = menuItem(device.localizedName, #selector(selectMicrophone(_:)))
            item.representedObject = device.uniqueID
            item.state = preferences.microphoneID == device.uniqueID ? .on : .off
            return item
        }
    }

    func frameRateItems() -> [NSMenuItem] {
        [24, 30, 60].map { rate in
            let item = menuItem("\(rate) fps", #selector(selectFrameRate(_:)))
            item.tag = rate
            item.state = preferences.framesPerSecond == rate ? .on : .off
            return item
        }
    }

    func toggleItems(isRecording: Bool) -> [NSMenuItem] {
        var items = [toggleItem(L("Show Mouse Pointer"), preferences.showsCursor, #selector(toggleCursor))]
        if isRecording {
            items.append(toggleItem(L("Show Mouse Clicks"), preferences.showsClicks, #selector(toggleClicks)))
            items.append(toggleItem(L("Capture System Audio"), preferences.capturesSystemAudio, #selector(toggleSystemAudio)))
        }
        items.append(toggleItem(L("Remember Last Selection"), preferences.remembersLastSelection, #selector(toggleRememberSelection)))
        items.append(toggleItem(L("Open When Done"), preferences.opensWhenDone, #selector(toggleOpenWhenDone)))
        return items
    }

    func presentDirectoryPanel(completion: @escaping () -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("Choose")
        panel.directoryURL = preferences.saveDirectory
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            MainActor.assumeIsolated {
                if response == .OK, let url = panel.url, let self {
                    self.preferences.customSaveDirectory = url
                    self.preferences.screenshotsToClipboard = false
                    self.onChange?()
                }
                completion()
            }
        }
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func toggleItem(_ title: String, _ isOn: Bool, _ action: Selector) -> NSMenuItem {
        let item = menuItem(title, action)
        item.state = isOn ? .on : .off
        return item
    }

    @objc private func selectSaveLocation(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        preferences.customSaveDirectory = url
        preferences.screenshotsToClipboard = false
        onChange?()
    }

    @objc private func selectClipboard() {
        preferences.screenshotsToClipboard = true
        onChange?()
    }

    @objc private func chooseSaveLocation() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let onChooseLocation = self.onChooseLocation {
                onChooseLocation()
            } else {
                self.presentDirectoryPanel {}
            }
        }
    }

    @objc private func selectTimer(_ sender: NSMenuItem) {
        preferences.timerSeconds = sender.tag
        onChange?()
    }

    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        preferences.microphoneID = sender.representedObject as? String
        onChange?()
    }

    @objc private func toggleCursor() {
        preferences.showsCursor.toggle()
        onChange?()
    }

    @objc private func toggleClicks() {
        preferences.showsClicks.toggle()
        onChange?()
    }

    @objc private func toggleSystemAudio() {
        preferences.capturesSystemAudio.toggle()
        onChange?()
    }

    @objc private func toggleRememberSelection() {
        preferences.remembersLastSelection.toggle()
        if !preferences.remembersLastSelection {
            preferences.lastSelection = nil
        }
        onChange?()
    }

    @objc private func toggleOpenWhenDone() {
        preferences.opensWhenDone.toggle()
        onChange?()
    }

    @objc private func selectFrameRate(_ sender: NSMenuItem) {
        preferences.framesPerSecond = sender.tag
        onChange?()
    }
}
