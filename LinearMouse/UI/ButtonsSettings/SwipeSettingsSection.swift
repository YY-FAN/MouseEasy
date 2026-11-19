// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct SwipeSettingsSection: View {
    @ObservedObject private var state = ButtonsSettingsState.shared

    private static let thresholdFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Swipe distance")
                    .frame(width: 120, alignment: .leading)
                Slider(
                    value: $state.swipeThreshold,
                    in: Scheme.Buttons.Swipe.thresholdRange,
                    step: 5
                ) {
                    Text("Distance to trigger a swipe")
                }
                .labelsHidden()
                .frame(minWidth: 100, maxWidth: 220)
                DeferredNumberField(
                    value: $state.swipeThreshold,
                    formatter: Self.thresholdFormatter,
                    range: Scheme.Buttons.Swipe.thresholdRange
                )
                .frame(width: 64)
                .accessibility(label: Text("Distance to trigger a swipe"))
                Text("pixels")
                    .foregroundColor(.secondary)
            }
            .help("Hold the assigned mouse button and move this far to trigger a swipe.")

            HStack(spacing: 12) {
                SettingsToggleRow(
                    title: NSLocalizedString("Keep pointer still during swipes", comment: ""),
                    isOn: $state.lockPointerDuringSwipe
                )
                .fixedSize(horizontal: true, vertical: false)
                Button("Restore defaults") {
                    state.resetSwipeSettings()
                }
                .buttonStyle(SettingsSecondaryButtonStyle())
                .disabled(!state.hasSwipeSettingsOverride)
            }
        }
    }
}
