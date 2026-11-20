// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

extension ScrollingSettings {
    struct ModifierKeysSection: View {
        @ObservedObject private var state = ScrollingSettingsState.shared

        @State private var direction: Scheme.Scrolling.BidirectionalDirection = .vertical

        var body: some View {
            SettingsCard(
                title: NSLocalizedString("Wheel behavior with modifier keys", comment: ""),
                symbol: "keyboard",
                headerAccessory: AnyView(
                    DirectionPicker(direction: $direction)
                        .controlSize(.small)
                        .frame(width: 150)
                        .accessibilityLabel("Wheel shortcut axis")
                )
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(WheelModifierKey.all, id: \.self) { key in
                        ModifierKeyActionPicker(label: key.label, direction: direction,
                                                action: state.modifierActions(for: direction)[dynamicMember: key.action])
                    }
                }
                Divider()
                SettingsDisclosure(title: NSLocalizedString("Record other scroll hotkeys", comment: "")) {
                    ScrollHotkeysSection()
                }
            }
        }
    }
}
