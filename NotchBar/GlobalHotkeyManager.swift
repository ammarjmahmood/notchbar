import AppKit

final class GlobalHotkeyManager {
    enum HotkeyError: Error {
        case eventTapCreationFailed
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    struct Hotkey: Equatable {
        let keyCode: Int64
        let requiredFlags: CGEventFlags
        let forbiddenFlags: CGEventFlags
    }

    /// Called on the main thread when the hotkey is pressed.
    var onHotkey: (() -> Void)?

    var hotkey: Hotkey = .init(
        keyCode: 15, // R
        requiredFlags: [.maskControl, .maskAlternate, .maskCommand],
        forbiddenFlags: [.maskShift]
    )

    func start() throws {
        guard eventTap == nil else { return }

        let mask = CGEventMask((1 << CGEventType.keyDown.rawValue)
                               | (1 << CGEventType.tapDisabledByTimeout.rawValue)
                               | (1 << CGEventType.tapDisabledByUserInput.rawValue))

        // Use an event tap so it works regardless of which app is active.
        // This typically requires Input Monitoring permission (and sometimes Accessibility).
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, cgEvent, refcon in
                guard let refcon else { return Unmanaged.passUnretained(cgEvent) }

                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                manager.handleEvent(type: type, event: cgEvent)
                return Unmanaged.passUnretained(cgEvent)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        guard let tap else {
            throw HotkeyError.eventTapCreationFailed
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func stop() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        runLoopSource = nil
        eventTap = nil
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }

        guard type == .keyDown else { return }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == hotkey.keyCode else { return }

        let flags = event.flags
        guard flags.contains(hotkey.requiredFlags) else { return }
        guard flags.intersection(hotkey.forbiddenFlags).isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            self?.onHotkey?()
        }
    }
}

