#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
audit_dir="$(mktemp -d /tmp/mouse-keyboard-bindings.XXXXXX)"
sdk_dir="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
[[ -d "$sdk_dir" ]] || sdk_dir="$(xcrun --show-sdk-path)"
module_dir="$project_dir/build/local/modules"
[[ -f "$module_dir/libKeyKit.dylib" ]] || { print -u2 '先运行 python3 Scripts/LocalBuild.py 构建本地依赖'; exit 1; }

cat > "$audit_dir/Support.swift" <<'SWIFT'
import AppKit
import Foundation
import KeyKit

// Actuation interfaces are inert in this executable. The production mapping
// and controller files are compiled unchanged, with action effects or an
// inert executor factory injected. No test posts real input.
struct Scheme {
    struct Buttons {
        struct Mapping {
            enum Action: Equatable, Codable {
                case arg0(Arg0)
                case arg1(Arg1)
                enum Arg0: String, Codable { case auto, none, missionControl }
                enum Arg1: Equatable, Codable { case keyPress([Key]) }
            }
            enum Button: Hashable { case mouse(Int) }
            struct PressAction {
                let action: Action
                let behavior: Behavior
                enum Behavior { case hold }
            }
        }
    }
}
struct EventTransformerContext {}
protocol EventTransformer {
    var handlesPointerMotion: Bool { get }
    func transform(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent?
}
protocol Deactivatable { func deactivate() }
final class SettingsState {
    static let shared = SettingsState()
    var recording = false
}
final class ScrollHotkeyController {
    enum InputType { case keyboard }
    struct Input { var type: InputType; var code: UInt16 }
    static let shared = ScrollHotkeyController()
    func discard(_ input: Input) {}
}
extension CGEvent {
    static let linearMouseSyntheticEventUserData: Int64 = 0x534D_4F4F_5448
    var isLinearMouseSyntheticEvent: Bool {
        get { getIntegerValueField(.eventSourceUserData) == Self.linearMouseSyntheticEventUserData }
        set { setIntegerValueField(.eventSourceUserData, value: newValue ? Self.linearMouseSyntheticEventUserData : 0) }
    }
}
final class ButtonActionExecutor {
    private(set) var calls = [String]()
    init() {}
    init(keySimulator: KeySimulating) { fatalError("Live executor must not be initialized in pure tests") }
    func perform(_ action: Scheme.Buttons.Mapping.Action, targetBundleIdentifier: String?) { calls.append("perform") }
    func beginPress(_ press: Scheme.Buttons.Mapping.PressAction, buttons: Set<Scheme.Buttons.Mapping.Button>, targetBundleIdentifier: String?) { calls.append("beginHold") }
    func endPress(_ press: Scheme.Buttons.Mapping.PressAction, buttons: Set<Scheme.Buttons.Mapping.Button>) { calls.append("endHold") }
    func deactivate() { calls.append("reset") }
}
SWIFT

cat > "$audit_dir/main.swift" <<'SWIFT'
import AppKit
import Foundation
import KeyKit

typealias Mapping = Scheme.Buttons.KeyboardMapping
let firstOwner = UUID()
let secondOwner = UUID()
var effects = [String]()
let controller = KeyboardActionBindingsController(effects: .init(
    perform: { _, target in effects.append("perform:\(target ?? "nil")") },
    beginHold: { _, code in effects.append("down:\(code)") },
    endHold: { _, code in effects.append("up:\(code)") },
    reset: { effects.append("reset") }
))
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    precondition(value(), message)
    checks += 1
}
func input(_ type: CGEventType, _ code: UInt16, flags: UInt64 = 0, repeatKey: Bool = false,
           owner: UUID = firstOwner, mappings: [Mapping]) -> Bool {
    controller.handle(type: type, keyCode: code, modifiers: flags, isRepeat: repeatKey,
                      owner: owner, mappings: mappings, targetBundleIdentifier: "test.app")
}
let command = CGEventFlags.maskCommand.rawValue
let shift = CGEventFlags.maskShift.rawValue
let one = Mapping(keyCode: 100, modifiers: command, action: .arg0(.missionControl))
check(!input(.keyDown, 100, flags: command | shift, mappings: [one]), "Extra modifier matched")
check(input(.keyDown, 100, flags: command, mappings: [one]), "Exact shortcut did not match")
check(effects == ["perform:test.app"], "Press did not perform exactly once")
check(input(.keyDown, 100, flags: command, repeatKey: true, mappings: [one]), "Repeat leaked original input")
check(effects.count == 1, "One-shot action repeated")
check(input(.keyUp, 100, mappings: []), "Key-up pairing depended on current modifiers or mappings")
check(!input(.keyUp, 100, mappings: []), "Orphan key-up was consumed twice")

var repeated = one
repeated.behavior = .repeat
check(input(.keyDown, 100, flags: command, mappings: [repeated]), "Repeat trigger failed")
check(input(.keyDown, 100, flags: command, repeatKey: true, mappings: [repeated]), "Repeat event failed")
check(effects.count == 3, "Physical repeat did not repeat action once")
check(input(.keyUp, 100, mappings: []), "Repeat key-up leaked")
check(!input(.keyDown, 100, flags: command, repeatKey: true, mappings: [repeated]), "Mid-hold autorepeat started a new binding")

