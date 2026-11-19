// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct DeviceIndicator: View {
    @ObservedObject private var state = DeviceIndicatorState.shared
    @ObservedObject private var deviceState = DeviceState.shared
    @State private var showDevicePickerSheet = false

    private var title: String { state.activeDeviceName ?? NSLocalizedString("Unknown", comment: "") }

    private var isSpecific: Bool {
        deviceState.currentDeviceMatcher != nil && deviceState.currentDeviceMatcher?.categoryOnlyValue != .mouse
    }

    var body: some View {
        Button {
            showDevicePickerSheet.toggle()
        } label: {
            Text(verbatim: title)
        }
        .controlSize(.small)
        .buttonStyle(SettingsScopeButtonStyle(isSpecific: isSpecific))
        .accessibilityHint(Text("Choose mouse or trackpad scope"))
        .help(title)
        .sheet(isPresented: $showDevicePickerSheet) {
            DevicePickerSheet(isPresented: $showDevicePickerSheet)
        }
    }
}
