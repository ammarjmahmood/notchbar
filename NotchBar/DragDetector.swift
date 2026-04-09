import AppKit

class DragDetector {
    var onDragBegan: (() -> Void)?
    var onDragEnded: (() -> Void)?
    var onDragEnteredNotch: (() -> Void)?

    private var monitors: [Any] = []
    private var isDragging = false
    private var hasEnteredNotch = false
    private var dragStartLocation: NSPoint?
    private let dragThreshold: CGFloat = 4

    func startMonitoring() {
        let downMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.dragStartLocation = NSEvent.mouseLocation
            self?.isDragging = false
            self?.hasEnteredNotch = false
        }
        if let downMonitor { monitors.append(downMonitor) }

        let dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            guard let self else { return }
            let location = NSEvent.mouseLocation

            if !self.isDragging {
                // Start drag after moving past threshold (avoids false triggers from clicks)
                if let start = self.dragStartLocation {
                    let dist = hypot(location.x - start.x, location.y - start.y)
                    if dist > self.dragThreshold {
                        self.isDragging = true
                        self.onDragBegan?()
                    }
                }
            }

            if self.isDragging && self.isInNotchRegion(location) && !self.hasEnteredNotch {
                self.hasEnteredNotch = true
                self.onDragEnteredNotch?()
            }
        }
        if let dragMonitor { monitors.append(dragMonitor) }

        let upMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self else { return }
            self.dragStartLocation = nil
            if self.isDragging {
                self.isDragging = false
                self.hasEnteredNotch = false
                self.onDragEnded?()
            }
        }
        if let upMonitor { monitors.append(upMonitor) }
    }

    func stopMonitoring() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    private func isInNotchRegion(_ point: NSPoint) -> Bool {
        guard let screen = NSScreen.main else { return false }
        let screenFrame = screen.frame

        let notchWidth: CGFloat = 350
        let notchHeight: CGFloat = 50

        let notchMinX = screenFrame.midX - notchWidth / 2
        let notchMaxX = screenFrame.midX + notchWidth / 2
        let notchMinY = screenFrame.maxY - notchHeight

        return point.x >= notchMinX && point.x <= notchMaxX && point.y >= notchMinY
    }

    deinit {
        stopMonitoring()
    }
}
