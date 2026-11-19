// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

extension ScrollingSettings {
    struct ModifierKeysSection: View {
        @ObservedObject private var state = ScrollingSettingsState.shared

        @State private var direction: Scheme.Scrolling.BidirectionalDirection = .vertical

        private var actions: Binding<Scheme.Scrolling.Modifiers> {
            let axis = direction
            return Binding(
                get: { state.mergedScheme.scrolling.modifiers[axis] ?? .init() },
                set: { state.scheme.scrolling.modifiers[axis] = $0 }
            )
        }

        var body: some View {
            SettingsCard(
                title: NSLocalizedString("Wheel shortcuts", comment: ""),
                symbol: "keyboard",
                headerAccessory: AnyView(
                    DirectionPicker(direction: $direction)
                        .controlSize(.small)
                        .frame(width: 150)
                        .accessibilityLabel("Wheel shortcut axis")
                )
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    ModifierKeyActionPicker(label: "⌃ Ctrl", action: actions.control)
                    ModifierKeyActionPicker(label: "⇧ Shift", action: actions.shift)
                    ModifierKeyActionPicker(label: "⌥ Option", action: actions.option)
                    ModifierKeyActionPicker(label: "⌘ Cmd", action: actions.command)
                }
                Divider()
                SettingsDisclosure(title: NSLocalizedString("Record other scroll hotkeys", comment: "")) {
                    ScrollHotkeysSection()
                }
            }
        }
    }
}
