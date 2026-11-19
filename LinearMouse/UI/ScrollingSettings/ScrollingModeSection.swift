// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

extension ScrollingSettings {
    struct ScrollingModeSection: View {
        @ObservedObject private var state = ScrollingSettingsState.shared

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                SettingsControlRow(title: NSLocalizedString("Scroll mode", comment: "")) {
                    Picker("Scroll mode", selection: $state.scrollingMode) {
                        Text("Smooth scrolling").tag(ScrollingSettingsState.ScrollingMode.smoothed)
                        Text("System acceleration").tag(ScrollingSettingsState.ScrollingMode.accelerated)
                        Text("By lines").tag(ScrollingSettingsState.ScrollingMode.byLines)
                        Text("By pixels").tag(ScrollingSettingsState.ScrollingMode.byPixels)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: pairedControlWidth, alignment: .leading)

                    if state.scrollingMode == .smoothed {
                        HStack(spacing: 8) {
                            Text("Feel preset").fixedSize()
                            Picker("Feel preset", selection: $state.smoothedPreset) {
                                ForEach(Scheme.Scrolling.Smoothed.Preset.allCases) { preset in
                                    Text(preset.presentation.title).tag(preset)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: 134, alignment: .leading)
                            .help(Text(state.smoothedPreset.presentation.subtitle))
                        }
                    }
                }

                switch state.scrollingMode {
                case .smoothed:
                    SmoothedScrollingSection()
                case .accelerated:
                    SettingsSlider(
                        title: NSLocalizedString("Scroll speed", comment: ""),
                        detail: NSLocalizedString("Increase the distance per scroll. Set to 0 for system speed.", comment: ""),
                        value: $state.scrollingSpeed,
                        range: 0 ... 128,
                        formatter: state.scrollingSpeedFormatter
                    )
                    SettingsSlider(
                        title: NSLocalizedString("Scroll acceleration", comment: ""),
                        detail: NSLocalizedString("Higher values accelerate faster wheel movements.", comment: ""),
                        value: $state.scrollingAcceleration,
                        range: 0 ... 10,
                        formatter: state.scrollingAccelerationFormatter
                    )
                    if state.scrollingDisabled {
                        Text("These settings stop scrolling.")
                            .font(.callout)
                            .foregroundColor(.orange)
                    }
                case .byLines:
                    SettingsControlRow(title: NSLocalizedString("Lines per scroll", comment: "")) {
                        Slider(value: $state.scrollingDistanceInLines, in: 0 ... 10, step: 1)
                            .controlSize(.mini)
                            .frame(minWidth: 120, maxWidth: SettingsControlLayout.sliderWidth)
                            .accessibilityLabel("Lines per scroll")
                        DeferredNumberField(
                            value: $state.scrollingDistanceInLines,
                            formatter: integerFormatter,
                            range: 0 ... 10
                        )
                        .frame(width: SettingsControlLayout.numberWidth, height: 22)
                        .accessibilityLabel("Lines per scroll value")
                    }
                case .byPixels:
                    SettingsSlider(
                        title: NSLocalizedString("Distance per scroll", comment: ""),
                        detail: NSLocalizedString("Move a fixed number of pixels without system acceleration.", comment: ""),
                        value: $state.scrollingDistanceInPixels,
                        range: 0 ... 128,
                        formatter: state.scrollingSpeedFormatter
                    )
                }

                actions
            }
        }

        private var actions: some View {
            HStack(spacing: 8) {
                switch state.scrollingMode {
                case .smoothed:
                    Button("Reset scroll feel") {
                        state.scrollingMode = .smoothed
                        state.restoreDefaultSmoothedPreset()
                    }
                    if state.direction == .horizontal {
                        Button("Use vertical settings") {
                            state.scheme.scrolling.smoothed.horizontal = state.mergedScheme.scrolling.smoothed.vertical
                        }
                    }
                case .accelerated:
                    Button("Restore system scrolling") {
                        state.scrollingMode = .accelerated
                        state.scrollingAcceleration = 1
                        state.scrollingSpeed = 0
                    }
                    if state.direction == .horizontal {
                        Button("Use vertical settings") {
                            state.scheme.scrolling.distance.horizontal = state.mergedScheme.scrolling.distance.vertical
                            state.scheme.scrolling.acceleration.horizontal = state.mergedScheme.scrolling.acceleration.vertical
                            state.scheme.scrolling.speed.horizontal = state.mergedScheme.scrolling.speed.vertical
                        }
                    }
                case .byLines, .byPixels:
                    EmptyView()
                }
                if state.showsContinuousScrollShiftTip {
                    Button("Enable Shift for horizontal scrolling") {
                        state.setShiftModifierToAlterOrientation()
                    }
                    .help("Hold Shift while scrolling to switch axis.")
                }
            }
            .buttonStyle(SettingsSecondaryButtonStyle())
        }

        private var integerFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.minimum = 0
            formatter.maximum = 10
            formatter.maximumFractionDigits = 0
            return formatter
        }
    }
}
