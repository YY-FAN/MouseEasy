import Foundation
import KeyKit

@main
struct CommonActionCatalogTests {
    static func main() {
        let entries = CommonActionCatalog.entries
        precondition(Set(entries.map(\.id)).count == entries.count, "Operation IDs must be stable and unique")
        precondition(entries.allSatisfy { !$0.title.isEmpty })
        precondition(CommonActionCatalog.entry(for: [.command, .tab])?.title == "Switch Apps")
        precondition(CommonActionCatalog.entry(for: [.commandRight, .tab])?.id == "switch-app")
        precondition(CommonActionCatalog.entry(for: [.tab, .command])?.id == "switch-app")
        precondition(CommonActionCatalog.entry(for: [.shift, .command, .tab])?.id == "switch-app-back")
        precondition(CommonActionCatalog.entry(for: [.command, .backquote])?.title == "Cycle App Windows")
        precondition(CommonActionCatalog.entry(for: [.command, .tab])?.label == "Switch Apps  ⌘⇥")
        precondition(CommonActionCatalog.entry(for: [.command, .tab, .tab]) == nil, "Repeated non-modifier keys are not a single shortcut")
        precondition(CommonActionCatalog.entry(for: [.command, .f20]) == nil)
        precondition(CommonActionCatalog.shortcut([.command, .shift, .control, .four]) == "⌃⇧⌘4")
        precondition(CommonActionCatalog.shortcut([.commandRight, .command, .tab]) == "⌘⇥")
        precondition(CommonActionCatalog.shortcut([.control, .option, .arrowLeft]) == "⌃⌥←")
        precondition(CommonActionCatalog.entry(forSystemAction: "missionControl")?.title == "Mission Control: Show All Windows")
        precondition(CommonActionCatalog.entry(forSystemAction: "missionControl")?.shortcut == nil, "System actions must not claim fixed user-configurable shortcuts")
        precondition(CommonActionCatalog.entry(for: "finder-downloads")?.shortcut == "⌥⌘L")
        precondition(CommonActionCatalog.entry(for: "finder-downloads")?.context == "Finder")
        precondition(CommonActionCatalog.entry(for: "browser-restore-tab")?.shortcut == "⇧⌘T")
        precondition(CommonActionCatalog.recommended.count == 8)
        precondition(CommonActionCatalog.recommended.first?.id == "switch-app")
        let findOrFolder = CommonActionCatalog.entry(for: [.command, .shift, .g])
        precondition(findOrFolder?.title == "Find Previous / Go to Folder", "A shared shortcut must not pick the first application's operation name")
        precondition(findOrFolder?.context == "Apps that support Find: Find Previous; Finder: Go to Folder")
        precondition(findOrFolder?.shortcut == "⇧⌘G")
        let folderOrStart = CommonActionCatalog.entry(for: [.commandRight, .arrowUp])
        precondition(folderOrStart?.title == "Open Enclosing Folder / Go to Beginning")
        precondition(folderOrStart?.context == "Finder: Open Enclosing Folder; Browsers and document apps: Go to Beginning")
        let openOrEnd = CommonActionCatalog.entry(for: [.command, .arrowDown])
        precondition(openOrEnd?.title == "Open Selected File / Go to End")
        precondition(openOrEnd?.context == "Finder: Open Selected File; Browsers and document apps: Go to End")
        precondition(CommonActionCatalog.entry(for: "finder-go")?.title == "Go to Folder", "The operation picker keeps each application's specific action")
        precondition(CommonActionCatalog.entry(for: "document-top")?.title == "Go to Beginning")
        print("PASS: 29 catalog checks; legacy shortcut recognition, modifier normalization, operation names, symbols, scopes, shared-shortcut names and system-action labels")
        print("CATALOG: \(entries.count) operations in \(CommonActionCatalog.groups.count) groups; no actions executed")
    }
}
