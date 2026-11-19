// SPDX-License-Identifier: MIT
// Copyright (c) 2026 MouseWorkbench contributors

import AppKit
import SwiftUI

struct ButtonMappingActionOpenTarget: View {
    @Binding var action: Scheme.Buttons.Mapping.Action
    private typealias Target = Scheme.Buttons.Mapping.Action.OpenTarget

    private var target: Binding<Target> {
        Binding(get: {
            if case let .arg1(.openTarget(value)) = action { return value }
            return .init()
        }, set: { action = .arg1(.openTarget($0)) })
    }

    var body: some View {
        HStack {
            TextField("File path", text: target.path)
            Button("Choose…", action: chooseFile)
        }
        Picker("Open with", selection: target.mode) {
            Text("Open with default app").tag(Target.Mode.open)
            Text("Run script or executable").tag(Target.Mode.execute)
        }
        .modifier(PickerViewModifier())
        if target.wrappedValue.mode == .execute || target.wrappedValue.fileURL.pathExtension.lowercased() == "app" {
            Text("Arguments, one per line")
            if #available(macOS 11, *) {
                TextEditor(text: argumentsBinding)
                    .frame(height: 55)
            } else {
                TextField("Arguments", text: argumentsBinding)
            }
        }
    }

    private var argumentsBinding: Binding<String> {
        Binding(get: { target.wrappedValue.arguments.joined(separator: "\n") }, set: {
            target.wrappedValue.arguments = $0.isEmpty ? [] : $0.components(separatedBy: "\n")
        })
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var value = target.wrappedValue
        value.path = url.path
        value.mode = ["sh", "command", "zsh", "scpt", "applescript"].contains(url.pathExtension.lowercased())
            ? .execute : .open
        target.wrappedValue = value
    }
}
