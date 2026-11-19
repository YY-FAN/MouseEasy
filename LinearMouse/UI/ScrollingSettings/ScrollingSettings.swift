// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct ScrollingSettings: View {
    @ObservedObject private var state = ScrollingSettingsState.shared

    var body: some View {
        DetailView {
            VStack(alignment: .leading, spacing: 12) {
                SettingsCard(title: NSLocalizedString("Direction & feel", comment: ""), symbol: "arrow.up.arrow.down") {
                    SettingsToggleRow(title: NSLocalizedString("Reverse wheel direction", comment: ""), isOn: $state.reverseVerticalScrolling, fillsRow: true)
                    Divider()
                    SettingsToggleRow(title: NSLocalizedString("Smooth scrolling", comment: ""), isOn: $state.verticalSmoothingEnabled, fillsRow: true)
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

                MirrorWheelCard()

                ModifierKeysSection()
            }
        }
        .onAppear { state.refreshHighResolutionWheelInfo() }
    }
}

private struct MirrorWheelCard: View {
    @ObservedObject var state = ConfigurationState.shared
    private var current: MirrorScrollSettings { state.configuration.mirrorScrolling ?? .init() }
    private func setting<T>(_ key: WritableKeyPath<MirrorScrollSettings, T?>,
                            _ effective: KeyPath<MirrorScrollSettings, T>) -> Binding<T> {
        Binding(get: { current[keyPath: effective] }, set: { value in
            var changed = current
            changed[keyPath: key] = value
            state.configuration.mirrorScrolling = changed
        })
    }

    var body: some View {
        SettingsCard(title: NSLocalizedString("iPhone Mirroring", comment: ""), subtitle: NSLocalizedString("All mice", comment: ""), symbol: "iphone") {
            SettingsToggleRow(title: NSLocalizedString("Use mirroring settings", comment: ""), subtitle: NSLocalizedString("Override scrolling only in iPhone Mirroring. Turn off to use normal scrolling.", comment: ""),
                              isOn: setting(\.enabled, \.isEnabled), fillsRow: true)
            if current.isEnabled {
                Divider()
                SettingsDisclosure(title: NSLocalizedString("Mirroring scroll settings", comment: "")) {
                    SettingsControlRow(title: NSLocalizedString("Wheel behavior", comment: "")) {
                        Picker("Wheel behavior", selection: setting(\.wheelMode, \.resolvedWheelMode)) {
                            ForEach(MirrorScrollSettings.WheelMode.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 216, alignment: .leading)
                    }
                    .help("Reverse only keeps the original wheel events and reversal. System wheel uses the macOS scroll direction.")

                    if current.resolvedWheelMode == .smooth {
                        SettingsControlRow(title: NSLocalizedString("Scroll event rate", comment: "")) {
                            Picker("Scroll event rate", selection: setting(\.frequency, \.hz)) {
                                Text("30 Hz").tag(30)
                                Text("60 Hz").tag(60)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 135, alignment: .leading)
                        }
                        SettingsSlider(title: NSLocalizedString("Mirroring speed", comment: ""), value: setting(\.speed, \.scrollSpeed),
                                       range: 0.1 ... 4, formatter: ScrollingSettingsState.shared.smoothedSpeedFormatter)
                        SettingsSlider(title: NSLocalizedString("Mirroring response", comment: ""), value: setting(\.response, \.responsiveness),
                                       range: 0 ... 2, formatter: ScrollingSettingsState.shared.smoothedResponseFormatter)
                        SettingsSlider(title: NSLocalizedString("Tail duration (s)", comment: ""), value: setting(\.duration, \.tail),
                                       range: 0 ... 0.8, formatter: ScrollingSettingsState.shared.smoothedDurationFormatter)
                    }
                }
            }
        }
    }
}
