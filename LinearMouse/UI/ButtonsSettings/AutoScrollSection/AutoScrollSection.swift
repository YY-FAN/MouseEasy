// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct AutoScrollSection: View {
    @ObservedObject private var state: ButtonsSettingsState = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsToggleRow(
                title: NSLocalizedString("Enable auto-scroll", comment: ""),
                subtitle: NSLocalizedString("Press the assigned button, then move the mouse to keep scrolling.", comment: ""),
                isOn: $state.autoScrollEnabled,
                fillsRow: true
            )

            if state.autoScrollEnabled {
                Divider()
                SettingsDisclosure(title: NSLocalizedString("Auto-scroll options", comment: "")) {
                    configurationControls
                }
            }
        }
        .help(Text(modeDescription))
    }

    private var configurationControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Toggle(
                        "Keep scrolling after release",
                        isOn: $state.autoScrollToggleModeEnabled.animation()
                    )
                    .toggleStyle(.checkbox)
                    .disabled(state.autoScrollToggleModeEnabled && !state.autoScrollHoldModeEnabled)

                    if state.autoScrollToggleModeEnabled {
                        Picker(String(""), selection: $state.autoScrollToggleActivation) {
                            Text("Short press")
                                .tag(Scheme.Buttons.AutoScroll.ToggleActivation.shortPress)
                            Text("Long press")
                                .tag(Scheme.Buttons.AutoScroll.ToggleActivation.longPress)
                        }
                        .labelsHidden()
                        .fixedSize()
                        .modifier(PickerViewModifier())
                    }
                }

                Toggle("Hold to scroll", isOn: $state.autoScrollHoldModeEnabled.animation())
                    .toggleStyle(.checkbox)
                    .disabled(state.autoScrollHoldModeEnabled && !state.autoScrollToggleModeEnabled)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("Auto-scroll trigger")
                        .frame(width: 120, alignment: .leading)
                    ButtonMappingButtonRecorder(
                        mapping: state.autoScrollTriggerBinding
                    )
                    .frame(width: 220)
                }

                if !state.autoScrollTriggerValid {
                    Text("Choose a mouse button trigger. Left click without modifier keys is not allowed.")
                        .foregroundColor(.red)
                        .controlSize(.small)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsToggleRow(
                title: NSLocalizedString("Reverse auto-scroll", comment: ""),
                subtitle: NSLocalizedString("Move the content in the same direction as the mouse.", comment: ""),
                isOn: $state.autoScrollReverse
            )
        }
    }

    private var modeDescription: LocalizedStringKey {
        let modes = Set(state.autoScrollModes)

        if state.autoScrollToggleModeEnabled,
           state.autoScrollToggleActivation == .longPress {
            if modes == [.toggle] {
                return "Long-press the trigger to enter autoscroll, move in any direction to scroll, then click again to exit."
            }

            return "Long-press and release to keep autoscroll active, or drag beyond the dead zone to scroll only until you let go."
        }

        if modes == [.toggle] {
            return "Click the trigger once to enter autoscroll, move in any direction to scroll, then click again to exit."
        }

        if modes == [.hold] {
            return "Hold the trigger while moving to scroll, then release it to stop."
        }

        return "Click and release to keep autoscroll active, or hold and drag to scroll only until you let go."
    }
}
