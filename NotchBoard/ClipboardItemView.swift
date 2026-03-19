import SwiftUI
import UniformTypeIdentifiers

struct ClipboardItemView: View {
    let item: ClipboardItem
    let onCopy: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(isHovering ? 0.12 : 0.07))

                    if let icon = item.icon {
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
        .onDrag {
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

    private var iconName: String {
        switch item.type {
        case .file: return "doc.fill"
        case .url: return "link"
        case .text: return "doc.text"
        }
    }
}
