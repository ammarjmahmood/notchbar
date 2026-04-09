import AppKit
import SwiftUI

class NotchWindow: NSPanel {
    var viewModel: NotchViewModel?

    private var moveMonitor: Any?
    private var isMouseInNotch = false

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)

        isOpaque = false
        backgroundColor = .clear
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovable = false
        isReleasedWhenClosed = false
        hasShadow = false
        level = .mainMenu + 3
        collectionBehavior = [.stationary, .canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { !ignoresMouseEvents }
    override var canBecomeMain: Bool { false }

    func startHoverMonitoring() {
        // Use a global mouse-moved monitor to detect when the cursor
        // reaches the very top of the screen over the notch area.
        // This avoids any tracking areas on the window itself.
        moveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.checkMouseLocation()
        }

        // Also monitor local events when the window is active (expanded)
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.checkMouseLocation()
            return event
        }
    }

    private func checkMouseLocation() {
        guard let vm = viewModel, let screen = NSScreen.main else { return }

        let mouse = NSEvent.mouseLocation
        let screenFrame = screen.frame

        if vm.isExpanded {
            // When expanded, check if mouse is within the expanded tray bounds
            let trayWidth = vm.openSize.width
            let trayHeight = vm.openSize.height
            let trayMinX = screenFrame.midX - trayWidth / 2
            let trayMaxX = screenFrame.midX + trayWidth / 2
            let trayMinY = screenFrame.maxY - trayHeight

            let inExpandedArea = mouse.x >= trayMinX && mouse.x <= trayMaxX
                && mouse.y >= trayMinY && mouse.y <= screenFrame.maxY

            if !inExpandedArea && !vm.dropTargeting && !vm.isDraggingOverNotch {
                DispatchQueue.main.async {
                    vm.isHovering = false
                    vm.collapse()
                }
                isMouseInNotch = false
            }
        } else {
            // When collapsed, only trigger on the top 6px of the screen within notch width
            let notchWidth = vm.closedSize.width
            let notchMinX = screenFrame.midX - notchWidth / 2
            let notchMaxX = screenFrame.midX + notchWidth / 2
            let triggerZoneTop = screenFrame.maxY
            let triggerZoneBottom = screenFrame.maxY - 6

            let inNotch = mouse.x >= notchMinX && mouse.x <= notchMaxX
                && mouse.y >= triggerZoneBottom && mouse.y <= triggerZoneTop

            if inNotch && !isMouseInNotch {
                isMouseInNotch = true
                DispatchQueue.main.async {
                    vm.isHovering = true
                    vm.expand()
                }
            } else if !inNotch {
                isMouseInNotch = false
            }
        }
    }

    deinit {
        if let monitor = moveMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// Custom drop view that wraps the SwiftUI content and handles ALL drag types via AppKit
class DropHostingView<Content: View>: NSHostingView<Content> {
    var viewModel: NotchViewModel?

    required init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes([
            .fileURL,
            .URL,
            .string,
            .tiff,
            .png,
            .pdf
        ])
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let vm = viewModel, vm.isExpanded else {
            // Auto-expand when dragging over
            DispatchQueue.main.async {
                self.viewModel?.expand()
                self.viewModel?.dropTargeting = true
            }
            return .copy
        }
        DispatchQueue.main.async {
            self.viewModel?.dropTargeting = true
        }
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        DispatchQueue.main.async {
            self.viewModel?.dropTargeting = false
        }
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let vm = viewModel else { return false }

        let pasteboard = sender.draggingPasteboard

        // 1. Handle local file URLs first (any file type — preserves original format)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty {
            DispatchQueue.main.async {
                for url in urls {
                    vm.clipboardManager.addFile(url)
                }
                vm.dropTargeting = false
            }
            return true
        }

        // 2. Handle web URLs (image URLs get downloaded in original format)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            DispatchQueue.main.async {
                for url in urls {
                    vm.clipboardManager.addURL(url)
                }
                vm.dropTargeting = false
            }
            return true
        }

        // 3. Fall back to raw image data only if no URL is available
        if let pngData = pasteboard.data(forType: .png) {
            DispatchQueue.main.async {
                vm.clipboardManager.addImageData(pngData)
                vm.dropTargeting = false
            }
            return true
        }

        if let tiffData = pasteboard.data(forType: .tiff) {
            DispatchQueue.main.async {
                vm.clipboardManager.addImageData(tiffData)
                vm.dropTargeting = false
            }
            return true
        }

        // 4. Handle text
        if let strings = pasteboard.readObjects(forClasses: [NSString.self]) as? [String], !strings.isEmpty {
            DispatchQueue.main.async {
                for text in strings {
                    vm.clipboardManager.addText(text)
                }
                vm.dropTargeting = false
            }
            return true
        }

        return false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        DispatchQueue.main.async {
            self.viewModel?.dropTargeting = false
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let vm = viewModel, vm.isExpanded else {
            super.rightMouseDown(with: event)
            return
        }

        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(showSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let clearItem = NSMenuItem(title: "Clear All", action: #selector(clearAll), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        let openItem = NSMenuItem(title: "Open Storage Folder", action: #selector(openStorageFolder), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func showSettings() {
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                self.viewModel?.selectedTab = .settings
            }
        }
    }

    @objc private func clearAll() {
        viewModel?.clipboardManager.clearAll()
    }

    @objc private func openStorageFolder() {
        if let url = viewModel?.clipboardManager.storageDirectory {
            NSWorkspace.shared.open(url)
        }
    }
}
