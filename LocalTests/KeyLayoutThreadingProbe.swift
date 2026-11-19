// SPDX-License-Identifier: MIT
// Copyright (c) 2026 WheelEase contributors

import AppKit
import Carbon
import Foundation
import KeyKit

private final class ProbeResult: @unchecked Sendable {
    private let lock = NSLock()
    private var storedFailure: String?
    func fail(_ message: String) { lock.lock(); storedFailure = message; lock.unlock() }
    var failure: String? { lock.lock(); defer { lock.unlock() }; return storedFailure }
}

@main
struct KeyLayoutThreadingProbe {
    static func main() {
        precondition(Thread.isMainThread)
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) != nil else {
            print("FAIL: current system keyboard layout is unavailable to this process")
            exit(1)
        }
        KeyCodeResolver.prepareForEventProcessing()
        let reference = KeyCodeResolver()
        let keys: [Key] = [.a, .z, .backquote, .tab, .command, .arrowLeft, .numpadPlus]
        let expected = keys.map { (reference.keyCode(for: $0), reference.keyCode(for: $0, modifiers: .maskCommand)) }
        let done = DispatchSemaphore(value: 0)
        let result = ProbeResult()

        Thread {
            for _ in 0 ..< 20 {
                let resolver = KeyCodeResolver()
                for (index, key) in keys.enumerated() {
                    if resolver.keyCode(for: key) != expected[index].0
                        || resolver.keyCode(for: key, modifiers: .maskCommand) != expected[index].1 {
                        result.fail("Background resolver changed a current-layout key mapping")
                    }
                }
                // Construct the same production simulator used by button cleanup.
                // No press/down/up/reset methods are called, so no input is posted.
                _ = KeySimulator()
            }
            done.signal()
        }.start()

        // Deliberately prevent the main queue from servicing synchronous work.
        // The previous implementation deadlocks here until this deadline.
        guard done.wait(timeout: .now() + 3) == .success else {
            print("FAIL: keyboard initialization waited on the blocked main thread")
            exit(1)
        }
        guard result.failure == nil else {
            print("FAIL: \(result.failure!)")
            exit(1)
        }
        let stopped = DispatchSemaphore(value: 0)
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            if stopped.wait(timeout: .now()) == .timedOut {
                print("FAIL: production EventThread.stop deadlocked during simulator initialization")
                exit(1)
            }
        }
        let eventThread = EventThread()
        eventThread.start()
        eventThread.onWillStop = { _ = KeySimulator() }
        eventThread.stop()
        stopped.signal()
        print("PASS: 20 production background resolvers and simulators initialized while main waited; current layout and Command mappings preserved")
        print("PASS: production EventThread.stop completed with keyboard initialization in its cleanup callback")
        print("0 input events posted")
    }
}
