import SwiftUI
import UniformTypeIdentifiers

struct ClipboardItemView: View {
    let item: ClipboardItem
    let onCopy: () -> Void
    let onRemove: () -> Void
    @ObservedObject var viewModel: NotchViewModel

    @State private var isHovering = false
    @State private var showPreview = false

    private var isImageFile: Bool {
        guard let url = item.url else { return false }
        let ext = url.pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "tif", "heic", "heif", "avif"].contains(ext)
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(isHovering ? 0.12 : 0.07))

                    if isImageFile, let url = item.url, let nsImage = NSImage(contentsOf: url) {
                        // Show actual image thumbnail for image files
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else if let icon = item.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 30, height: 30)
                    } else {
                        Image(systemName: iconName)
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Remove button
                if isHovering {
                    Button(action: onRemove) {
                        ZStack {
                            Circle()
                                .fill(.black)
                                .frame(width: 18, height: 18)
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .buttonStyle(.plain)
                    .offset(x: 5, y: -5)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .popover(isPresented: $showPreview, arrowEdge: .bottom) {
                if isImageFile, let url = item.url, let nsImage = NSImage(contentsOf: url) {
                    VStack(spacing: 8) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 400, maxHeight: 400)

                        Text(item.name)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(12)
                } else {
                    VStack(spacing: 8) {
                        if let icon = item.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 80, height: 80)
                        }
                        Text(item.name)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .truncationMode(.middle)
                    }
                    .padding(12)
                }
            }

            Text(item.name)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 64)
        }
        .allowsHitTesting(true)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            onCopy()
        }
        .contextMenu {
            Button("Preview") {
                showPreview = true
            }
            Button("Copy") {
                onCopy()
            }
            Divider()
            Button("Remove", role: .destructive) {
                onRemove()
            }
        }
        .onDrag {
            viewModel.isDraggingFromNotch = true
            // Monitor when the drag ends by observing the pasteboard
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.monitorDragEnd()
            }
            if let url = item.url {
                if let provider = NSItemProvider(contentsOf: url) {
                    provider.suggestedName = url.lastPathComponent
                    return provider
                }
                return NSItemProvider(object: url as NSURL)
            } else if let text = item.text {
                return NSItemProvider(object: text as NSString)
            }
            return NSItemProvider()
        }
        .help("Click to copy. Drag to use elsewhere.")
    }

    private func monitorDragEnd() {
        // Poll for mouse button release to detect drag end
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            let buttons = NSEvent.pressedMouseButtons
            if buttons & 1 == 0 {
                // Left mouse button released — drag ended
                timer.invalidate()
                DispatchQueue.main.async {
                    self.viewModel.isDraggingFromNotch = false
                    self.viewModel.collapse()
                }
            }
        }
    }

    private var iconName: String {
        switch item.type {
        case .file: return "doc.fill"
        case .url: return "link"
        case .text: return "doc.text"
        }
    }
}
