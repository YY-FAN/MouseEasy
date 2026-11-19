// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct DisplayIndicator: View {
    @State private var showDisplayPickerSheet = false

    @ObservedObject private var schemeState: SchemeState = .shared

    private var title: String { schemeState.currentDisplay ?? NSLocalizedString("All Displays", comment: "") }

    var body: some View {
        Button {
            showDisplayPickerSheet.toggle()
        } label: {
            Text(verbatim: title)
        }
        .controlSize(.small)
        .buttonStyle(SettingsScopeButtonStyle(isSpecific: schemeState.currentDisplay != nil))
        .accessibilityHint(Text("Choose display scope"))
        .help(title)
        .sheet(isPresented: $showDisplayPickerSheet) {
            DisplayPickerSheet(isPresented: $showDisplayPickerSheet)
        }
    }
}
