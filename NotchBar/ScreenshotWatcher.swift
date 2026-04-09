import Foundation
import AppKit

class ScreenshotWatcher: ObservableObject {
    @Published var screenshots: [ClipboardItem] = []

    private let settings = SettingsManager.shared
    private var knownFiles: Set<String> = []
    private var pollTimer: Timer?
    private var pasteboardTimer: Timer?
    private var lastPasteboardCount: Int = 0

    private static let screenshotPrefixes = ["Screenshot ", "Screen Recording "]
    private static let screenshotExtensions: Set<String> = ["png", "jpg", "jpeg", "tiff", "gif", "mov", "mp4"]

    init() {
        NSLog("[ScreenshotWatcher] init called")
        snapshotExistingFiles()
        lastPasteboardCount = NSPasteboard.general.changeCount
    }

    func start() {
        NSLog("[ScreenshotWatcher] start() called")
        stopWatching()

        pollTimer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkForNewScreenshots()
        }
        RunLoop.main.add(pollTimer!, forMode: .common)

        pasteboardTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkPasteboardForScreenshot()
        }
        RunLoop.main.add(pasteboardTimer!, forMode: .common)

        NSLog("[ScreenshotWatcher] Timers added to RunLoop")
    }

    private func snapshotExistingFiles() {
        let dir = settings.screenshotDirectory
        NSLog("[ScreenshotWatcher] Watching: %@", dir.path)

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else {
            NSLog("[ScreenshotWatcher] ERROR: Cannot list directory")
            return
        }

        for url in contents where Self.isScreenshot(url) {
            knownFiles.insert(url.lastPathComponent)
        }
        NSLog("[ScreenshotWatcher] Skipping %d existing screenshots", knownFiles.count)
    }

    func stopWatching() {
        pollTimer?.invalidate()
        pollTimer = nil
        pasteboardTimer?.invalidate()
        pasteboardTimer = nil
    }

    // MARK: - File-based screenshots

    private func checkForNewScreenshots() {
        let dir = settings.screenshotDirectory

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }

        for url in contents {
            let name = url.lastPathComponent
            guard Self.isScreenshot(url), !knownFiles.contains(name) else { continue }

            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? Int, size > 0 else { continue }

            NSLog("[ScreenshotWatcher] NEW: %@", name)
            knownFiles.insert(name)

            let icon = Self.makeThumbnail(for: url)
            let item = ClipboardItem(
                type: .file,
                name: name,
                url: url,
                text: nil,
                dateAdded: Date(),
                icon: icon
            )

            DispatchQueue.main.async {
                self.screenshots.insert(item, at: 0)
                NSLog("[ScreenshotWatcher] Added to list, count: %d", self.screenshots.count)
            }
        }
    }

    // MARK: - Clipboard screenshots

    private func checkPasteboardForScreenshot() {
        let pb = NSPasteboard.general
        let currentCount = pb.changeCount
        guard currentCount != lastPasteboardCount else { return }
        lastPasteboardCount = currentCount

        guard let types = pb.types,
              (types.contains(.png) || types.contains(.tiff)) else { return }

        // Skip if pasteboard has file URLs (our own copy or a file drag)
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty { return }

        let imageData: Data?
        if let png = pb.data(forType: .png) {
            imageData = png
        } else if let tiff = pb.data(forType: .tiff) {
            imageData = tiff
        } else {
            return
        }

        guard let data = imageData, let nsImage = NSImage(data: data) else { return }

        NSLog("[ScreenshotWatcher] Clipboard screenshot detected")

        let thumb = NSImage(size: NSSize(width: 40, height: 40))
        thumb.lockFocus()
        nsImage.draw(in: NSRect(x: 0, y: 0, width: 40, height: 40),
                    from: NSRect(origin: .zero, size: nsImage.size),
                    operation: .sourceOver, fraction: 1.0)
        thumb.unlockFocus()

        let timestamp = Int(Date().timeIntervalSince1970)
        let item = ClipboardItem(
            type: .file,
            name: "Screenshot \(timestamp)",
            url: nil,
            text: nil,
            dateAdded: Date(),
            icon: thumb
        )

        DispatchQueue.main.async {
            self.screenshots.insert(item, at: 0)
            NSLog("[ScreenshotWatcher] Clipboard screenshot added, count: %d", self.screenshots.count)
        }
    }

    // MARK: - Helpers

    private static func isScreenshot(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        guard screenshotExtensions.contains(ext) else { return false }
        return screenshotPrefixes.contains { name.hasPrefix($0) }
    }

    private static func makeThumbnail(for url: URL) -> NSImage {
        if let nsImage = NSImage(contentsOf: url) {
            let thumb = NSImage(size: NSSize(width: 40, height: 40))
            thumb.lockFocus()
            nsImage.draw(in: NSRect(x: 0, y: 0, width: 40, height: 40),
                        from: NSRect(origin: .zero, size: nsImage.size),
                        operation: .sourceOver, fraction: 1.0)
            thumb.unlockFocus()
            return thumb
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 40, height: 40)
        return icon
    }

    func restartWithNewFolder() {
        knownFiles.removeAll()
        screenshots.removeAll()
        snapshotExistingFiles()
        start()
    }

    func removeScreenshot(_ item: ClipboardItem) {
        screenshots.removeAll { $0.id == item.id }
    }

    func clearAll() {
        screenshots.removeAll()
    }

    func copyToClipboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let url = item.url {
            pb.writeObjects([url as NSURL])
        }
    }

    deinit {
        stopWatching()
    }
}
