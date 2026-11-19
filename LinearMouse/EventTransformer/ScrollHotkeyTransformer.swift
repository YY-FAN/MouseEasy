// MIT License

import CoreGraphics
import Foundation

/// Observe after explicit keyboard action mappings but before mouse mappings.
/// Configured hotkeys leave their original key/button stream untouched.
final class ScrollHotkeyInputObserver: EventTransformer {
    var handlesPointerMotion: Bool { false }
    private let applicationPID: pid_t?
    private let controller: ScrollHotkeyController

    init(applicationPID: pid_t?, controller: ScrollHotkeyController = .shared) {
        self.applicationPID = applicationPID
        self.controller = controller
    }

    func transform(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent? {
        if SettingsState.shared.recording || KeyboardActionRecordingState.shared.isRecording {
            controller.reset()
            return event
        }
        guard !event.isLinearMouseSyntheticEvent else { return event }
        let input: ScrollHotkeyController.Input?
        let isDown: Bool
        switch event.type {
        case .keyDown, .keyUp:
            input = .init(type: .keyboard, code: UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode)))
            isDown = event.type == .keyDown
        case .leftMouseDown, .rightMouseDown, .otherMouseDown,
             .leftMouseUp, .rightMouseUp, .otherMouseUp:
            input = .init(type: .mouse, code: UInt16(clamping: event.getIntegerValueField(.mouseEventButtonNumber)))
            isDown = [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type)
        default:
            input = nil
            isDown = false
        }
        controller.observe(
            input: input,
            isDown: isDown,
            isRepeat: event.type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            scope: .init(deviceID: context.device?.id, applicationPID: applicationPID)
        )
        return event
    }
}

/// Applies to the already-reversed wheel, after normal modifier actions.
/// A Ctrl+wheel pinch action consumes the event before reaching this stage.
final class ScrollHotkeyTransformer: EventTransformer {
    var handlesPointerMotion: Bool { false }
    private let hotkeys: Scheme.Scrolling.ScrollHotkeys
    private let applicationPID: pid_t?
    private let controller: ScrollHotkeyController

    init(
        hotkeys: Scheme.Scrolling.ScrollHotkeys,
        applicationPID: pid_t?,
        controller: ScrollHotkeyController = .shared
    ) {
        self.hotkeys = hotkeys
        self.applicationPID = applicationPID
        self.controller = controller
    }

    func transform(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent? {
        guard event.type == .scrollWheel, !event.isLinearMouseSyntheticEvent,
              context.device?.category == .mouse, !SettingsState.shared.recording,
              !KeyboardActionRecordingState.shared.isRecording else { return event }
        let roles = controller.activeRoles(
            hotkeys: hotkeys,
            modifierFlags: ModifierState.shared.currentFlags,
            scope: .init(deviceID: context.device?.id, applicationPID: applicationPID)
        )
        let view = ScrollWheelEventView(event)
        if roles.contains(.acceleration) { view.scale(factor: hotkeys.resolvedAccelerationScale) }
        if roles.contains(.alterOrientation) { view.swapXY() }
        if roles.contains(.bypassSmoothing) { event.bypassesSmoothedScrolling = true }
        return event
    }
}
