// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct AppPickerSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject private var schemeState = SchemeState.shared
    @ObservedObject private var config = ConfigurationState.shared
    @State private var draft = AppPickerDraft()
    @State private var showDeleteAlert = false
    @State private var removalTarget: AppTarget?

    private var exceptions: Set<AppTarget> {
        draft.exceptions(in: config.configuration)
    }

    private var configured: [AppTarget] {
        draft.configuredApps(in: config.configuration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SettingsCard {
                Button { draft.selected = nil } label: {
                    HStack {
                        Text("All Apps").font(.body.weight(.semibold))
                        Spacer()
                        selectionMark(draft.selected == nil)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                hint("Set defaults for apps. An app’s own settings take priority.")
            }

            SettingsCard(title: NSLocalizedString("Apps with custom settings", comment: ""), symbol: "slider.horizontal.3",
                         headerAccessory: AnyView(AppPicker(title: "Add app…", unavailable: exceptions) { app in
                             draft.addApp(app)
                         })) {
                hint("Choose an app to edit its settings for the current device and display.")
                if configured.isEmpty {
                    hint("No apps have custom settings yet.")
                } else {
                    rows(configured) { app in
                        HStack(spacing: 10) {
                            Button { draft.selected = app } label: {
                                HStack {
                                    Text(verbatim: app.displayName).lineLimit(1)
                                    Spacer(minLength: 8)
                                    selectionMark(draft.selected == app)
                                }.contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(app.identifier)
                            .frame(maxWidth: .infinity)

                            if draft.addedApps.contains(app) || schemeState.hasMatchingSchemes(forApp: app, forDisplay: schemeState.currentDisplay) {
                                Button("Remove app settings…") {
                                    removalTarget = app
                                    showDeleteAlert = true
                                }
                                .buttonStyle(SettingsDestructiveButtonStyle())
                                .fixedSize()
                            }
                        }
                    }
                }
            }

            SettingsCard(title: NSLocalizedString("Exceptions", comment: ""), symbol: "minus.circle",
                         headerAccessory: AnyView(AppPicker(title: "Add exception…", unavailable: exceptions, knownTargets: configured) { app in
                             draft.addException(app)
                         })) {
                hint("MouseEasy pauses all input settings in these apps. Removing an exception restores the app’s previous settings.")
                if exceptions.isEmpty {
                    hint("No exceptions.")
                } else {
                    rows(exceptions.sorted(by: AppTarget.alphabetically)) { app in
                        HStack {
                            Text(verbatim: app.displayName).help(app.identifier)
                            Spacer()
                            Button("Remove exception") {
                                draft.removeException(app)
                            }.controlSize(.small)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }.sheetSecondaryActionStyle().asCancelAction()
                Button("OK", action: apply).sheetPrimaryActionStyle().asDefaultAction()
            }
        }
        .padding(14)
        .frame(width: 420)
        .onExitCommand { isPresented = false }
        .onAppear {
            draft.selected = schemeState.currentApp.flatMap { exceptions.contains($0) ? nil : $0 }
            AppPickerState.shared.refreshInstalledApps()
        }
        .alert(isPresented: $showDeleteAlert) {
            Alert(title: Text("Remove app settings?"),
                  message: Text(verbatim: String(format: NSLocalizedString("Remove settings for %@ for the current device and display?", comment: ""),
                                                removalTarget?.displayName ?? "")),
                  primaryButton: .destructive(Text("Remove")) {
                      if let app = removalTarget { draft.removeApp(app) }
                      removalTarget = nil
                  }, secondaryButton: .cancel { removalTarget = nil })
        }
    }

    private func hint(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.subheadline).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func selectionMark(_ isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .foregroundColor(isSelected ? .accentColor : .secondary)
            .accessibilityLabel(Text(isSelected ? "Selected" : "Not selected"))
    }

    @ViewBuilder
    private func rows<Row: View>(_ apps: [AppTarget], @ViewBuilder row: @escaping (AppTarget) -> Row) -> some View {
        let list = VStack(alignment: .leading, spacing: 3) {
            ForEach(apps, id: \.self) { app in row(app).frame(minHeight: 22) }
        }
        if apps.count > 4 {
            ScrollView { list }.frame(height: 100)
        } else {
            list
        }
    }

    private func apply() {
        draft.apply(to: schemeState, configurationState: config)
        isPresented = false
    }
}

// Keep additions independent of the selected editing target until the user confirms.
struct AppPickerDraft {
    var selected: AppTarget?
    private(set) var addedApps = Set<AppTarget>()
    private var addedExceptions = Set<AppTarget>()
    private var removedExceptions = Set<AppTarget>()
    private var pendingDeletes = Set<AppTarget>()

    func exceptions(in configuration: Configuration) -> Set<AppTarget> {
        Set(configuration.excludedApps ?? []).subtracting(removedExceptions).union(addedExceptions)
    }

    func configuredApps(in configuration: Configuration) -> [AppTarget] {
        var targets = Set(configuration.schemes.flatMap { scheme in
            (scheme.if ?? []).compactMap { condition -> AppTarget? in
                if let app = condition.app { return .bundle(app) }
                if let path = condition.processPath { return .executable(path) }
                return condition.processName.map(AppTarget.executableName)
            }
        })
        targets.formUnion(addedApps)
        if let selected { targets.insert(selected) }
        return targets.subtracting(pendingDeletes).subtracting(exceptions(in: configuration))
            .sorted(by: AppTarget.alphabetically)
    }

    mutating func addApp(_ app: AppTarget) {
        pendingDeletes.remove(app)
        addedApps.insert(app)
        selected = app
    }

    mutating func removeApp(_ app: AppTarget) {
        addedApps.remove(app)
        pendingDeletes.insert(app)
        if selected == app { selected = nil }
    }

    mutating func addException(_ app: AppTarget) {
        removedExceptions.remove(app)
        pendingDeletes.remove(app)
        addedExceptions.insert(app)
        if selected == app { selected = nil }
    }

    mutating func removeException(_ app: AppTarget) {
        addedExceptions.remove(app)
        removedExceptions.insert(app)
    }

    func apply(to schemeState: SchemeState, configurationState: ConfigurationState) {
        let updated = exceptions(in: configurationState.configuration)
        if updated != Set(configurationState.configuration.excludedApps ?? []) {
            configurationState.configuration.excludedApps = updated.isEmpty ? nil : updated.sorted(by: AppTarget.alphabetically)
        }
        for app in pendingDeletes.subtracting(updated) {
            schemeState.deleteMatchingSchemes(forApp: app, forDisplay: schemeState.currentDisplay)
        }
        var appsToSave = addedApps
        if let selected { appsToSave.insert(selected) }
        schemeState.ensureAppSchemes(
            for: appsToSave.subtracting(updated).subtracting(pendingDeletes).sorted(by: AppTarget.alphabetically),
            forDisplay: schemeState.currentDisplay
        )
        schemeState.currentApp = selected.flatMap { updated.contains($0) ? nil : $0 }
    }
}
