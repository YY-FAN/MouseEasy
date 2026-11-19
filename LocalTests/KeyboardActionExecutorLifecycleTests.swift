// SPDX-License-Identifier: MIT
// Copyright (c) 2026 WheelEase contributors

import AppKit
import Foundation

/// Runs the production controller while main deliberately waits, like the
/// EventThread shutdown handshake. The executor factory is an inert recorder;
/// constructing the default live executor remains a fatal test failure.
enum KeyboardActionExecutorLifecycleTests {
    private final class Probe {
        let executor = ButtonActionExecutor()
        var creations = 0
        var creationWasOnMain = false
        var checks = [(Bool, String)]()

        func check(_ value: Bool, _ message: String) { checks.append((value, message)) }
    }

    static func run(check: (Bool, String) -> Void) {
        precondition(Thread.isMainThread)
        let probe = Probe()
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            defer { finished.signal() }

            // A completely unused production controller must stop without
            // touching its default KeySimulator factory.
            let unused = KeyboardActionBindingsController()
            unused.reset()
            unused.reset()
            unused.release(owner: UUID())
            probe.check(true, "Unused reset and release completed without a live executor")

            let controller = KeyboardActionBindingsController(executorFactory: {
                probe.creations += 1
                probe.creationWasOnMain = Thread.isMainThread
                return probe.executor
            })
            let owner = UUID()
            let command = CGEventFlags.maskCommand.rawValue
            let once = Scheme.Buttons.KeyboardMapping(
                keyCode: 100, modifiers: command, action: .arg0(.missionControl)
            )
            let hold = Scheme.Buttons.KeyboardMapping(
                keyCode: 101, modifiers: command, behavior: .hold,
                action: .arg1(.keyPress([.command, .tab]))
            )
            func input(_ type: CGEventType, _ code: UInt16,
                       mappings: [Scheme.Buttons.KeyboardMapping]) -> Bool {
                controller.handle(
                    type: type, keyCode: code, modifiers: command, isRepeat: false,
                    owner: owner, mappings: mappings, targetBundleIdentifier: "test.app"
                )
            }

            controller.reset()
            probe.check(probe.creations == 0, "Reset must not create an unused executor")
            probe.check(!input(.keyDown, 99, mappings: [once]), "Unmatched key must pass through")
            probe.check(probe.creations == 0, "Unmatched input must not create an executor")
            probe.check(input(.keyDown, 100, mappings: [once]), "First action must be consumed")
            probe.check(probe.creations == 1 && !probe.creationWasOnMain,
                        "First action creates exactly one executor directly on its event worker")
            probe.check(probe.executor.calls == ["perform"], "First action must execute immediately")
            probe.check(input(.keyUp, 100, mappings: []), "First action key-up must stay paired")
            controller.reset()
            probe.check(probe.executor.calls == ["perform", "reset"], "Used reset deactivates the existing executor")
            probe.check(input(.keyDown, 101, mappings: [hold]), "Hold must start after reset")
            controller.release(owner: owner)
            probe.check(probe.executor.calls.suffix(2) == ["beginHold", "endHold"],
                        "Owner release must end the existing hold")
            controller.reset()
            probe.check(probe.creations == 1, "Reset, release and later actions must reuse the same executor")
        }
        let completed = finished.wait(timeout: .now() + 2) == .success
        check(completed, "Executor lifecycle must complete while main waits; no main-thread synchronous initialization")
        guard completed else { return }
        for (value, message) in probe.checks { check(value, message) }
    }
}
