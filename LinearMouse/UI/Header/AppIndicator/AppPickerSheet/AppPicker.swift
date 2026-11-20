// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct AppPicker: View {
    @ObservedObject private var state = AppPickerState.shared

    let title: LocalizedStringKey
    let unavailable: Set<AppTarget>
    var knownTargets: [AppTarget] = []
    let choose: (AppTarget) -> Void

    @ViewBuilder
    var body: some View {
        if #available(macOS 11, *) {
            Menu { choices } label: { Text(title) }.controlSize(.small).fixedSize()
        } else {
            MenuButton(label: Text(title)) { choices }.controlSize(.small).fixedSize()
        }
    }

    @ViewBuilder
    private var choices: some View {
        let known = knownTargets.filter { !unavailable.contains($0) }
        if !known.isEmpty {
            Section(header: Text("Apps with custom settings")) {
                ForEach(known, id: \.self) { app in
                    Button(action: { choose(app) }) { Text(verbatim: app.displayName) }
                }
            }
        }
        let blocked = unavailable.union(known)
        let running = state.runningTargets.filter { !blocked.contains($0) }
        if !running.isEmpty {
            Section(header: Text("Running")) {
                ForEach(running, id: \.self) { app in
                    Button(action: { choose(app) }) { Text(verbatim: app.displayName) }
                }
            }
        }
        let alreadyListed = blocked.union(running)
        Section(header: Text("Installed")) {
            ForEach(state.installedApps.filter { !alreadyListed.contains(.bundle($0.bundleIdentifier)) }) { app in
                Button(action: { choose(.bundle(app.bundleIdentifier)) }) { Text(verbatim: app.bundleName) }
            }
        }
        Divider()
        Button("Other App…") { browse(executable: false) }
        Button("Other Executable…") { browse(executable: true) }
    }

    private func browse(executable: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if executable {
            panel.message = NSLocalizedString("Select an executable file", comment: "")
        } else if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.applicationBundle]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let target: AppTarget
        if executable {
            target = .executable(url.path)
        } else if let app = try? readInstalledApp(at: url) {
            target = .bundle(app.bundleIdentifier)
        } else {
            return
        }
        if !unavailable.contains(target) { choose(target) }
    }
}
