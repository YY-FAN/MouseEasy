// MIT License
// Keyboard-triggered actions for the independent local application.

import AppKit
import SwiftUI

struct KeyboardActionBindingsSection: View {
    @ObservedObject private var state = ButtonsSettingsState.shared
    @State private var draft = Scheme.Buttons.KeyboardMapping()
    @State private var showingEditor = false

    private var mappings: [Scheme.Buttons.KeyboardMapping] {
        state.mergedScheme.buttons.keyboardMappings ?? []
    }

    var body: some View {
        SettingsCard(title: NSLocalizedString("Keyboard actions", comment: ""), symbol: "keyboard") {
            ForEach(mappings) { mapping in
                HStack(alignment: .center, spacing: 12) {
                    Toggle(isOn: Binding(
                        get: { mapping.enabled },
                        set: { enabled in
                            var updated = mapping
                            updated.enabled = enabled
                            save(updated)
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(mapping.triggerDescription)
                            Text(mapping.action.description)
                                .settingsDescriptionStyle()
                        }
                    }
                    Spacer()
                    Button("Edit") {
                        draft = mapping
                        showingEditor = true
                    }
                    .buttonStyle(SettingsSecondaryButtonStyle())
                    if state.scheme.buttons.keyboardMappings?.contains(where: { $0.id == mapping.id }) == true {
                        Button("Remove override") {
                            var current = state.scheme.buttons.keyboardMappings ?? []
                            current.removeAll { $0.id == mapping.id }
                            state.scheme.buttons.keyboardMappings = current.isEmpty ? nil : current
                        }
                        .buttonStyle(SettingsDestructiveButtonStyle())
                    }
                }
            }

            HStack(spacing: 10) {
                Button("Add keyboard action…") {
                    draft = .init()
                    showingEditor = true
                }
                Button("Disable all keyboard bindings in this scope") {
                    state.scheme.buttons.keyboardMappings = []
                }
                if state.scheme.buttons.keyboardMappings != nil {
                    Button("Inherit settings") {
                        state.scheme.buttons.keyboardMappings = nil
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            KeyboardActionBindingEditor(mapping: $draft, isPresented: $showingEditor) { mapping in
                save(mapping)
            }
        }
    }

    private func save(_ mapping: Scheme.Buttons.KeyboardMapping) {
        var current = state.scheme.buttons.keyboardMappings ?? []
        current.removeAll { $0.id == mapping.id || $0.hasSameTrigger(as: mapping) }
        current.append(mapping)
        state.scheme.buttons.keyboardMappings = current
    }
}

private struct KeyboardActionBindingEditor: View {
    @Binding var mapping: Scheme.Buttons.KeyboardMapping
    @Binding var isPresented: Bool
    let save: (Scheme.Buttons.KeyboardMapping) -> Void
    @State private var editingSession: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keyboard actions")
                .font(.system(size: 15, weight: .semibold))

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    KeyboardActionTriggerRecorder(keyCode: $mapping.keyCode, modifiers: $mapping.modifiers)
                        .frame(height: 34)

                    Text(mapping.triggerDescription)
                        .font(.headline)

                    ButtonMappingAction(action: $mapping.action)

                    Picker("Trigger", selection: $mapping.behavior) {
                        Text("Once on press").tag(Scheme.Buttons.KeyboardMapping.Behavior.perform)
                        Text("Repeat while held").tag(Scheme.Buttons.KeyboardMapping.Behavior.repeat)
                        Text("Hold shortcut until released").tag(Scheme.Buttons.KeyboardMapping.Behavior.hold)
                    }

                    if mapping.behavior == .hold {
                        Text("Held shortcuts are released when you switch apps or devices, pause MouseEasy, or revoke access.")
                            .settingsDescriptionStyle()
                    }

                    Toggle("Enable binding", isOn: $mapping.enabled)
                }
            }

            HStack {
                Text("Keyboard actions and scroll hotkeys pause while editing.")
                    .settingsDescriptionStyle()
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(SettingsSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save(mapping)
                    isPresented = false
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!mapping.isValid)
            }
        }
        .padding(14)
        .frame(width: 620, height: 420)
        .background(SettingsTheme.canvas)
        .foregroundColor(SettingsTheme.text)
        .onAppear {
            if editingSession == nil { editingSession = KeyboardActionRecordingState.shared.begin() }
        }
        .onDisappear {
            if let editingSession { KeyboardActionRecordingState.shared.end(editingSession) }
            editingSession = nil
        }
    }
}

/// This responder captures input only after an explicit click inside the editor.
/// It installs no global or background keyboard monitor.
private struct KeyboardActionTriggerRecorder: NSViewRepresentable {
    @Binding var keyCode: UInt16?
    @Binding var modifiers: UInt64

    func makeNSView(context _: Context) -> RecorderView { RecorderView(frame: .zero) }

    func updateNSView(_ view: RecorderView, context _: Context) {
        view.recorded = { code, flags in
            keyCode = code
            modifiers = flags
        }
    }

    final class RecorderView: NSView {
        var recorded: ((UInt16, UInt64) -> Void)?
        private var recording = false
        private lazy var button = NSButton(title: NSLocalizedString("Record key or shortcut…", comment: ""), target: self, action: #selector(beginRecording))
        override var acceptsFirstResponder: Bool { true }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            button.bezelStyle = .rounded
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: leadingAnchor),
                button.trailingAnchor.constraint(equalTo: trailingAnchor),
                button.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }

        required init?(coder: NSCoder) { return nil }

        @objc private func beginRecording() {
            recording = true
            button.title = NSLocalizedString("Press a shortcut, or Esc to cancel", comment: "")
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            capture(event)
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard recording, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
            capture(event)
            return true
        }

        override func resignFirstResponder() -> Bool {
            finishRecording()
            return true
        }

        private func capture(_ event: NSEvent) {
            guard !event.isARepeat else { return }
            if event.keyCode != 53 {
                recorded?(event.keyCode, UInt64(event.modifierFlags.rawValue) & Scheme.Buttons.KeyboardMapping.modifierMask)
            }
            finishRecording()
        }

        private func finishRecording() {
            recording = false
            button.title = NSLocalizedString("Record key or shortcut…", comment: "")
        }
    }
}
