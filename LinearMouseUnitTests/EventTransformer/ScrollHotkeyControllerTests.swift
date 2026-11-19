// MIT License

import CoreGraphics
@testable import LinearMouse
import XCTest

final class ScrollHotkeyControllerTests: XCTestCase {
    typealias Hotkeys = Scheme.Scrolling.ScrollHotkeys

    func testPressRepeatReleaseAndModifierMatching() {
        let controller = ScrollHotkeyController(isPhysicallyPressed: { _ in true })
        let binding = Hotkeys.Binding(type: .keyboard, code: 98, modifiers: CGEventFlags.maskShift.rawValue)
        let input = ScrollHotkeyController.Input(binding)
        let scope = ScrollHotkeyController.Scope(deviceID: 1, applicationPID: 20)
        var config = Hotkeys()
        config.acceleration = binding
        controller.observe(input: input, isDown: true, scope: scope)
        controller.observe(input: input, isDown: true, isRepeat: true, scope: scope)
        XCTAssertEqual(controller.pressed.count, 1)
        XCTAssertEqual(controller.activeRoles(hotkeys: config, modifierFlags: .maskShift, scope: scope), [.acceleration])
        XCTAssertTrue(controller.activeRoles(hotkeys: config, modifierFlags: [], scope: scope).isEmpty)
        controller.observe(input: input, isDown: false, scope: scope)
        XCTAssertTrue(controller.activeRoles(hotkeys: config, modifierFlags: .maskShift, scope: scope).isEmpty)
    }

    func testAppAndDeviceSwitchRequireNewPress() {
        let controller = ScrollHotkeyController(isPhysicallyPressed: { _ in true })
        let binding = Hotkeys.Binding(type: .keyboard, code: 98)
        let input = ScrollHotkeyController.Input(binding)
        let first = ScrollHotkeyController.Scope(deviceID: 1, applicationPID: 20)
        let otherApp = ScrollHotkeyController.Scope(deviceID: 1, applicationPID: 21)
        let otherMouse = ScrollHotkeyController.Scope(deviceID: 2, applicationPID: 21)
        var config = Hotkeys()
        config.bypassSmoothing = binding
        controller.observe(input: input, isDown: true, scope: first)
        XCTAssertTrue(controller.activeRoles(hotkeys: config, modifierFlags: [], scope: otherApp).isEmpty)
        controller.observe(input: input, isDown: true, isRepeat: true, scope: otherApp)
        XCTAssertTrue(controller.pressed.isEmpty)
        controller.observe(input: input, isDown: true, scope: otherApp)
        XCTAssertEqual(controller.activeRoles(hotkeys: config, modifierFlags: [], scope: otherApp), [.bypassSmoothing])
        XCTAssertTrue(controller.activeRoles(hotkeys: config, modifierFlags: [], scope: otherMouse).isEmpty)
    }

    func testRecoversMissedMouseReleaseAndReset() {
        var stillDown = true
        let controller = ScrollHotkeyController(isPhysicallyPressed: { _ in stillDown })
        let binding = Hotkeys.Binding(type: .mouse, code: 3)
        let scope = ScrollHotkeyController.Scope(deviceID: 1, applicationPID: 20)
        var config = Hotkeys()
        config.alterOrientation = binding
        controller.observe(input: .init(binding), isDown: true, scope: scope)
        XCTAssertEqual(controller.activeRoles(hotkeys: config, modifierFlags: [], scope: scope), [.alterOrientation])
        stillDown = false
        XCTAssertTrue(controller.activeRoles(hotkeys: config, modifierFlags: [], scope: scope).isEmpty)
        controller.reset()
        XCTAssertTrue(controller.pressed.isEmpty)
    }

    func testDecodingDefaultsAndExplicitDisableOverride() throws {
        let binding = try JSONDecoder().decode(Hotkeys.Binding.self, from: Data(#"{"type":"keyboard","code":98}"#.utf8))
        XCTAssertEqual(binding.modifiers, 0)
        XCTAssertTrue(binding.isEnabled)
        var global = Hotkeys()
        global.acceleration = binding
        var app = Hotkeys()
        app.acceleration = .disabled
        app.merge(into: &global)
        XCTAssertFalse(global.hasEnabledBinding)
    }
}
