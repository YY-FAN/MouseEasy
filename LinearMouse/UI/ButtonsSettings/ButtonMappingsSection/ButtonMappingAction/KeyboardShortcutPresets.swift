// SPDX-License-Identifier: MIT
// Copyright (c) 2026 MouseWorkbench contributors

import KeyKit
import SwiftUI

extension CommonActionCatalog.Entry {
    var mappingAction: Scheme.Buttons.Mapping.Action {
        switch output {
        case let .keyboard(keys): return .arg1(.keyPress(keys))
        case let .system(rawValue):
            return .arg0(Scheme.Buttons.Mapping.Action.Arg0(rawValue: rawValue) ?? .auto)
        }
    }
}

extension Scheme.Buttons {
    static let windowSwitchingPreset: [Mapping] = [(3, "switch-window"), (4, "switch-app")].compactMap { number, id in
        guard let action = CommonActionCatalog.entry(for: id)?.mappingAction else { return nil }
        return Mapping(trigger: .init(input: .button(.mouse(number))), outcomes: .init(shortPress: action))
    }

    var windowSwitchingButtonsAreAvailable: Bool {
        Self.windowSwitchingPreset.allSatisfy { preset in
            guard let trigger = preset.trigger else { return false }
            return !(mappings ?? []).contains { $0.effectiveTrigger?.isEquivalent(to: trigger) == true }
        }
    }
}

struct KeyboardShortcutPresets: View {
    @Binding var keys: [Key]

    var body: some View {
        Menu("Choose a shortcut…") {
            ForEach(CommonActionCatalog.groups) { group in
                let entries = group.entries.filter { $0.keys != nil }
                if !entries.isEmpty {
                    Menu(group.title) {
                        ForEach(entries) { entry in
                            Button(entry.label) { keys = entry.keys ?? [] }
                        }
                    }
                }
            }
        }
    }
}
