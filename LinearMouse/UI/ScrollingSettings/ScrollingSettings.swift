// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct ScrollingSettings: View {
    @ObservedObject private var state = ScrollingSettingsState.shared
    @ObservedObject private var schemeState = SchemeState.shared

    var body: some View {
        DetailView {
            VStack(alignment: .leading, spacing: 12) {
                SettingsCard(title: NSLocalizedString("Direction & feel", comment: ""), symbol: "arrow.up.arrow.down") {
                    SettingsToggleRow(title: NSLocalizedString("Reverse vertical scrolling", comment: ""), isOn: $state.reverseVerticalScrolling, fillsRow: true)
                    Divider()
                    SettingsToggleRow(title: NSLocalizedString("Smooth scrolling", comment: ""), isOn: $state.verticalSmoothingEnabled, fillsRow: true)
                    Divider()
                    horizontalScrollShortcut
                    Divider()
                    SettingsDisclosure(title: NSLocalizedString("Scroll feel & horizontal settings", comment: "")) {
                        Header()
                        Divider()
                        ScrollingModeSection()
                        if state.scrollingMode == .smoothed {
                            Divider()
                            SmoothedScrollingAdvancedControls()
                        }
                        if state.showsHighResolutionWheelControl {
                            Divider()
                            LogitechHighResolutionWheelSection()
                        }
                    }
                }

                if schemeState.showsMirrorScrollSettings {
                    MirrorWheelCard()
                }

                ModifierKeysSection()
            }
        }
        .onAppear { state.refreshHighResolutionWheelInfo() }
    }

    private var horizontalScrollShortcut: some View {
        let selection = state.modifierActions(for: .vertical).axisSwitchKeys
        let keys = selection.wrappedValue
        return HStack(spacing: 10) {
            Text("Hold a modifier to scroll horizontally").font(.body.weight(.medium))
            Spacer(minLength: 12)
            Picker("Hold a modifier to scroll horizontally", selection: selection) {
                Text("Unassigned").tag([WheelModifierKey]())
                ForEach(WheelModifierKey.all, id: \.self) { key in
                    Text(verbatim: key.label).tag([key])
                }
                if keys.count > 1 {
                    // A detailed setup can bind more than one key independently.
                    Text(verbatim: keys.map(\.label).joined(separator: " / ")).tag(keys)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
        }
        .frame(minHeight: 24)
    }
}

private struct MirrorWheelCard: View {
    @ObservedObject var state = ConfigurationState.shared
    private var current: MirrorScrollSettings { state.configuration.mirrorScrolling ?? .init() }
    private func setting<T>(_ key: WritableKeyPath<MirrorScrollSettings, T?>,
                            _ effective: KeyPath<MirrorScrollSettings, T>) -> Binding<T> {
        Binding(get: { current[keyPath: effective] }, set: { value in
            var changed = current
            if !changed.isEnabled {
                changed.systemReverseVertical = false
                changed.systemWheelMultiplier = 1
                changed.enabled = true
            }
            changed[keyPath: key] = value
            state.configuration.mirrorScrolling = changed
        })
    }

    var body: some View {
        SettingsCard(title: NSLocalizedString("iPhone Mirroring", comment: ""), subtitle: NSLocalizedString("All mice", comment: ""), symbol: "iphone") {
            SettingsToggleRow(title: NSLocalizedString("Reverse vertical scrolling", comment: ""),
                              isOn: setting(\.systemReverseVertical, \.reversesSystemWheel))
            Divider()
            SettingsControlRow(title: NSLocalizedString("Scroll speed", comment: "")) {
                let speed = setting(\.systemWheelMultiplier, \.wheelMultiplier)
                if MirrorScrollSettings.wheelMultipliers.contains(speed.wrappedValue) {
                    Picker("Scroll speed", selection: speed) {
                        ForEach(MirrorScrollSettings.wheelMultipliers, id: \.self) { multiplier in
                            Text(verbatim: String(format: "%g×", multiplier)).tag(multiplier)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                } else {
                    // A saved fractional speed remains visible until a new preset is chosen.
                    Menu {
                        ForEach(MirrorScrollSettings.wheelMultipliers, id: \.self) { multiplier in
                            Button { speed.wrappedValue = multiplier } label: {
                                Text(verbatim: String(format: "%g×", multiplier))
                            }
                        }
                    } label: {
                        Text(verbatim: String(format: "%g×", speed.wrappedValue))
                    }
                    .fixedSize()
                }
            }
        }
    }
}
