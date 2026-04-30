import SwiftUI
import AppKit
import Combine
import ApplicationServices

@main
struct NotchBarApp: App {
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
    private let hotkeyManager = GlobalHotkeyManager()
    private var cancellables = Set<AnyCancellable>()
    private var didShowHotkeyPermissionAlert = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewModel = NotchViewModel()
        dragDetector = DragDetector()

        setupDragDetector()
        setupNotchWindow()
        setupStatusBarItem()
        setupCommandRHotkey()
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
            button.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "NotchBar")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Clear Clipboard", action: #selector(clearClipboard), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Storage Folder", action: #selector(openStorageFolder), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit NotchBar", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func setupCommandRHotkey() {
        hotkeyManager.onHotkey = { [weak self] in
            guard let self else { return }
            guard SettingsManager.shared.toggleNotchbarOnCommandR else { return }
            self.viewModel.toggleHidden()
        }

        // React to setting changes (enable/disable and hotkey choice).
        Publishers.CombineLatest(
            SettingsManager.shared.$toggleNotchbarOnCommandR,
            SettingsManager.shared.$notchbarHotkey
        )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled, choice in
                guard let self else { return }
                if enabled {
                    self.configureHotkey(choice)
                    self.startHotkeyIfPossible()
                } else {
                    self.hotkeyManager.stop()
                }
            }
            .store(in: &cancellables)

        // Ensure it's started on launch if enabled.
        if SettingsManager.shared.toggleNotchbarOnCommandR {
            configureHotkey(SettingsManager.shared.notchbarHotkey)
            startHotkeyIfPossible()
        }
    }

    private func configureHotkey(_ choice: SettingsManager.NotchbarHotkey) {
        switch choice {
        case .commandR:
            hotkeyManager.hotkey = .init(
                keyCode: 15, // R
                requiredFlags: [.maskCommand],
                forbiddenFlags: [.maskShift, .maskAlternate, .maskControl]
            )
        case .controlOptionCommandR:
            hotkeyManager.hotkey = .init(
                keyCode: 15, // R
                requiredFlags: [.maskControl, .maskAlternate, .maskCommand],
                forbiddenFlags: [.maskShift]
            )
        }
    }

    private func startHotkeyIfPossible() {
        // Prompt user to grant Accessibility if needed (helps for event taps on many systems).
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        do {
            try hotkeyManager.start()
        } catch {
            hotkeyManager.stop()
            showHotkeyPermissionAlertOnce()
        }
    }

    private func showHotkeyPermissionAlertOnce() {
        guard !didShowHotkeyPermissionAlert else { return }
        didShowHotkeyPermissionAlert = true

        let alert = NSAlert()
        alert.messageText = "Allow NotchBar to detect the hotkey"
        alert.informativeText = "Enable NotchBar in System Settings → Privacy & Security → Input Monitoring (and Accessibility if prompted), then quit + reopen NotchBar."
        alert.addButton(withTitle: "OK")
        alert.runModal()
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

    deinit {
        hotkeyManager.stop()
    }
}
