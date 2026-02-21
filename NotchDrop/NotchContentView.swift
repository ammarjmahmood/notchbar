import SwiftUI
import UniformTypeIdentifiers

struct NotchContentView: View {
    @ObservedObject var viewModel: NotchViewModel

    @State private var dropTargeted = false

    var body: some View {
        GeometryReader { geo in
            let width = viewModel.currentWidth
            let height = viewModel.currentHeight

            ZStack(alignment: .top) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    notchBody
                        .frame(width: width, height: height)
                        .clipShape(NotchShape(
                            topCornerRadius: 0,
                            bottomCornerRadius: viewModel.isExpanded ? 22 : 10
                        ))
                        .shadow(
                            color: viewModel.isExpanded ? .black.opacity(0.45) : .clear,
                            radius: viewModel.isExpanded ? 30 : 0,
                            y: viewModel.isExpanded ? 8 : 0
                        )
                        .contentShape(NotchShape(
                            topCornerRadius: 0,
                            bottomCornerRadius: viewModel.isExpanded ? 22 : 10
                        ))
                        // Hover is handled by NotchWindow's global mouse monitor
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    @ViewBuilder
    private var notchBody: some View {
        ZStack {
            // Subtle gradient background instead of flat black
            LinearGradient(
                colors: [Color(white: 0.06), Color.black],
                startPoint: .bottom,
                endPoint: .top
            )

            if viewModel.isExpanded {
                expandedContent
                    .transition(
                        .asymmetric(
                            insertion: .opacity
                                .combined(with: .scale(scale: 0.92, anchor: .top))
                                .animation(.spring(response: 0.45, dampingFraction: 0.8)),
                            removal: .opacity
                                .combined(with: .scale(scale: 0.95, anchor: .top))
                                .animation(.easeIn(duration: 0.15))
                        )
                    )
            } else {
                closedContent
                    .transition(.opacity.animation(.easeInOut(duration: 0.12)))
            }
        }
    }

    @ViewBuilder
    private var closedContent: some View {
        HStack(spacing: 5) {
            if !viewModel.clipboardManager.items.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                    Text("\(viewModel.clipboardManager.items.count)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: viewModel.closedSize.height)

            // Single tray
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                    )
                    .foregroundStyle(.white.opacity(viewModel.dropTargeting ? 0.4 : 0.12))
                    .animation(.easeInOut(duration: 0.2), value: viewModel.dropTargeting)

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(viewModel.dropTargeting ? 0.05 : 0))
                    .animation(.easeInOut(duration: 0.2), value: viewModel.dropTargeting)

                if viewModel.clipboardManager.items.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 26, weight: .ultraLight))
                            .foregroundStyle(.white.opacity(viewModel.dropTargeting ? 0.7 : 0.3))

                        Text("Drop files here")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(viewModel.dropTargeting ? 0.6 : 0.25))
                    }
                    .animation(.easeInOut(duration: 0.2), value: viewModel.dropTargeting)
                } else {
                    VStack(spacing: 6) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(viewModel.clipboardManager.items) { item in
                                    ClipboardItemView(
                                        item: item,
                                        onCopy: { viewModel.clipboardManager.copyToClipboard(item) },
                                        onRemove: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                viewModel.clipboardManager.removeItem(item)
                                            }
                                        }
                                    )
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.5).combined(with: .opacity),
                                        removal: .scale(scale: 0.8).combined(with: .opacity)
                                    ))
                                }
                            }
                            .padding(.horizontal, 10)
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.clipboardManager.items.count)
                        }

                        HStack {
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    viewModel.clipboardManager.clearAll()
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 9, weight: .medium))
                                    Text("Clear")
                                        .font(.system(size: 9, weight: .medium, design: .rounded))
                                }
                                .foregroundStyle(.white.opacity(0.35))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.white.opacity(0.06), in: Capsule())
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Text("\(viewModel.clipboardManager.items.count) items")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.2))
                        }
                        .padding(.horizontal, 12)
                    }
                    .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
    }
}
