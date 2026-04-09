import SwiftUI
import Combine
import UniformTypeIdentifiers

enum NotchTab: String, CaseIterable {
    case files = "Files"
    case screenshots = "Screenshots"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .files: return "doc.on.doc"
        case .screenshots: return "camera.viewfinder"
        case .settings: return "gearshape"
        }
    }
}

class NotchViewModel: ObservableObject {
    @Published var isExpanded = false
    @Published var isDraggingOverNotch = false
    @Published var isHovering = false
    @Published var dropTargeting = false
    @Published var isDraggingFromNotch = false
    @Published var selectedTab: NotchTab = .files

    let clipboardManager = ClipboardManager()
    let screenshotWatcher = ScreenshotWatcher()

    weak var notchWindow: NotchWindow?
    weak var dragDetector: DragDetector?

    private var collapseWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    let closedSize: CGSize
    let openSize = CGSize(width: 700, height: 250)

    init() {
        if let screen = NSScreen.main {
            let safeArea = screen.safeAreaInsets
            if safeArea.top > 0 {
                let topLeft = screen.auxiliaryTopLeftArea?.width ?? 0
                let topRight = screen.auxiliaryTopRightArea?.width ?? 0
                let notchWidth = screen.frame.width - topLeft - topRight
                closedSize = CGSize(width: max(notchWidth, 185), height: safeArea.top)
            } else {
                closedSize = CGSize(width: 185, height: 32)
            }
        } else {
            closedSize = CGSize(width: 185, height: 32)
        }

        clipboardManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        screenshotWatcher.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var currentWidth: CGFloat {
        isExpanded ? openSize.width : closedSize.width
    }

    var currentHeight: CGFloat {
        isExpanded ? openSize.height : closedSize.height
    }

    func expand() {
        collapseWorkItem?.cancel()
        guard !isExpanded else { return }
        selectedTab = .files
        withAnimation(.spring(response: 0.4, dampingFraction: 0.78, blendDuration: 0.1)) {
            isExpanded = true
        }
        notchWindow?.ignoresMouseEvents = false
    }

    func collapse() {
        collapseWorkItem?.cancel()
        guard !isHovering, !dropTargeting, !isDraggingOverNotch, !isDraggingFromNotch else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82, blendDuration: 0.05)) {
            isExpanded = false
        }
        notchWindow?.ignoresMouseEvents = true
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { [weak self] data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async {
                        self?.clipboardManager.addFile(url)
                    }
                }
                handled = true
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async {
                        self?.clipboardManager.addURL(url)
                    }
                }
                handled = true
            } else if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.text.identifier) { [weak self] data, _ in
                    guard let text = data as? String else { return }
                    DispatchQueue.main.async {
                        self?.clipboardManager.addText(text)
                    }
                }
                handled = true
            }
        }

        return handled
    }
}
