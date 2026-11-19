// MIT License

import CoreGraphics
import Foundation

/// Ephemeral physical input state. The application event thread is its owner.
/// No keys are logged or persisted; only currently-held key/button codes exist.
final class ScrollHotkeyController {
    typealias Hotkeys = Scheme.Scrolling.ScrollHotkeys
    typealias Binding = Hotkeys.Binding
    static let shared = ScrollHotkeyController()

    struct Input: Hashable {
        let type: Binding.InputType
        let code: UInt16
        init(_ binding: Binding) { type = binding.type; code = binding.code }
        init(type: Binding.InputType, code: UInt16) { self.type = type; self.code = code }
    }

    struct Scope: Equatable {
        var deviceID: Int32?
        var applicationPID: pid_t?
    }

    private(set) var pressed = Set<Input>()
    private var scope: Scope?
    private let isPhysicallyPressed: (Input) -> Bool

    init(isPhysicallyPressed: @escaping (Input) -> Bool = { input in
        switch input.type {
        case .keyboard:
            CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(input.code))
        case .mouse:
            input.code < 32
                && CGEventSource.buttonState(.combinedSessionState, button: CGMouseButton(rawValue: UInt32(input.code))!)
        }
    }) {
        self.isPhysicallyPressed = isPhysicallyPressed
    }

    func reset() { pressed.removeAll(); scope = nil }

    /// An explicit action has captured this input before the hotkey observer.
    func discard(_ input: Input) { pressed.remove(input) }

    func observe(input: Input?, isDown: Bool, isRepeat: Bool = false, scope nextScope: Scope) {
        updateScope(nextScope)
        guard let input else { return }
        if isDown {
            // An auto-repeat arriving after an app/device switch is not a new
            // deliberate press in the new scope.
            if !isRepeat || pressed.contains(input) { pressed.insert(input) }
        } else {
            pressed.remove(input)
        }
    }

    func activeRoles(
        hotkeys: Hotkeys,
        modifierFlags: CGEventFlags,
        scope nextScope: Scope
    ) -> Set<Hotkeys.Role> {
        updateScope(nextScope)
        // Recover missed releases after a transient tap timeout.
        pressed = pressed.filter(isPhysicallyPressed)
        return Set(Hotkeys.Role.allCases.filter { role in
            guard let binding = hotkeys[role], binding.isEnabled,
                  binding.matches(modifierFlags: modifierFlags) else { return false }
            return pressed.contains(Input(binding))
        })
    }

    private func updateScope(_ next: Scope) {
        if let scope {
            let changedApp = scope.applicationPID != next.applicationPID
            let changedDevice = scope.deviceID != nil && next.deviceID != nil && scope.deviceID != next.deviceID
            if changedApp || changedDevice { pressed.removeAll() }
        }
        scope = Scope(deviceID: next.deviceID ?? scope?.deviceID, applicationPID: next.applicationPID)
    }
}
