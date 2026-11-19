// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

extension ScrollingSettings {
    struct LogitechHighResolutionWheelSection: View {
        @ObservedObject private var state = ScrollingSettingsState.shared

        var body: some View {
            SettingsToggleRow(
                title: NSLocalizedString("High-resolution wheel", comment: ""),
                subtitle: NSLocalizedString("Use smaller vertical scroll steps on supported Logitech mice.", comment: ""),
                isOn: $state.highResolutionWheel
            )
        }
    }
}
