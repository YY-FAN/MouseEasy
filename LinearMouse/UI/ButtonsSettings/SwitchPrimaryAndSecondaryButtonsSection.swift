// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct SwitchPrimaryAndSecondaryButtonsSection: View {
    @ObservedObject var state: ButtonsSettingsState = .shared

    var body: some View {
        SettingsToggleRow(
            title: NSLocalizedString("Swap left and right buttons", comment: ""),
            subtitle: NSLocalizedString("Use the right button as the primary button for left-handed use.", comment: ""),
            isOn: $state.switchPrimaryAndSecondaryButtons,
            fillsRow: true
        )
    }
}
