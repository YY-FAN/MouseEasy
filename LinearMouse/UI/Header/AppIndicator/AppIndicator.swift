// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct AppIndicator: View {
    @State private var showAppPickerSheet = false

    @ObservedObject private var schemeState: SchemeState = .shared

    private var title: String { schemeState.currentAppName ?? NSLocalizedString("All Apps", comment: "") }

    var body: some View {
        Button {
            showAppPickerSheet.toggle()
        } label: {
            Text(verbatim: title)
        }
        .controlSize(.small)
        .buttonStyle(SettingsScopeButtonStyle(isSpecific: schemeState.currentApp != nil))
        .accessibilityHint(Text("Choose application scope"))
        .help(title)
        .sheet(isPresented: $showAppPickerSheet) {
            AppPickerSheet(isPresented: $showAppPickerSheet)
        }
    }
}
