// MIT License
// Copyright (c) 2021-2026 LinearMouse
// Local development build: independent release channel.

import SwiftUI

struct CheckForUpdatesView: View {
    var body: some View {
        Text(String(format: NSLocalizedString("Version %@", comment: ""), LinearMouse.appVersion))
            .foregroundColor(.secondary)
        Text("Local build. Install a newer version to update.")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}
