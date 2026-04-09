import Foundation
import ServiceManagement

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private enum Keys {
        static let storageFolderPath = "storageFolderPath"
        static let autoClearMinutes = "autoClearMinutes"
        static let screenshotFolderPath = "screenshotFolderPath"
        static let launchAtLogin = "launchAtLogin"
    }

    @Published var storageFolderPath: String {
        didSet { UserDefaults.standard.set(storageFolderPath, forKey: Keys.storageFolderPath) }
    }

    @Published var autoClearMinutes: Int {
        didSet { UserDefaults.standard.set(autoClearMinutes, forKey: Keys.autoClearMinutes) }
    }

    @Published var screenshotFolderPath: String {
        didSet { UserDefaults.standard.set(screenshotFolderPath, forKey: Keys.screenshotFolderPath) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin)
            updateLaunchAtLogin()
        }
    }

    var storageDirectory: URL {
        let url = URL(fileURLWithPath: (storageFolderPath as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    var screenshotDirectory: URL {
        URL(fileURLWithPath: (screenshotFolderPath as NSString).expandingTildeInPath, isDirectory: true)
    }

    private init() {
        let defaults = UserDefaults.standard

        // Storage folder
        let defaultStorage = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchBoard", isDirectory: true).path
        self.storageFolderPath = defaults.string(forKey: Keys.storageFolderPath) ?? defaultStorage

        // Auto-clear minutes
        let savedMinutes = defaults.integer(forKey: Keys.autoClearMinutes)
        self.autoClearMinutes = savedMinutes > 0 ? savedMinutes : 10

        // Screenshot folder — try reading macOS screencapture preference
        let defaultScreenshotPath = Self.detectScreenshotFolder()
        self.screenshotFolderPath = defaults.string(forKey: Keys.screenshotFolderPath) ?? defaultScreenshotPath

        // Launch at login
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
    }

    private static func detectScreenshotFolder() -> String {
        if let pref = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            return pref
        }
        return ("~/Desktop" as NSString).expandingTildeInPath
    }

    private func updateLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update launch at login: \(error)")
            }
        }
    }
}