let held = Mapping(keyCode: 101, modifiers: command, behavior: .hold, action: .arg1(.keyPress([.command, .tab])))
check(input(.keyDown, 101, flags: command, mappings: [held]), "Hold trigger failed")
check(effects.last == "down:101", "Hold did not start")
check(!input(.flagsChanged, 55, mappings: []), "Modifier release should pass through")
check(effects.last == "up:101", "Lost modifier did not release held output")
check(input(.keyUp, 101, mappings: []), "Cancelled hold lost physical key-up pairing")
check(effects.filter { $0 == "up:101" }.count == 1, "Held output was released twice")

check(input(.keyDown, 101, flags: command, mappings: [held]), "Second hold failed")
check(!input(.scrollWheel, 0, owner: secondOwner, mappings: []), "Context transition consumed unrelated input")
check(effects.last == "up:101", "Context change retained held output")
check(input(.keyDown, 101, flags: command, repeatKey: true, owner: secondOwner, mappings: [held]), "Captured autorepeat leaked after context change")
check(effects.last == "up:101", "Context change reactivated held output")
check(input(.keyUp, 101, owner: secondOwner, mappings: []), "Context switch did not consume captured key-up")

var disabled = one
disabled.enabled = false
check(!input(.keyDown, 100, flags: command, mappings: [one, disabled]), "Disabled override fell back to inherited binding")
var merged: [Mapping]? = [one]
Mapping.merge([disabled], into: &merged)
check(merged?.count == 1 && merged?.first?.enabled == false, "Same trigger was not replaced on merge")
Mapping.merge([], into: &merged)
check(merged?.isEmpty == true, "Empty override did not clear inheritance")
check(!Mapping(keyCode: 55, action: .arg0(.none)).isValid, "Standalone modifier accepted as ordinary key")
check(!Mapping(keyCode: 1, behavior: .hold, action: .arg0(.missionControl)).isValid, "Non-key action accepted in hold mode")

let original = Mapping(keyCode: 100, modifiers: command, action: .arg0(.none))
var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
object.removeValue(forKey: "id")
object.removeValue(forKey: "enabled")
object.removeValue(forKey: "behavior")
let decoded = try JSONDecoder().decode(Mapping.self, from: JSONSerialization.data(withJSONObject: object))
check(decoded.enabled && decoded.behavior == .perform && decoded.keyCode == 100, "Optional mapping defaults failed")
let roundTripped = try JSONDecoder().decode(Mapping.self, from: JSONEncoder().encode(original))
check(roundTripped == original, "Mapping round trip failed")

let token1 = KeyboardActionRecordingState.shared.begin()
let token2 = KeyboardActionRecordingState.shared.begin()
KeyboardActionRecordingState.shared.end(token1)
check(KeyboardActionRecordingState.shared.isRecording, "Nested recording gate closed early")
KeyboardActionRecordingState.shared.end(token2)
check(!KeyboardActionRecordingState.shared.isRecording, "Recording gate remained active")

check(input(.keyDown, 101, flags: command, mappings: [held]), "Reset precondition failed")
controller.reset()
check(effects.suffix(2) == ["up:101", "reset"], "Reset did not release and clear effects")
check(!input(.keyUp, 101, mappings: []), "Reset retained a captured key-up")
let synthetic = CGEvent(source: nil)!
synthetic.type = .keyDown
synthetic.setIntegerValueField(.keyboardEventKeycode, value: 100)
synthetic.isLinearMouseSyntheticEvent = true
check(!controller.consume(synthetic, owner: firstOwner, mappings: [one], targetBundleIdentifier: "test.app"), "Synthetic output looped into binding")
KeyboardActionExecutorLifecycleTests.run { value, message in check(value, message) }
print("PASS: \(checks) keyboard action checks; exact modifiers, repeat, down/up, hold release, context reset, inheritance, defaults, recording gate, synthetic bypass, unused teardown and first execution while main waits")
print("0 input events posted; executor effects were injected and no system settings changed")
SWIFT

cp "$project_dir/LinearMouse/Model/Configuration/Scheme/Buttons/KeyboardMapping.swift" "$audit_dir/KeyboardMapping.swift"
cp "$project_dir/LinearMouse/EventTransformer/KeyboardActionBindingsTransformer.swift" "$audit_dir/KeyboardActionBindingsTransformer.swift"
swiftc -swift-version 5 -sdk "$sdk_dir" -module-cache-path "$audit_dir/ModuleCache" \
    -I "$module_dir" -I "$module_dir/KeyKitC" -L "$module_dir" -lKeyKit \
    -Xlinker -rpath -Xlinker "$module_dir" \
    "$audit_dir/Support.swift" "$audit_dir/KeyboardMapping.swift" \
    "$audit_dir/KeyboardActionBindingsTransformer.swift" \
    "$project_dir/LocalTests/KeyboardActionExecutorLifecycleTests.swift" "$audit_dir/main.swift" -o "$audit_dir/validate"
"$audit_dir/validate"
