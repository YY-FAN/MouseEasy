// SPDX-License-Identifier: MIT
// Copyright (c) 2026 MouseWorkbench contributors

import Foundation
import KeyKit

/// One source for the operation picker, shortcut labels and existing-binding names.
/// Shortcut facts checked against Apple's Mac and Safari guides on 2026-11-17.
enum CommonActionCatalog {
    struct Entry: Identifiable, Equatable {
        enum Output: Equatable {
            case keyboard([Key])
            case system(String)
        }
        let id: String
        let title: String
        let output: Output
        var context: String? = nil

        var keys: [Key]? {
            guard case let .keyboard(keys) = output else { return nil }
            return keys
        }
        var shortcut: String? { keys.map(CommonActionCatalog.shortcut) }
        var label: String {
            shortcut.map { "\(title)  \($0)" } ?? title
        }
    }

    struct Group: Identifiable {
        var id: String { title }
        let title: String
        let entries: [Entry]
    }

    private static func key(_ id: String, _ title: String, _ keys: [Key], _ context: String? = nil) -> Entry {
        .init(id: id, title: NSLocalizedString(title, comment: ""), output: .keyboard(keys),
              context: context.map { NSLocalizedString($0, comment: "") })
    }
    private static func system(_ id: String, _ title: String) -> Entry {
        .init(id: id, title: NSLocalizedString(title, comment: ""), output: .system(id))
    }

    static let groups: [Group] = [
        .init(title: NSLocalizedString("Apps & Windows", comment: ""), entries: [
            key("switch-app", "Switch Apps", [.command, .tab]),
            key("switch-app-back", "Switch Apps in Reverse", [.command, .shift, .tab]),
            key("switch-window", "Cycle App Windows", [.command, .backquote]),
            key("switch-window-back", "Cycle App Windows in Reverse", [.command, .shift, .backquote]),
            key("minimize", "Minimize Window", [.command, .m]),
            key("minimize-all", "Minimize All App Windows", [.command, .option, .m]),
            key("hide-app", "Hide Current App", [.command, .h]),
            key("hide-others", "Hide Other Apps", [.command, .option, .h]),
            key("close-window", "Close Window or Tab", [.command, .w]),
            key("fullscreen", "Toggle Full Screen", [.control, .command, .f], "Apps that support full screen"),
            key("app-settings", "Open App Settings", [.command, .comma]),
            key("quit-app", "Quit Current App", [.command, .q])
        ]),
        .init(title: NSLocalizedString("Desktop & System", comment: ""), entries: [
            system("missionControl", "Mission Control: Show All Windows"),
            system("appExpose", "Show All Windows of Current App"),
            system("showDesktop", "Show Desktop"),
            system("missionControl.spaceLeft", "Move Left a Space"),
            system("missionControl.spaceRight", "Move Right a Space"),
            system("launchpad", "Open Apps or Launchpad"),
            key("spotlight", "Open Spotlight", [.command, .space], "With the default system shortcuts"),
            key("emoji", "Show Emoji & Symbols", [.control, .command, .space]),
            key("toggle-dock", "Show or Hide Dock", [.option, .command, .d]),
            key("lock-screen", "Lock Screen", [.control, .command, .q]),
            system("window.maximize", "Maximize Current Window"),
            system("window.minimize", "Minimize Current Window (System)"),
            system("lookUpAndDataDetectors", "Look Up Selection"),
            system("smartZoom", "Smart Zoom")
        ]),
        .init(title: NSLocalizedString("Screenshots & Recording", comment: ""), entries: [
            key("screenshot-region", "Capture Selection", [.command, .shift, .four]),
            key("screenshot-screen", "Capture Screen", [.command, .shift, .three]),
            key("screenshot-toolbar", "Open Screenshot Toolbar", [.command, .shift, .five]),
            key("screenshot-region-copy", "Copy Selection Screenshot", [.control, .command, .shift, .four]),
            key("screenshot-screen-copy", "Copy Screen Screenshot", [.control, .command, .shift, .three])
        ]),
        .init(title: NSLocalizedString("Editing & Documents", comment: ""), entries: [
            key("copy", "Copy", [.command, .c]),
            key("cut", "Cut", [.command, .x]),
            key("paste", "Paste", [.command, .v]),
            key("paste-style", "Paste and Match Style", [.command, .option, .shift, .v], "In supported apps"),
            key("select-all", "Select All", [.command, .a]),
            key("undo", "Undo", [.command, .z]),
            key("redo", "Redo", [.command, .shift, .z]),
            key("save", "Save", [.command, .s]),
            key("find", "Find", [.command, .f]),
            key("find-next", "Find Next", [.command, .g]),
            key("find-previous", "Find Previous", [.command, .shift, .g], "Apps that support Find"),
            key("new", "New Window or Document", [.command, .n]),
            key("open", "Open File", [.command, .o]),
            key("print", "Print", [.command, .p])
        ]),
        .init(title: NSLocalizedString("Finder", comment: ""), entries: [
            key("finder-new-folder", "New Folder", [.command, .shift, .n], "Finder"),
            key("finder-info", "Get Info", [.command, .i], "Finder"),
            key("finder-go", "Go to Folder", [.command, .shift, .g], "Finder"),
            key("finder-downloads", "Open Downloads", [.command, .option, .l], "Finder"),
            key("finder-home", "Open Home Folder", [.command, .shift, .h], "Finder"),
            key("finder-desktop", "Open Desktop Folder", [.command, .shift, .d], "Finder"),
            key("finder-documents", "Open Documents Folder", [.command, .shift, .o], "Finder"),
            key("finder-quicklook", "Quick Look", [.space], "Finder"),
            key("finder-duplicate", "Duplicate File", [.command, .d], "Finder"),
            key("finder-move-paste", "Move Copied Files", [.command, .option, .v], "Finder"),
            key("finder-trash", "Move to Trash", [.command, .delete], "Finder"),
            key("finder-up", "Open Enclosing Folder", [.command, .arrowUp], "Finder"),
            key("finder-open", "Open Selected File", [.command, .arrowDown], "Finder"),
            key("finder-path", "Show or Hide Path Bar", [.command, .option, .p], "Finder")
        ]),
        .init(title: NSLocalizedString("Browsing & Tabs", comment: ""), entries: [
            key("browser-back", "Go Back", [.command, .backetLeft], "Browsers such as Safari"),
            key("browser-forward", "Go Forward", [.command, .backetRight], "Browsers such as Safari"),
            key("browser-reload", "Reload Page", [.command, .r], "Browsers such as Safari"),
            key("browser-address", "Focus Address Bar", [.command, .l], "Browsers such as Safari"),
            key("browser-new-tab", "New Tab", [.command, .t], "Browsers such as Safari"),
            key("browser-next-tab", "Next Tab", [.control, .tab], "Browsers such as Safari"),
            key("browser-previous-tab", "Previous Tab", [.control, .shift, .tab], "Browsers such as Safari"),
            key("browser-restore-tab", "Reopen Closed Tab", [.command, .shift, .t], "Browsers such as Safari"),
            key("page-up", "Page Up", [.pageUp]),
            key("page-down", "Page Down", [.pageDown]),
            key("document-top", "Go to Beginning", [.command, .arrowUp], "Browsers and document apps"),
            key("document-end", "Go to End", [.command, .arrowDown], "Browsers and document apps")
        ]),
        .init(title: NSLocalizedString("Sound & Playback", comment: ""), entries: [
            system("media.volumeUp", "Volume Up"), system("media.volumeDown", "Volume Down"),
            system("media.mute", "Toggle Mute"), system("media.playPause", "Play or Pause"),
            system("media.previous", "Previous Track"), system("media.next", "Next Track"),
            system("media.fastForward", "Fast Forward"), system("media.rewind", "Rewind"),
            system("display.brightnessUp", "Increase Display Brightness"), system("display.brightnessDown", "Decrease Display Brightness"),
            system("keyboard.brightnessUp", "Increase Keyboard Brightness"), system("keyboard.brightnessDown", "Decrease Keyboard Brightness")
        ]),
        .init(title: NSLocalizedString("Mouse Actions", comment: ""), entries: [
            system("mouse.button.left", "Primary Click"), system("mouse.button.leftDouble", "Double Primary Click"),
            system("mouse.button.middle", "Middle Click"), system("mouse.button.right", "Secondary Click"),
            system("mouse.button.back", "Back"), system("mouse.button.forward", "Forward"),
            system("mouse.wheel.scrollUp", "Scroll Up"), system("mouse.wheel.scrollDown", "Scroll Down"),
            system("mouse.wheel.scrollLeft", "Scroll Left"), system("mouse.wheel.scrollRight", "Scroll Right")
        ])
    ]

