// MIT License
// Explicit keyboard action bindings share the normal button-action executor.

import AppKit
import Foundation
import KeyKit

/// Recording only takes place in a focused editor. The event thread reads this
/// gate so configured actions do not fire while a shortcut is being recorded.
final class KeyboardActionRecordingState {
    static let shared = KeyboardActionRecordingState()
    private let lock = NSLock()
    private var sessions = Set<UUID>()

    var isRecording: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !sessions.isEmpty
    }

    func begin() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        let id = UUID()
        sessions.insert(id)
        return id
    }

    func end(_ session: UUID) {
        lock.lock()
        sessions.remove(session)
        lock.unlock()
    }
}

final class KeyboardActionBindingsController {
    static let shared = KeyboardActionBindingsController()
    typealias Mapping = Scheme.Buttons.KeyboardMapping
    typealias Action = Scheme.Buttons.Mapping.Action

    struct Effects {
        var perform: (Action, String?) -> Void
        var beginHold: (Action, UInt16) -> Void
        var endHold: (Action, UInt16) -> Void
        var reset: () -> Void
    }

    private struct ActivePress {
        var owner: UUID
        var mapping: Mapping
        var targetBundleIdentifier: String?
    }

    private var owner: UUID?
    private var active = [UInt16: ActivePress]()
    private var suppressedKeyUps = Set<UInt16>()
    private let injectedEffects: Effects?
    private let executorFactory: () -> ButtonActionExecutor
    private var executor: ButtonActionExecutor?

    init(
        effects: Effects? = nil,
        executorFactory: @escaping () -> ButtonActionExecutor = {
            ButtonActionExecutor(
                keySimulator: KeySimulator(eventSourceUserData: CGEvent.linearMouseSyntheticEventUserData)
            )
        }
    ) {
        injectedEffects = effects
        self.executorFactory = executorFactory
    }

    /// Construction belongs only to an actual action, never teardown. In
    /// particular, a main-thread stop can be waiting for EventThread.reset().
    private func executorForAction() -> ButtonActionExecutor {
        if let executor { return executor }
        let executor = executorFactory()
        self.executor = executor
        return executor
    }

    /// Called only on EventThread. Synthetic output never re-enters recognition.
    func consume(
        _ event: CGEvent,
        owner: UUID,
        mappings: [Mapping],
        targetBundleIdentifier: String?
    ) -> Bool {
        guard !event.isLinearMouseSyntheticEvent,
              event.getIntegerValueField(.eventSourceUnixProcessID) != Int64(getpid()) else {
            return false
        }
        if KeyboardActionRecordingState.shared.isRecording || SettingsState.shared.recording {
            releaseAll()
            suppressedKeyUps.removeAll()
            self.owner = nil
            return false
        }
        return handle(
            type: event.type,
            keyCode: UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode)),
            modifiers: event.flags.rawValue,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            owner: owner,
            mappings: mappings,
            targetBundleIdentifier: targetBundleIdentifier
        )
    }

    /// Pure input surface used by tests; actual execution can be injected.
    func handle(
        type: CGEventType,
        keyCode: UInt16,
        modifiers: UInt64,
        isRepeat: Bool,
        owner nextOwner: UUID,
        mappings: [Mapping],
        targetBundleIdentifier: String?
    ) -> Bool {
        if owner != nextOwner {
            releaseAll()
            owner = nextOwner
        }

        if type == .keyUp {
            if let press = active.removeValue(forKey: keyCode) {
                end(press, keyCode: keyCode)
                suppressedKeyUps.remove(keyCode)
                return true
            }
            return suppressedKeyUps.remove(keyCode) != nil
        }

        if type == .flagsChanged {
            let flags = modifiers & Mapping.modifierMask
            let released = active.filter { $0.value.mapping.modifiers & flags != $0.value.mapping.modifiers }
            for (code, press) in released {
                end(press, keyCode: code)
                active.removeValue(forKey: code)
                suppressedKeyUps.insert(code)
            }
            return false
        }

        guard type == .keyDown else { return false }
        if let press = active[keyCode] {
            if press.mapping.behavior == .repeat, isRepeat {
                perform(press.mapping.action, target: press.targetBundleIdentifier)
            }
            return true
        }
        if suppressedKeyUps.contains(keyCode) { return true }
        guard !isRepeat,
              let mapping = mappings.last(where: { $0.matches(keyCode: keyCode, modifiers: modifiers) }),
              mapping.enabled, mapping.isValid else { return false }

        active[keyCode] = .init(owner: nextOwner, mapping: mapping, targetBundleIdentifier: targetBundleIdentifier)
        if mapping.behavior == .hold {
            if let injectedEffects {
                injectedEffects.beginHold(mapping.action, keyCode)
            } else {
                executorForAction().beginPress(.init(action: mapping.action, behavior: .hold), buttons: token(keyCode), targetBundleIdentifier: targetBundleIdentifier)
            }
        } else {
            perform(mapping.action, target: targetBundleIdentifier)
        }
        return true
    }

    func release(owner: UUID) {
        for (code, press) in active.filter({ $0.value.owner == owner }) {
            end(press, keyCode: code)
            active.removeValue(forKey: code)
            suppressedKeyUps.insert(code)
        }
        if self.owner == owner { self.owner = nil }
    }

    func reset() {
        releaseAll()
        active.removeAll()
        suppressedKeyUps.removeAll()
        owner = nil
        if let injectedEffects { injectedEffects.reset() } else { executor?.deactivate() }
    }

    private func releaseAll() {
        for (code, press) in active {
            end(press, keyCode: code)
            suppressedKeyUps.insert(code)
        }
        active.removeAll()
    }

    private func perform(_ action: Action, target: String?) {
        if let injectedEffects { injectedEffects.perform(action, target) }
        else { executorForAction().perform(action, targetBundleIdentifier: target) }
    }

    private func end(_ press: ActivePress, keyCode: UInt16) {
        guard press.mapping.behavior == .hold else { return }
        if let injectedEffects { injectedEffects.endHold(press.mapping.action, keyCode) }
        else { executor?.endPress(.init(action: press.mapping.action, behavior: .hold), buttons: token(keyCode)) }
    }

    private func token(_ keyCode: UInt16) -> Set<Scheme.Buttons.Mapping.Button> {
        // Executor dictionaries use opaque press IDs. This private executor
        // never shares its token namespace with physical mouse mappings.
        [.mouse(65_536 + Int(keyCode))]
    }
}

final class KeyboardActionBindingsTransformer: EventTransformer, Deactivatable {
    let handlesPointerMotion = false
    private let owner = UUID()
    private let mappings: [Scheme.Buttons.KeyboardMapping]
    private let targetBundleIdentifier: String?

    init(mappings: [Scheme.Buttons.KeyboardMapping], targetBundleIdentifier: String?) {
        self.mappings = mappings
        self.targetBundleIdentifier = targetBundleIdentifier
    }

    func transform(_ event: CGEvent, in _: EventTransformerContext) -> CGEvent? {
        let consumed = KeyboardActionBindingsController.shared.consume(
            event, owner: owner, mappings: mappings, targetBundleIdentifier: targetBundleIdentifier
        )
        if consumed, event.type == .keyDown || event.type == .keyUp {
            ScrollHotkeyController.shared.discard(.init(
                type: .keyboard,
                code: UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
            ))
        }
        return consumed ? nil : event
    }

    func deactivate() {
        KeyboardActionBindingsController.shared.release(owner: owner)
    }
}
