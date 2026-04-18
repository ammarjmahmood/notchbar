import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct ClipboardItem: Identifiable, Equatable {
    let id = UUID()
    let type: ItemType
    let name: String
    let url: URL?
    let text: String?
    let dateAdded: Date
    let icon: NSImage?

    enum ItemType {
        case file
        case url
        case text
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }
}

class ClipboardManager: ObservableObject {
    @Published var items: [ClipboardItem] = []

    private let settings = SettingsManager.shared

    var storageDirectory: URL {
        settings.storageDirectory
    }

    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "tif", "svg", "heic", "heif", "ico", "avif"
    ]

    private static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mkv", "webm"
    ]

    private var syncTimer: Timer?
    private var autoClearTimer: Timer?

    init() {
        // Check every 3 seconds if files were deleted manually from the folder
        syncTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.syncWithFileSystem()
        }

        // Auto-clear based on settings
        startAutoClearTimer()
    }

    private func startAutoClearTimer() {
        autoClearTimer?.invalidate()
        let interval = TimeInterval(settings.autoClearMinutes * 60)
        autoClearTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.clearAll()
            }
        }
    }

    /// Remove items whose files no longer exist on disk
    private func syncWithFileSystem() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let before = self.items.count
            self.items.removeAll { item in
                if item.type == .file, let url = item.url {
                    return !FileManager.default.fileExists(atPath: url.path)
                }
                return false
            }
            // Reset auto-clear timer if items changed
            if self.items.count != before && !self.items.isEmpty {
                self.startAutoClearTimer()
            }
        }
    }

    /// Check if a file with the same name (or resolved path) is already in the shelf
    func containsFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return items.contains { $0.type == .file && $0.name == name }
    }

    func addFile(_ url: URL) {
        // Prevent duplicates
        if containsFile(url) { return }

        startAutoClearTimer() // Reset 10-min timer
        let destination = storageDirectory.appendingPathComponent(url.lastPathComponent)
        let finalURL: URL
        if FileManager.default.fileExists(atPath: destination.path) {
            // Could be our own stored copy — check if it's already tracked
            if items.contains(where: { $0.url == destination }) { return }
            let name = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            let uniqueName = "\(name)_\(Int(Date().timeIntervalSince1970)).\(ext)"
            finalURL = storageDirectory.appendingPathComponent(uniqueName)
        } else {
            finalURL = destination
        }

        do {
            try FileManager.default.copyItem(at: url, to: finalURL)
        } catch {
            // If copy fails, reference original
        }

        // For image/video files, generate a real thumbnail; otherwise use the file icon
        let icon: NSImage
        let ext = url.pathExtension.lowercased()
        if Self.imageExtensions.contains(ext), let nsImage = NSImage(contentsOf: url) {
            let thumb = NSImage(size: NSSize(width: 64, height: 64))
            thumb.lockFocus()
            nsImage.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64),
                        from: NSRect(origin: .zero, size: nsImage.size),
                        operation: .sourceOver, fraction: 1.0)
            thumb.unlockFocus()
            icon = thumb
        } else if Self.videoExtensions.contains(ext) {
            icon = Self.generateVideoThumbnail(url: url) ?? NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 64, height: 64)
        } else {
            icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 40, height: 40)
        }

        let item = ClipboardItem(
            type: .file,
            name: url.lastPathComponent,
            url: finalURL,
            text: nil,
            dateAdded: Date(),
            icon: icon
        )

        items.insert(item, at: 0)

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([finalURL as NSURL])
    }

    /// Save raw image data (from browser drag) as a file
    func addImageData(_ data: Data, suggestedName: String? = nil) {
        // Prevent duplicates by name
        if let suggestedName, items.contains(where: { $0.name == suggestedName }) { return }

        startAutoClearTimer()
        let name = suggestedName ?? "image_\(Int(Date().timeIntervalSince1970))"

        // Detect image type from data
        let ext = Self.detectImageExtension(from: data)
        let fileName = name.hasSuffix(".\(ext)") ? name : "\(name).\(ext)"

        var finalURL = storageDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: finalURL.path) {
            let base = finalURL.deletingPathExtension().lastPathComponent
            finalURL = storageDirectory.appendingPathComponent("\(base)_\(Int(Date().timeIntervalSince1970)).\(ext)")
        }

        do {
            try data.write(to: finalURL)
        } catch {
            return
        }

        // Create thumbnail for the icon
        let icon: NSImage
        if let nsImage = NSImage(data: data) {
            let thumb = NSImage(size: NSSize(width: 40, height: 40))
            thumb.lockFocus()
            nsImage.draw(in: NSRect(x: 0, y: 0, width: 40, height: 40),
                        from: NSRect(origin: .zero, size: nsImage.size),
                        operation: .sourceOver, fraction: 1.0)
            thumb.unlockFocus()
            icon = thumb
        } else {
            icon = NSWorkspace.shared.icon(forFile: finalURL.path)
            icon.size = NSSize(width: 40, height: 40)
        }

        let item = ClipboardItem(
            type: .file,
            name: fileName,
            url: finalURL,
            text: nil,
            dateAdded: Date(),
            icon: icon
        )

        items.insert(item, at: 0)

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([finalURL as NSURL])
    }

    /// Download image from a URL and save it
    func addImageURL(_ url: URL) {
        // Download in background
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self, let data, error == nil else { return }

            // Get filename from URL or response
            var fileName = url.lastPathComponent
            if fileName.isEmpty || !fileName.contains(".") {
                let ext = Self.detectImageExtension(from: data)
                fileName = "image_\(Int(Date().timeIntervalSince1970)).\(ext)"
            }
            // Clean up query params from filename
            if let qIndex = fileName.firstIndex(of: "?") {
                fileName = String(fileName[..<qIndex])
            }

            DispatchQueue.main.async {
                self.addImageData(data, suggestedName: fileName)
            }
        }.resume()
    }

    func addURL(_ url: URL) {
        // Prevent duplicates
        if items.contains(where: { $0.type == .url && $0.url == url }) { return }

        // Check if the URL points to an image — download it instead
        let ext = url.pathExtension.lowercased()
        let pathLower = url.absoluteString.lowercased()
        if Self.imageExtensions.contains(ext) || pathLower.contains("image") && (pathLower.contains(".jpg") || pathLower.contains(".png") || pathLower.contains(".webp") || pathLower.contains(".jpeg")) {
            addImageURL(url)
            return
        }

        let item = ClipboardItem(
            type: .url,
            name: url.absoluteString,
            url: url,
            text: nil,
            dateAdded: Date(),
            icon: NSImage(systemSymbolName: "link", accessibilityDescription: nil)
        )

        items.insert(item, at: 0)

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([url as NSURL])
    }

    func addText(_ text: String) {
        // Prevent duplicates
        if items.contains(where: { $0.type == .text && $0.text == text }) { return }

        let item = ClipboardItem(
            type: .text,
            name: String(text.prefix(50)),
            url: nil,
            text: text,
            dateAdded: Date(),
            icon: NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        )

        items.insert(item, at: 0)

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    func copyToClipboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch item.type {
        case .file:
            if let url = item.url {
                pb.writeObjects([url as NSURL])
            }
        case .url:
            if let url = item.url {
                pb.writeObjects([url as NSURL])
            }
        case .text:
            if let text = item.text {
                pb.setString(text, forType: .string)
            }
        }
    }

    func removeItem(_ item: ClipboardItem) {
        if item.type == .file, let url = item.url {
            try? FileManager.default.removeItem(at: url)
        }
        items.removeAll { $0.id == item.id }
    }

    func clearAll() {
        for item in items {
            if item.type == .file, let url = item.url {
                try? FileManager.default.removeItem(at: url)
            }
        }
        items.removeAll()
    }

    // Generate a thumbnail from a video file
    static func generateVideoThumbnail(url: URL) -> NSImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 128, height: 128)
        let time = CMTime(seconds: 1, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    // Detect image format from raw data bytes
    private static func detectImageExtension(from data: Data) -> String {
        guard data.count >= 4 else { return "png" }
        let bytes = [UInt8](data.prefix(4))

        if bytes[0] == 0x89 && bytes[1] == 0x50 { return "png" }
        if bytes[0] == 0xFF && bytes[1] == 0xD8 { return "jpg" }
        if bytes[0] == 0x47 && bytes[1] == 0x49 { return "gif" }
        if bytes[0] == 0x52 && bytes[1] == 0x49 { return "webp" }
        if bytes[0] == 0x42 && bytes[1] == 0x4D { return "bmp" }
        if bytes[0] == 0x49 && bytes[1] == 0x49 { return "tiff" }
        if bytes[0] == 0x4D && bytes[1] == 0x4D { return "tiff" }
        return "png"
    }
}
