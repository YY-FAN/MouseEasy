// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct UniversalBackForwardSection: View {
    @ObservedObject var state: ButtonsSettingsState = .shared

    var body: some View {
        SettingsToggleRow(
            title: NSLocalizedString("Universal back and forward", comment: ""),
            subtitle: NSLocalizedString("Use side buttons to go back and forward in more apps. Your assigned button actions take priority.", comment: ""),
            isOn: $state.universalBackForward,
            fillsRow: true
        )
    }
}
