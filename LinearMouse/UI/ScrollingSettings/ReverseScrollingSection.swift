// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

extension ScrollingSettings {
    struct ReverseScrollingSection: View {
        @ObservedObject private var state = ScrollingSettingsState.shared

        var body: some View {
            Toggle("Reverse horizontal scrolling", isOn: $state.reverseHorizontalScrolling)
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()
                .help(NSLocalizedString("Reverse horizontal scrolling. Some back and forward gestures may also change.", comment: ""))
        }
    }
}
