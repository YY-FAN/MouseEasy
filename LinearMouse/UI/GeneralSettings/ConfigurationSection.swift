// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import SwiftUI

struct ConfigurationSection: View {
    @ObservedObject var configurationState = ConfigurationState.shared
    var showsMaintenance = false

    var body: some View {
        HStack(spacing: 8) {
            if showsMaintenance {
                Button("Reload configuration") { configurationState.load() }
                    .buttonStyle(SettingsSecondaryButtonStyle())
                    .disabled(configurationState.loading)
                Button("Show in Finder…") { configurationState.revealInFinder() }
                    .buttonStyle(SettingsSecondaryButtonStyle())
            } else {
                Button(action: exportConfiguration) {
                    Label("Export configuration…", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
                Button(action: importConfiguration) {
                    Label("Import configuration…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(SettingsSecondaryButtonStyle())
            }
            Spacer(minLength: 0)
        }
    }

    private func importConfiguration() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["json"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        reportErrors { try configurationState.importConfiguration(from: source) }
    }

    private func exportConfiguration() {
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["json"]
        panel.nameFieldStringValue = "MouseEasy-settings.json"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        reportErrors { try configurationState.exportConfiguration(to: destination) }
    }

    private func reportErrors(_ operation: () throws -> Void) {
        do { try operation() } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}
