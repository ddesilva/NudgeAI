import AppKit
import Carbon.HIToolbox

/// Registers a single global hotkey via the Carbon Event Manager and invokes
/// `handler` whenever the user presses it, regardless of which app is in front.
@MainActor
final class GlobalHotkeyMonitor {
    typealias Handler = () -> Void

    private var hotkeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let handler: Handler

    /// Four-char signature ('Ndge') used to identify our hotkey registration.
    private static let signature: OSType = {
        let bytes: [UInt8] = [0x4E, 0x64, 0x67, 0x65] // 'N','d','g','e'
        return bytes.reduce(0) { ($0 << 8) | OSType($1) }
    }()
    private static let id: UInt32 = 1

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    deinit {
        if let ref = hotkeyRef { UnregisterEventHotKey(ref) }
        if let ref = handlerRef { RemoveEventHandler(ref) }
    }

    /// Re-read the hotkey from `Preferences` and update the registration.
    func reload() {
        unregister()
        guard let hk = Preferences.hotkey else { return }
        register(hk)
    }

    private func register(_ hk: Hotkey) {
        installHandlerIfNeeded()
        let hotkeyID = EventHotKeyID(signature: Self.signature, id: Self.id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hk.keyCode,
            carbonModifiers(from: hk.modifiers),
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotkeyRef = ref
        }
    }

    private func unregister() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        var ref: EventHandlerRef?
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let monitor = Unmanaged<GlobalHotkeyMonitor>
                    .fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { monitor.handler() }
                return noErr
            },
            1,
            &spec,
            context,
            &ref
        )
        handlerRef = ref
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }
}
