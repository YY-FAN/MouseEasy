// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit

enum LinearMouse {
    static var appBundleIdentifier: String {
        Bundle.main.infoDictionary?[kCFBundleIdentifierKey as String] as? String ?? "io.github.yyfan.MouseWorkbench.dev"
    }

    static var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ??
            Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? "MouseEasy"
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "(unknown)"
    }

    static func brandedLocalization(_ key: String) -> String {
        NSLocalizedString(key, comment: "Application interface")
            .replacingOccurrences(of: "LinearMouse", with: appName)
    }

    static func updateApplicationMenuNames() {
        func update(_ menu: NSMenu) {
            menu.title = menu.title.replacingOccurrences(of: "LinearMouse", with: appName)
            for item in menu.items {
                item.title = item.title.replacingOccurrences(of: "LinearMouse", with: appName)
                if let submenu = item.submenu { update(submenu) }
            }
        }
        if let menu = NSApplication.shared.mainMenu { update(menu) }
    }
}
