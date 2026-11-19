// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

extension ScrollingSettings {
    struct ReverseScrollingSection: View {
        @ObservedObject private var state = ScrollingSettingsState.shared

        var body: some View {
            SettingsToggleRow(
                title: state.direction == .vertical ? NSLocalizedString("Reverse vertical scrolling", comment: "") : NSLocalizedString("Reverse horizontal scrolling", comment: ""),
                subtitle: state.direction == .vertical
                    ? NSLocalizedString("Change the vertical direction of the mouse wheel.", comment: "")
                    : NSLocalizedString("Change horizontal scroll direction, including some navigation gestures.", comment: ""),
                isOn: $state.reverseScrolling
            )
        }
    }
}
