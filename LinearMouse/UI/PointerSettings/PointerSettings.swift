// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI
import Defaults

struct PointerSettings: View {
    @ObservedObject var state = PointerSettingsState.shared

    var body: some View {
        DetailView {
            VStack(alignment: .leading, spacing: 12) {
                speedControls
                SettingsDisclosure(title: NSLocalizedString("Pointer behavior & hardware", comment: "")) {
                    additionalControls
                }
                .padding(.horizontal, 4)
            }
        }
        .onAppear { state.refreshPointerHardwareDPIInfo() }
    }

    private var speedControls: some View {
        SettingsCard(title: NSLocalizedString("Speed & acceleration", comment: ""), symbol: "speedometer") {
            if !state.pointerDisableAcceleration {
                SettingsSlider(title: NSLocalizedString("Pointer speed", comment: ""), value: $state.pointerSpeed,
                               range: 0 ... 1, formatter: state.pointerSpeedFormatter)
                SettingsSlider(title: NSLocalizedString("Pointer acceleration", comment: ""), value: $state.pointerAcceleration,
                               range: 0 ... 40, formatter: state.pointerAccelerationFormatter)
                if state.showsPointerSpeedLimitationNotice {
                    Text("macOS may limit speed adjustments for this device.")
                        .foregroundColor(.secondary)
                }
            } else if #available(macOS 14, *) {
                SettingsSlider(title: NSLocalizedString("Tracking speed", comment: ""), value: $state.pointerAcceleration,
                               range: 0 ... 40, formatter: state.pointerAccelerationFormatter)
            }
            Divider()
            SettingsToggleRow(title: NSLocalizedString("Disable pointer acceleration", comment: ""), isOn: $state.pointerDisableAcceleration, fillsRow: true)
            Button("Restore system defaults", action: state.revertPointerSpeed)
                .buttonStyle(SettingsSecondaryButtonStyle())
        }
    }

    private var additionalControls: some View {
        Group {
            if state.showsPointerHardwareDPIControl {
                SettingsCard(title: NSLocalizedString("Mouse hardware DPI", comment: ""), symbol: "scope") {
                    pointerHardwareDPIControl
                }
            }

            SettingsCard(title: NSLocalizedString("Pointer behavior", comment: ""), symbol: "cursorarrow") {
                PointerLocationControls()
                Divider()
                SettingsToggleRow(
                    title: NSLocalizedString("Focus window on hover", comment: ""),
                    subtitle: NSLocalizedString("Hold Control to pause.", comment: ""),
                    isOn: $state.focusFollowsMouse
                )
                Divider()
                pointerRedirectsToScrollControl
            }

            HStack(spacing: 12) {
                Button("About pointer settings") {
                    NSWorkspace.shared.open(URL(string: "https://go.linearmouse.app/disable-pointer-acceleration-and-speed")!)
                }
                if state.showsPointerSpeedLimitationNotice {
                    Button("About device speed limits") {
                        NSWorkspace.shared.open(URL(string: "https://go.linearmouse.app/pointer-speed-limitations")!)
                    }
                }
            }
            .buttonStyle(SettingsSecondaryButtonStyle())
        }
    }

    private var pointerRedirectsToScrollControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Scroll with pointer movement")
                    .frame(width: 120, alignment: .leading)
                Picker("Pointer movement mode", selection: $state.pointerRedirectsToScrollMode.animation()) {
                    Text("Off").tag(PointerSettingsState.RedirectsToScrollMode.off)
                    Text("While holding a button").tag(PointerSettingsState.RedirectsToScrollMode.whileHoldingTrigger)
                    Text("Always").tag(PointerSettingsState.RedirectsToScrollMode.always)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 170)
            }
            .help("Turn mouse movement into scrolling using the current speed, direction, and smoothing.")

            if state.pointerRedirectsToScrollMode == .whileHoldingTrigger {
                pointerRedirectsToScrollTriggerControl
            }

            if state.redirectsToScrollAlwaysSecondsUntilRevert != nil {
                pointerRedirectsToScrollAlwaysRevertNotice
            }
        }
        .alert(isPresented: $state.redirectsToScrollAlwaysConfirmationPresented) {
            Alert(
                title: Text("Always convert pointer movement to scroll events?"),
                message: Text(
                    "This device will stop moving the pointer. To undo it you will need the keyboard or another mouse or trackpad, so it is reverted automatically unless you confirm."
                ),
                primaryButton: .default(Text("Turn On")) {
                    state.confirmRedirectsToScrollAlways()
                },
                secondaryButton: .cancel {
                    state.cancelRedirectsToScrollAlways()
                }
            )
        }
    }

    /// Mirrors how macOS confirms a display change: the setting is already
    /// live, and goes back by itself unless it is kept. Where the API is
    /// available, "Keep" is the default button and "Revert" the cancel one, so
    /// both are reachable from the keyboard while the pointer is unusable.
    private var pointerRedirectsToScrollAlwaysRevertNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let seconds = state.redirectsToScrollAlwaysSecondsUntilRevert {
                Text("Reverting in \(seconds) second(s) unless you keep this setting.")
                    .settingsDescriptionStyle()
            }

            HStack {
                if #available(macOS 11.0, *) {
                    Button("Keep") {
                        state.keepRedirectsToScrollAlways()
                    }
                    .buttonStyle(SettingsPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)

                    Button("Revert") {
                        state.revertRedirectsToScrollAlways()
                    }
                    .buttonStyle(SettingsSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                } else {
                    Button("Keep") {
                        state.keepRedirectsToScrollAlways()
                    }
                    .buttonStyle(SettingsPrimaryButtonStyle())

                    Button("Revert") {
                        state.revertRedirectsToScrollAlways()
                    }
                    .buttonStyle(SettingsSecondaryButtonStyle())
                }
            }
        }
    }

    private var pointerRedirectsToScrollTriggerControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("Trigger button")
                    .frame(width: 120, alignment: .leading)
                ButtonMappingButtonRecorder(mapping: state.pointerRedirectsToScrollTriggerBinding)
                if state.pointerRedirectsToScrollTrigger != nil {
                    Button("Clear") {
                        state.pointerRedirectsToScrollTrigger = nil
                    }
                    .buttonStyle(SettingsSecondaryButtonStyle())
                }
                Spacer(minLength: 0)
            }
            .help(state.pointerRedirectsToScrollTrigger == nil
                ? NSLocalizedString("Record a mouse button first. The pointer moves normally until a button is set.", comment: "")
                : NSLocalizedString("Hold this button to scroll by moving the mouse.", comment: ""))
            if !state.pointerRedirectsToScrollTriggerValid {
                Text("Choose a mouse button trigger. Left click without modifier keys is not allowed.")
                    .foregroundColor(.red)
                    .controlSize(.small)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var pointerHardwareDPIControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let info = state.pointerHardwareDPIInfo,
               info.currentDPI != nil,
               let range = info.dpiRange {
                pointerHardwareDPISetter(range: range)

                if let message = state.pointerHardwareDPIStatusMessage {
                    Text(message)
                        .foregroundColor(.secondary)
                }
            } else if state.pointerHardwareDPIBusy {
                Text(state.pointerHardwareDPIApplying ? "Applying..." : "Refreshing...")
                    .foregroundColor(.secondary)
            } else {
                Text(state.pointerHardwareDPIStatusMessage ?? "Reading hardware DPI from the selected device.")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func pointerHardwareDPISetter(range: ClosedRange<Int>) -> some View {
        HStack(spacing: 10) {
            Text("Hardware DPI")
                .frame(width: 120, alignment: .leading)
            if range.lowerBound < range.upperBound {
                Slider(
                    value: Binding(
                        get: { Double(state.pointerHardwareDPITargetDPI) },
                        set: { state.updatePointerHardwareDPITargetDPI(Int($0.rounded())) }
                    ),
                    in: Double(range.lowerBound) ... Double(range.upperBound)
                )
                .accessibility(label: Text("Hardware DPI"))
            } else {
                Spacer(minLength: 0)
            }
            DeferredNumberField(
                value: Binding(
                    get: { Double(state.pointerHardwareDPITargetDPI) },
                    set: { state.commitPointerHardwareDPITargetDPI(Int($0.rounded())) }
                ),
                formatter: state.pointerDPIFormatter,
                range: Double(range.lowerBound) ... Double(range.upperBound)
            )
            .frame(width: 76)
            .accessibility(label: Text("Hardware DPI value"))
        }
        .help(String(format: NSLocalizedString("Range: %lld–%lld DPI", comment: ""), Int64(range.lowerBound), Int64(range.upperBound)))
    }
}


private struct PointerLocationControls: View {
    @Default(.showPointerLocation) private var isEnabled
    @Default(.pointerLocationTriggerModifier) private var triggerModifier

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsToggleRow(
                title: NSLocalizedString("Locate pointer", comment: ""),
                subtitle: NSLocalizedString("Press a modifier key twice to highlight the pointer.", comment: ""),
                isOn: $isEnabled.animation()
            )
            if isEnabled {
                HStack(spacing: 10) {
                    Text("Locator key")
                        .frame(width: 120, alignment: .leading)
                    Picker("Locator key", selection: $triggerModifier.animation()) {
                        ForEach(PointerLocationTriggerModifier.allCases) { modifier in
                            Text(modifier.label).tag(modifier)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 170)
                }
            }
        }
    }
}
