import SwiftUI
import AppKit

@main
struct NotchBoardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var notchWindow: NotchWindow?
    var viewModel: NotchViewModel!
    var dragDetector: DragDetector!
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewModel = NotchViewModel()
        dragDetector = DragDetector()

        setupDragDetector()
        setupNotchWindow()
        setupStatusBarItem()
        viewModel.screenshotWatcher.start()
    }

    private func setupDragDetector() {
        dragDetector.onDragBegan = { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.viewModel.isDraggingOverNotch = true
            }
        }

        dragDetector.onDragEnded = { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.viewModel.isDraggingOverNotch = false
                self.viewModel.collapse()
            }
        }

        dragDetector.onDragEnteredNotch = { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.viewModel.expand()
            }
        }

        dragDetector.startMonitoring()
    }

    private func setupNotchWindow() {
        guard let screen = NSScreen.main else { return }

        let windowWidth: CGFloat = 750
        let windowHeight: CGFloat = 300

        let originX = screen.frame.midX - windowWidth / 2
        let originY = screen.frame.maxY - windowHeight

        let contentView = NotchContentView(viewModel: viewModel)

        let hostingView = DropHostingView(rootView: contentView)
        hostingView.viewModel = viewModel
        hostingView.frame = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)

        let window = NotchWindow(
            contentRect: NSRect(x: originX, y: originY, width: windowWidth, height: windowHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.orderFrontRegardless()

        self.notchWindow = window

        window.viewModel = viewModel
        viewModel.notchWindow = window
        viewModel.dragDetector = dragDetector

        window.startHoverMonitoring()
    }

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "NotchBoard")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Clear Clipboard", action: #selector(clearClipboard), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Storage Folder", action: #selector(openStorageFolder), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit NotchBoard", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func clearClipboard() {
        viewModel.clipboardManager.clearAll()
    }

    @objc private func openStorageFolder() {
        let url = viewModel.clipboardManager.storageDirectory
        NSWorkspace.shared.open(url)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
