import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @ObservedObject var viewModel: NotchViewModel

    @State private var isTargeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: [8, 5])
                )
                .foregroundColor(isTargeted ? .white.opacity(0.5) : .white.opacity(0.15))

            RoundedRectangle(cornerRadius: 14)
                .fill(isTargeted ? Color.white.opacity(0.06) : Color.clear)

            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(.white.opacity(isTargeted ? 0.8 : 0.35))

                Text("Drop files here")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(isTargeted ? 0.7 : 0.35))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL, .url, .text], isTargeted: $isTargeted) { providers in
            viewModel.dropTargeting = false
            return viewModel.handleDrop(providers: providers)
        }
        .onChange(of: isTargeted) { _, targeted in
            viewModel.dropTargeting = targeted
        }
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }
}
