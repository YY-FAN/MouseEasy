// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct ButtonsSettings: View {
    var body: some View {
        DetailView {
            VStack(alignment: .leading, spacing: 12) {
                ButtonMappingsSection()

                SettingsCard(title: NSLocalizedString("Button behavior", comment: ""), symbol: "arrow.left.arrow.right") {
                    UniversalBackForwardSection()
                    Divider()
                    SwitchPrimaryAndSecondaryButtonsSection()
                }

                SettingsCard(title: NSLocalizedString("Auto-scroll", comment: ""), symbol: "arrow.up.and.down") {
                    AutoScrollSection()
                }

                SettingsDisclosure(title: NSLocalizedString("Gestures, keyboard & accidental clicks", comment: "")) {
                    SettingsCard(title: NSLocalizedString("Swipe gestures", comment: ""), symbol: "hand.draw") {
                        SwipeSettingsSection()
                    }
                    KeyboardActionBindingsSection()
                    ClickDebouncingSection()
                }
                .padding(.horizontal, 4)
            }
        }
    }
}
