#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
audit_dir="$(mktemp -d /tmp/mouse-hotkey-validation.XXXXXX)"
cat > "$audit_dir/Probe.swift" <<'SWIFT'
import CoreGraphics
import Foundation
struct Scheme { struct Scrolling {} }

@main
struct ScrollHotkeyValidation {
    static func main() throws {
        typealias Hotkeys = Scheme.Scrolling.ScrollHotkeys
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            guard value() else { fatalError(message) }
        }
        var physicallyDown = true
        let controller = ScrollHotkeyController(isPhysicallyPressed: { _ in physicallyDown })
        let binding = try JSONDecoder().decode(Hotkeys.Binding.self,
            from: Data(#"{"type":"keyboard","code":98}"#.utf8))
        check(binding.modifiers == 0 && binding.isEnabled, "Optional binding defaults failed")
        let input = ScrollHotkeyController.Input(binding)
        let first = ScrollHotkeyController.Scope(deviceID: 1, applicationPID: 20)
        var config = Hotkeys()
        config.acceleration = binding
        controller.observe(input: input, isDown: true, scope: first)
        controller.observe(input: input, isDown: true, isRepeat: true, scope: first)
        check(controller.pressed.count == 1, "Repeat generated multiple press states")
        controller.discard(input)
        check(controller.pressed.isEmpty, "Explicit keyboard action did not clear the same scroll hotkey")
        controller.observe(input: input, isDown: true, scope: first)
        check(controller.activeRoles(hotkeys: config, modifierFlags: [], scope: first) == [.acceleration],
              "Held key did not activate")
        physicallyDown = false
        check(controller.activeRoles(hotkeys: config, modifierFlags: [], scope: first).isEmpty,
              "Missed physical release was not recovered")
        physicallyDown = true
        controller.observe(input: input, isDown: true, scope: first)
        let otherApp = ScrollHotkeyController.Scope(deviceID: 1, applicationPID: 21)
        check(controller.activeRoles(hotkeys: config, modifierFlags: [], scope: otherApp).isEmpty,
              "App change retained a held hotkey")
        controller.observe(input: input, isDown: true, isRepeat: true, scope: otherApp)
        check(controller.pressed.isEmpty, "Auto-repeat reactivated a key after scope change")
        controller.observe(input: input, isDown: true, scope: otherApp)
        let otherMouse = ScrollHotkeyController.Scope(deviceID: 2, applicationPID: 21)
        check(controller.activeRoles(hotkeys: config, modifierFlags: [], scope: otherMouse).isEmpty,
              "Mouse change retained a held hotkey")
        let mouse = Hotkeys.Binding(type: .mouse, code: 3, modifiers: CGEventFlags.maskShift.rawValue)
        config.alterOrientation = mouse
        controller.observe(input: .init(mouse), isDown: true, scope: otherMouse)
        check(controller.activeRoles(hotkeys: config, modifierFlags: [], scope: otherMouse).isEmpty,
              "Required modifiers were ignored")
        check(controller.activeRoles(hotkeys: config, modifierFlags: .maskShift, scope: otherMouse) == [.alterOrientation],
              "Mouse button with modifier did not activate")
        var override = Hotkeys()
        override.alterOrientation = .disabled
        override.acceleration = .disabled
        override.merge(into: &config)
        check(!config.hasEnabledBinding, "Explicit disable did not override inheritance")
        controller.reset()
        check(controller.pressed.isEmpty, "Stop/reset retained held state")
        print("PASS: optional defaults, key/repeat/release, missed-release recovery, app/device scope reset, mouse/modifiers, inheritance, stop reset")
        print("0 events posted; no system mouse properties changed")
    }
}
SWIFT

swiftc -parse-as-library -module-cache-path "$audit_dir/ModuleCache" \
    "$project_dir/LinearMouse/Utilities/Codable/ImplicitOptional.swift" \
    "$project_dir/LinearMouse/Model/Configuration/Scheme/Scrolling/ScrollHotkeys.swift" \
    "$project_dir/LinearMouse/EventTransformer/ScrollHotkeyController.swift" \
    "$audit_dir/Probe.swift" -o "$audit_dir/validate"
"$audit_dir/validate"
