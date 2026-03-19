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
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    @ViewBuilder
    private var notchBody: some View {
        ZStack {
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
            let totalCount = viewModel.clipboardManager.items.count + viewModel.screenshotWatcher.screenshots.count + viewModel.screenRecorder.recordings.count
            if totalCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                    Text("\(totalCount)")
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

            // Tab bar
            tabBar
                .padding(.horizontal, 16)
                .padding(.top, 4)

            // Tab content
            switch viewModel.selectedTab {
            case .files:
                filesTabContent
            case .screenshots:
                screenshotsTabContent
            case .recording:
                recordingTabContent
            case .settings:
                SettingsView()
            }
        }
    }

    // MARK: - Tab Bar

    @ViewBuilder
    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(NotchTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.selectedTab = tab
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 9, weight: .medium))
                        Text(tab.rawValue)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(viewModel.selectedTab == tab ? .white.opacity(0.9) : .white.opacity(0.35))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(viewModel.selectedTab == tab ? .white.opacity(0.12) : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.white.opacity(0.04), in: Capsule())
    }

    // MARK: - Files Tab

    @ViewBuilder
    private var filesTabContent: some View {
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

    // MARK: - Screenshots Tab

    @ViewBuilder
    private var screenshotsTabContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                )
                .foregroundStyle(.white.opacity(0.12))

            if viewModel.screenshotWatcher.screenshots.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 26, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.3))

                    Text("Screenshots will appear here")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.25))
                }
            } else {
                VStack(spacing: 6) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(viewModel.screenshotWatcher.screenshots) { item in
                                ClipboardItemView(
                                    item: item,
                                    onCopy: { viewModel.screenshotWatcher.copyToClipboard(item) },
                                    onRemove: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            viewModel.screenshotWatcher.removeScreenshot(item)
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
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.screenshotWatcher.screenshots.count)
                    }

                    HStack {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                viewModel.screenshotWatcher.clearAll()
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

                        Text("\(viewModel.screenshotWatcher.screenshots.count) screenshots")
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

    // MARK: - Recording Tab

    @ViewBuilder
    private var recordingTabContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                )
                .foregroundStyle(.white.opacity(0.12))

            if viewModel.screenRecorder.isRecording {
                // Recording in progress
                VStack(spacing: 8) {
                    HStack(spacing: 16) {
                        // Pulsing red dot
                        Circle()
                            .fill(.red)
                            .frame(width: 10, height: 10)
                            .shadow(color: .red.opacity(0.6), radius: 4)
                            .modifier(PulsingModifier())

                        // Elapsed time
                        Text(formatDuration(viewModel.screenRecorder.recordingDuration))
                            .font(.system(size: 18, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))

                        // Stop button
                        Button(action: {
                            viewModel.screenRecorder.stopRecording()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(.white.opacity(0.12))
                                    .frame(width: 40, height: 40)
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(.red)
                                    .frame(width: 16, height: 16)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Stop recording")
                    }

                    Text("Recording screen...")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                }
            } else if viewModel.screenRecorder.recordings.isEmpty {
                // No recordings yet
                VStack(spacing: 10) {
                    Button(action: {
                        viewModel.screenRecorder.startRecording()
                    }) {
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.08))
                                .frame(width: 52, height: 52)
                            Circle()
                                .fill(.red)
                                .frame(width: 28, height: 28)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Start screen recording")

                    Text("Start screen recording")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.25))
                }
            } else {
                // Has recordings
                VStack(spacing: 6) {
                    HStack {
                        // Record button (small)
                        Button(action: {
                            viewModel.screenRecorder.startRecording()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(.white.opacity(0.08))
                                    .frame(width: 32, height: 32)
                                Circle()
                                    .fill(.red)
                                    .frame(width: 16, height: 16)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Start screen recording")
                        .padding(.leading, 10)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(viewModel.screenRecorder.recordings) { item in
                                    ClipboardItemView(
                                        item: item,
                                        onCopy: { viewModel.screenRecorder.copyToClipboard(item) },
                                        onRemove: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                viewModel.screenRecorder.removeRecording(item)
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
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.screenRecorder.recordings.count)
                        }
                    }

                    HStack {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                viewModel.screenRecorder.clearAll()
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

                        Text("\(viewModel.screenRecorder.recordings.count) recordings")
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

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Pulsing Animation Modifier

struct PulsingModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