    static var entries: [Entry] { groups.flatMap(\.entries) }
    static var recommended: [Entry] {
        let ids = ["switch-app", "switch-window", "missionControl", "showDesktop", "screenshot-region", "copy", "paste", "browser-back"]
        return ids.compactMap { id in entries.first { $0.id == id } }
    }
    static func entry(for id: String) -> Entry? { entries.first { $0.id == id } }
    static func entry(for keys: [Key]) -> Entry? {
        let normalized = normalizedKeys(keys)
        let matches = entries.filter { entry in entry.keys.map(normalizedKeys) == normalized }
        guard let first = matches.first else { return nil }
        guard matches.count > 1 else { return first }

        // Existing mappings store keys, not an operation ID. A shared shortcut
        // can therefore only be named by all its app-dependent uses.
        return .init(
            id: matches.map(\.id).joined(separator: "+"),
            title: matches.map(\.title).joined(separator: NSLocalizedString(" / ", comment: "Multiple shortcut actions")),
            output: .keyboard(normalized),
            context: matches.map { entry in
                let context = entry.context ?? NSLocalizedString("Apps that support this shortcut", comment: "")
                return String(format: NSLocalizedString("%@: %@", comment: "Action context and name"), context, entry.title)
            }
                .joined(separator: NSLocalizedString("; ", comment: "Action contexts"))
        )
    }
    static func entry(forSystemAction rawValue: String) -> Entry? {
        entries.first { $0.output == .system(rawValue) }
    }

    static func shortcut(_ keys: [Key]) -> String {
        normalizedKeys(keys).map { key in
            switch key {
            case .tab: return "⇥"
            case .space: return NSLocalizedString("Space", comment: "")
            case .delete: return "⌫"
            case .escape: return "⎋"
            case .arrowLeft: return "←"
            case .arrowRight: return "→"
            case .arrowUp: return "↑"
            case .arrowDown: return "↓"
            case .pageUp: return "⇞"
            case .pageDown: return "⇟"
            case .home: return "↖"
            case .end: return "↘"
            case .enter: return "↩"
            default: return key.description
            }
        }.joined()
    }

    static func normalizedKeys(_ keys: [Key]) -> [Key] {
        let normalized = keys.map { key -> Key in
            switch key {
            case .commandRight: return .command
            case .shiftRight: return .shift
            case .optionRight: return .option
            case .controlRight: return .control
            default: return key
            }
        }
        let order: [Key] = [.control, .option, .shift, .command]
        return order.filter { normalized.contains($0) } + normalized.filter { !$0.isModifier }
    }
}
