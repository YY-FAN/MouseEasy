// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

extension ScrollingSettings {
    static let pairedControlWidth: CGFloat = 120

    struct Header: View {
        @ObservedObject private var state = ScrollingSettingsState.shared

        var body: some View {
            SettingsControlRow(title: NSLocalizedString("Scroll direction", comment: "")) {
                DirectionPicker(direction: $state.direction)
                    .frame(width: pairedControlWidth, alignment: .leading)
                HStack(spacing: 8) {
                    Text("Reverse direction").fixedSize()
                    Toggle("Reverse direction", isOn: $state.reverseScrolling)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .fixedSize()
                }
                .help(state.direction == .vertical
                    ? NSLocalizedString("Reverse vertical wheel movement.", comment: "")
                    : NSLocalizedString("Reverse horizontal scrolling. Some back and forward gestures may also change.", comment: ""))
            }
        }
    }

    struct DirectionPicker: View {
        @Binding var direction: Scheme.Scrolling.BidirectionalDirection

        var body: some View {
            Picker("Scroll axis", selection: $direction) {
                Text("Vertical ↕").tag(Scheme.Scrolling.BidirectionalDirection.vertical)
                Text("Horizontal ↔").tag(Scheme.Scrolling.BidirectionalDirection.horizontal)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityLabel("Scroll direction")
        }
    }
}
