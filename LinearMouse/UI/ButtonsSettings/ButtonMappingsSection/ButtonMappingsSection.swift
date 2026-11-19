// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct ButtonMappingsSection: View {
    @ObservedObject private var state: ButtonsSettingsState = .shared

    @State private var activeSheet: ActiveSheet?
    @State private var mappingDraft: Scheme.Buttons.Mapping = .init()
    @State private var editingOriginalMapping: Scheme.Buttons.Mapping?

    var body: some View {
        SettingsCard(title: NSLocalizedString("Button bindings", comment: ""), symbol: "computermouse") {
            if state.mappings.isEmpty {
                Text("No button actions yet").foregroundColor(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach($state.mappings, id: \.self) { $mapping in
                        ButtonMappingListItem(
                            mapping: $mapping,
                            onEdit: beginEditing,
                            onDelete: removeMapping
                        )
                        if mapping != state.mappings.last {
                            Divider()
                        }
                    }
                }
                Divider()
            }

            HStack(spacing: 8) {
                Button(action: beginAdding) {
                    Label("Add button", systemImage: "plus")
                }
                .accessibilityIdentifier("addButtonMapping")
                if state.canApplyWindowSwitchingPreset {
                    Button("Use window switching preset", action: state.applyWindowSwitchingPreset)
                        .help("Button #3 cycles windows in this app. Button #4 switches apps.")
                }
            }
            .buttonStyle(SettingsSecondaryButtonStyle())
        }
        .sheet(item: $activeSheet) { sheet in
            ButtonMappingEditSheet(
                isPresented: sheetPresented,
                mapping: $mappingDraft,
                mode: sheet.mode
            ) { mapping in
                apply(mapping, from: sheet)
            }
        }
    }

    private var sheetPresented: Binding<Bool> {
        Binding(
            get: { activeSheet != nil },
            set: { isPresented in
                if !isPresented {
                    activeSheet = nil
                    editingOriginalMapping = nil
                }
            }
        )
    }

    private func removeMapping(_ mapping: Scheme.Buttons.Mapping) {
        state.mappings.removeAll { $0 == mapping }
    }

    private func beginAdding() {
        mappingDraft = .init()
        editingOriginalMapping = nil
        activeSheet = .create
    }

    private func beginEditing(_ mapping: Scheme.Buttons.Mapping) {
        mappingDraft = mapping
        editingOriginalMapping = mapping
        activeSheet = .edit
    }

    private func apply(_ mapping: Scheme.Buttons.Mapping, from sheet: ActiveSheet) {
        switch sheet {
        case .create:
            if let trigger = mapping.effectiveTrigger,
               let index = state.mappings.firstIndex(where: {
                   $0.isStructured && $0.effectiveTrigger?.isEquivalent(to: trigger) == true
               }) {
                var existing = state.mappings[index]
                existing.mergeOutcomes(from: mapping)
                state.mappings[index] = existing
            } else {
                state.appendMapping(mapping)
            }

        case .edit:
            guard let editingOriginalMapping,
                  let index = state.mappings.firstIndex(of: editingOriginalMapping) else {
                return
            }
            state.mappings[index] = mapping
        }
    }
}

private extension ButtonMappingsSection {
    enum ActiveSheet: String, Identifiable {
        case create
        case edit

        var id: String {
            rawValue
        }

        var mode: ButtonMappingEditSheet.Mode {
            switch self {
            case .create:
                return .create
            case .edit:
                return .edit
            }
        }
    }
}
