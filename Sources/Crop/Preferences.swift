import AppKit

func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let microphoneID = "microphoneID"
        static let capturesSystemAudio = "capturesSystemAudio"
        static let showsCursor = "showsCursor"
        static let showsClicks = "showsClicks"
        static let framesPerSecond = "framesPerSecond"
        static let saveDirectory = "saveDirectory"
        static let screenshotsToClipboard = "screenshotsToClipboard"
        static let opensWhenDone = "opensWhenDone"
        static let timerSeconds = "timerSeconds"
        static let remembersLastSelection = "remembersLastSelection"
        static let lastSelection = "lastSelection"
        static let lastMode = "lastMode"
    }

    private init() {
        defaults.register(defaults: [
            Key.capturesSystemAudio: false,
            Key.showsCursor: true,
            Key.showsClicks: false,
            Key.framesPerSecond: 60,
            Key.screenshotsToClipboard: false,
            Key.opensWhenDone: false,
            Key.timerSeconds: 0,
            Key.remembersLastSelection: true,
            Key.lastMode: CaptureMode.recordSelection.rawValue
        ])
    }

    var microphoneID: String? {
        get { defaults.string(forKey: Key.microphoneID) }
        set { defaults.set(newValue, forKey: Key.microphoneID) }
    }

    var capturesSystemAudio: Bool {
        get { defaults.bool(forKey: Key.capturesSystemAudio) }
        set { defaults.set(newValue, forKey: Key.capturesSystemAudio) }
    }

    var showsCursor: Bool {
        get { defaults.bool(forKey: Key.showsCursor) }
        set { defaults.set(newValue, forKey: Key.showsCursor) }
    }

    var showsClicks: Bool {
        get { defaults.bool(forKey: Key.showsClicks) }
        set { defaults.set(newValue, forKey: Key.showsClicks) }
    }

    var framesPerSecond: Int {
        get { defaults.integer(forKey: Key.framesPerSecond) }
        set { defaults.set(newValue, forKey: Key.framesPerSecond) }
    }

    var screenshotsToClipboard: Bool {
        get { defaults.bool(forKey: Key.screenshotsToClipboard) }
        set { defaults.set(newValue, forKey: Key.screenshotsToClipboard) }
    }

    var opensWhenDone: Bool {
        get { defaults.bool(forKey: Key.opensWhenDone) }
        set { defaults.set(newValue, forKey: Key.opensWhenDone) }
    }

    var timerSeconds: Int {
        get { defaults.integer(forKey: Key.timerSeconds) }
        set { defaults.set(newValue, forKey: Key.timerSeconds) }
    }

    var remembersLastSelection: Bool {
        get { defaults.bool(forKey: Key.remembersLastSelection) }
        set { defaults.set(newValue, forKey: Key.remembersLastSelection) }
    }

    var lastSelection: NSRect? {
        get {
            guard let value = defaults.string(forKey: Key.lastSelection) else { return nil }
            let rect = NSRectFromString(value)
            return rect.isEmpty ? nil : rect
        }
        set { defaults.set(newValue.map { NSStringFromRect($0) }, forKey: Key.lastSelection) }
    }

    var lastMode: Int {
        get { defaults.integer(forKey: Key.lastMode) }
        set { defaults.set(newValue, forKey: Key.lastMode) }
    }

    var customSaveDirectory: URL? {
        get { defaults.url(forKey: Key.saveDirectory) }
        set { defaults.set(newValue, forKey: Key.saveDirectory) }
    }

    static var moviesDirectory: URL {
        directory(.moviesDirectory, fallback: "Movies")
    }

    static var desktopDirectory: URL {
        directory(.desktopDirectory, fallback: "Desktop")
    }

    static var documentsDirectory: URL {
        directory(.documentDirectory, fallback: "Documents")
    }

    private static func directory(_ kind: FileManager.SearchPathDirectory, fallback: String) -> URL {
        FileManager.default.urls(for: kind, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(fallback)
    }

    var saveDirectory: URL {
        customSaveDirectory ?? Self.moviesDirectory
    }
}
