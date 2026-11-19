// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit

enum Application {
    static func restart() { restart(showGeneral: false) }

    static func restart(showGeneral: Bool) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait for termination cleanup to finish before reopening this exact bundle.
        task.arguments = ["-c",
            #"while kill -0 "$1" 2>/dev/null; do sleep 0.1; done; exec /usr/bin/open "$2" --args "$3""#,
            "mouseeasy-reopen", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath,
            showGeneral ? "--show-general" : "--show"]
        do {
            try task.run()
            NSApplication.shared.terminate(nil)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

enum InterfaceLanguage: String {
    case system, chinese = "zh-Hans", english = "en"

    static var current: Self {
        guard let domain = Bundle.main.bundleIdentifier,
              let languages = UserDefaults.standard.persistentDomain(forName: domain)?["AppleLanguages"] as? [String],
              let first = languages.first else { return .system }
        return Self(rawValue: first) ?? .system
    }

    func apply() {
        guard self != Self.current else { return }
        // Use the native per-app preference so AppKit, SwiftUI, and permission panels
        // all load the same localization on the next launch.
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
        Application.restart(showGeneral: true)
    }
}
