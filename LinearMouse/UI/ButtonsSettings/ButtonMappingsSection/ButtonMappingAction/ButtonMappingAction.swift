// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct ButtonMappingAction: View {
    @Binding var action: Scheme.Buttons.Mapping.Action
    var label: LocalizedStringKey = "Action"
    @State private var showingCustom = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(action.presentationTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let shortcut = action.presentationShortcut {
                    Text(shortcut)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.accentColor)
                }
                Spacer(minLength: 12)
                operationMenu
            }
            DisclosureGroup(isExpanded: $showingCustom) {
                VStack(alignment: .leading, spacing: 8) {
                    ButtonMappingActionPicker(actionType: $action.kind, label: "Action type")
                    customEditor
                }
                .padding(.top, 8)
                .settingsDetailAppearance()
            } label: {
                Text("Custom shortcuts, scripts & other actions")
                    .font(SettingsDetailAppearance.font)
                    .foregroundColor(SettingsTheme.detailText)
            }
        }
        .padding(10)
        .background(SettingsTheme.panel)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
        .help(selectedContext.map { String(format: NSLocalizedString("Applies to %@", comment: ""), $0) } ?? NSLocalizedString("Choose an action to perform", comment: ""))
        .onAppear { showingCustom = needsCustomEditor }
    }

    private var operationMenu: some View {
        Menu {
            CommonMappingChoices(select: { action = $0; showingCustom = false })
            Divider()
            Button("Open an app or file…") {
                action = .arg1(.openTarget(.init()))
                showingCustom = true
            }
            Button("Record another shortcut…") {
                action = .arg1(.keyPress([]))
                showingCustom = true
            }
        } label: {
            Text("Choose action")
        }
        .menuStyle(.borderedButton)
        .fixedSize()
        .accessibilityLabel("Choose action")
    }

    private var needsCustomEditor: Bool {
        switch action {
        case let .arg1(.keyPress(keys)): return CommonActionCatalog.entry(for: keys) == nil
        case .arg1: return true
        case .arg0: return false
        }
    }

    private var selectedContext: String? {
        guard case let .arg1(.keyPress(keys)) = action else { return nil }
        return CommonActionCatalog.entry(for: keys)?.context
    }

    @ViewBuilder
    private var customEditor: some View {
        switch action {
        case .arg0:
            EmptyView()
        case .arg1(.run):
            ButtonMappingActionRun(action: $action)
        case .arg1(.openTarget):
            ButtonMappingActionOpenTarget(action: $action)
        case .arg1(.mouseWheelScrollUp),
             .arg1(.mouseWheelScrollDown),
             .arg1(.mouseWheelScrollLeft),
             .arg1(.mouseWheelScrollRight):
            ButtonMappingActionScroll(action: $action)
        case .arg1(.keyPress):
            KeyboardShortcutRecorder(keys: $action.keyPressKeys)
        }
    }
}

struct CommonMappingChoices: View {
    typealias Action = Scheme.Buttons.Mapping.Action
    var onlyRecommended = false
    var current: Action?
    var allows: (Action) -> Bool = { _ in true }
    let select: (Action) -> Void

    var body: some View {
        Section(header: Text("Common actions")) {
            ForEach(CommonActionCatalog.recommended) { entry in choice(entry) }
        }
        if !onlyRecommended {
            ForEach(CommonActionCatalog.groups) { group in
                Section(header: Text(group.title)) {
                    ForEach(group.entries) { entry in choice(entry) }
                }
            }
        }
        Divider()
        Button("Use default behavior") { select(.arg0(.auto)) }.disabled(!allows(.arg0(.auto)))
        Button("Do nothing") { select(.arg0(.none)) }.disabled(!allows(.arg0(.none)))
    }

    private func choice(_ entry: CommonActionCatalog.Entry) -> some View {
        Button {
            select(entry.mappingAction)
        } label: {
            if current == entry.mappingAction {
                Label(entry.label, systemImage: "checkmark")
            } else {
                Text(entry.label)
            }
        }
        .disabled(!allows(entry.mappingAction))
    }
}
