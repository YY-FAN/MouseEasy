// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

extension ScrollingSettings {
    struct SmoothedScrollingSection: View {
        @ObservedObject private var state = ScrollingSettingsState.shared

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                SettingsSlider(
                    title: NSLocalizedString("Scroll speed", comment: ""),
                    detail: NSLocalizedString("Adjust the distance travelled per wheel step.", comment: ""),
                    value: $state.smoothedSpeed,
                    range: Scheme.Scrolling.Smoothed.speedRange,
                    formatter: state.smoothedSpeedFormatter
                )
                SettingsSlider(
                    title: NSLocalizedString("Minimum step (pt)", comment: ""),
                    detail: NSLocalizedString("Set to 0 for the original step, or increase it to move farther with a light turn.", comment: ""),
                    value: $state.smoothedMinimumStep,
                    range: Scheme.Scrolling.Smoothed.minimumStepRange,
                    formatter: state.smoothedMinimumStepFormatter
                )
                SettingsSlider(
                    title: NSLocalizedString("Response", comment: ""),
                    detail: NSLocalizedString("Choose a gentle start or an immediate response.", comment: ""),
                    value: $state.smoothedResponse,
                    range: Scheme.Scrolling.Smoothed.responseRange,
                    formatter: state.smoothedResponseFormatter
                )

                SettingsControlRow(title: state.smoothedDurationEnabled ? NSLocalizedString("Fixed tail (s)", comment: "") : NSLocalizedString("Fixed tail", comment: "")) {
                    HStack(spacing: SettingsControlLayout.spacing) {
                        Toggle("Fixed tail", isOn: $state.smoothedDurationEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .fixedSize()
                        if state.smoothedDurationEnabled {
                            CompactSettingsSlider(title: NSLocalizedString("Tail duration", comment: ""), value: $state.smoothedDuration,
                                                  range: Scheme.Scrolling.Smoothed.durationRange)
                                .frame(height: 18)
                        }
                    }
                    .frame(width: state.smoothedDurationEnabled ? SettingsControlLayout.sliderWidth : nil,
                           alignment: .leading)
                    if state.smoothedDurationEnabled {
                        DeferredNumberField(
                            value: $state.smoothedDuration,
                            formatter: state.smoothedDurationFormatter,
                            range: Scheme.Scrolling.Smoothed.durationRange
                        )
                        .frame(width: SettingsControlLayout.numberWidth, height: 22)
                        .accessibilityLabel("Tail duration in seconds")
                    }
                }
                .help("Set how long scrolling continues after the wheel stops. Turn off to use inertia.")

                if !state.smoothedDurationEnabled {
                    SettingsSlider(
                        title: NSLocalizedString("Scroll inertia", comment: ""),
                        detail: NSLocalizedString("Higher values glide longer after the wheel stops.", comment: ""),
                        value: $state.smoothedInertia,
                        range: Scheme.Scrolling.Smoothed.inertiaRange,
                        formatter: state.smoothedInertiaFormatter
                    )
                }
            }
        }
    }

    struct SmoothedScrollingAdvancedControls: View {
        @ObservedObject private var state = ScrollingSettingsState.shared

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                SettingsSlider(
                    title: NSLocalizedString("Fast-scroll acceleration", comment: ""),
                    detail: NSLocalizedString("Increase the distance when turning the wheel quickly.", comment: ""),
                    value: $state.smoothedAcceleration,
                    range: Scheme.Scrolling.Smoothed.accelerationRange,
                    formatter: state.smoothedAccelerationFormatter
                )
                SettingsControlRow(title: NSLocalizedString("Edge bounce", comment: "")) {
                    Toggle("Edge bounce", isOn: $state.smoothedBouncing)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .fixedSize()
                }
                .help("Allow elastic scrolling at the edges of content.")
            }
        }
    }
}
