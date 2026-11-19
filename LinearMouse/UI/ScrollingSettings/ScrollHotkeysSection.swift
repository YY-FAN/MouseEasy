// MIT License

import AppKit
import SwiftUI

extension ScrollingSettings {
    struct ScrollHotkeysSection: View {
        private typealias Hotkeys = Scheme.Scrolling.ScrollHotkeys
        @ObservedObject private var state = ScrollingSettingsState.shared
        @ObservedObject private var settingsState = SettingsState.shared
        @State private var recordingRole: Hotkeys.Role?
        @State private var recordingMonitor: Any?
        @State private var recordingSessionID: UUID?

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("Record a key or mouse button and hold it to change scrolling on either axis.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ForEach(Hotkeys.Role.allCases) { role in
                    HStack {
                        Text(role.title).frame(width: 118, alignment: .leading)
                        Button(recordingRole == role ? NSLocalizedString("Press a key (Esc to cancel)", comment: "") : description(for: role)) {
                            startRecording(role)
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(SettingsSecondaryButtonStyle())
                        Button("Inherit") {
                            stopRecording()
                            state.setScrollHotkey(nil, for: role)
                        }
                        .buttonStyle(SettingsSecondaryButtonStyle())
                        Button("Disable") {
                            stopRecording()
                            state.setScrollHotkey(.disabled, for: role)
                        }
                        .buttonStyle(SettingsSecondaryButtonStyle())
                    }
                }
                HStack {
                    Text("Acceleration multiplier")
                    TextField("Acceleration multiplier", value: $state.scrollHotkeyAccelerationScale, formatter: scaleFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                    Stepper("", value: $state.scrollHotkeyAccelerationScale, in: 0.1 ... 20, step: 0.5)
                        .labelsHidden()
                }
                Text("Record keys, mouse buttons, or modifier combinations. The original input reaches the app. Control-scroll zoom takes priority.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .onDisappear { stopRecording() }
            .onReceive(settingsState.$buttonMappingRecordingSession) { session in
                if let recordingSessionID, session?.id != recordingSessionID {
                    stopRecording()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
                stopRecording()
            }
        }

        private var scaleFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.minimum = 0.1
            formatter.maximum = 20
            formatter.maximumFractionDigits = 1
            return formatter
        }

        private func description(for role: Hotkeys.Role) -> String {
            guard let binding = state.mergedScheme.scrolling.hotkeys[role] else { return NSLocalizedString("Click to record", comment: "") }
            guard binding.isEnabled else { return NSLocalizedString("Disabled", comment: "") }
            let flags = CGEventFlags(rawValue: binding.modifiers)
            let prefix = [
                (flags.contains(.maskControl), "⌃"), (flags.contains(.maskAlternate), "⌥"),
                (flags.contains(.maskShift), "⇧"), (flags.contains(.maskCommand), "⌘")
            ].compactMap { $0.0 ? $0.1 : nil }.joined()
            if binding.type == .mouse {
                return prefix + String(format: NSLocalizedString("Mouse button %lld", comment: ""), Int64(binding.code) + 1)
            }
            // Older profiles saved a translated fallback label. Derive it from the code
            // again so switching languages also updates existing bindings.
            if let label = binding.label, label != "键码 \(binding.code)", label != "Key code \(binding.code)" {
                return prefix + label
            }
            return prefix + String(format: NSLocalizedString("Key code %lld", comment: ""), Int64(binding.code))
        }

        private func startRecording(_ role: Hotkeys.Role) {
            stopRecording()
            recordingRole = role
            let session = UUID()
            recordingSessionID = session
            settingsState.beginButtonMappingRecording(sessionID: session)
            recordingMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { event in
                guard recordingRole != nil else { return event }
                if event.type == .keyDown, event.keyCode == 53 {
                    stopRecording()
                    return nil
                }
                let type: Hotkeys.Binding.InputType = event.type == .keyDown ? .keyboard : .mouse
                let code = event.type == .keyDown ? event.keyCode : UInt16(clamping: event.buttonNumber)
                let label = event.type == .keyDown ? keyLabel(event) : nil
                let binding = Hotkeys.Binding(
                    type: type,
                    code: code,
                    modifiers: UInt64(event.modifierFlags.rawValue) & Hotkeys.Binding.relevantModifiers.rawValue,
                    enabled: true,
                    label: label
                )
                state.setScrollHotkey(binding, for: role)
                stopRecording()
                return nil
            }
        }

        private func stopRecording() {
            if let recordingMonitor { NSEvent.removeMonitor(recordingMonitor) }
            recordingMonitor = nil
            let session = recordingSessionID
            recordingSessionID = nil
            recordingRole = nil
            if let session { settingsState.endButtonMappingRecording(sessionID: session) }
        }

        private func keyLabel(_ event: NSEvent) -> String? {
            switch event.keyCode {
            case 36, 76: "Return"
            case 48: "Tab"
            case 49: "Space"
            case 51: "Delete"
            case 123: "←"
            case 124: "→"
            case 125: "↓"
            case 126: "↑"
            case 122: "F1"
            case 120: "F2"
            case 99: "F3"
            case 118: "F4"
            case 96: "F5"
            case 97: "F6"
            case 98: "F7"
            case 100: "F8"
            case 101: "F9"
            case 109: "F10"
            case 103: "F11"
            case 111: "F12"
            default: event.charactersIgnoringModifiers?.uppercased()
            }
        }
    }
}

extension ScrollingSettingsState {
    func setScrollHotkey(_ binding: Scheme.Scrolling.ScrollHotkeys.Binding?, for role: Scheme.Scrolling.ScrollHotkeys.Role) {
        scheme.scrolling.hotkeys[role] = binding
    }

    var scrollHotkeyAccelerationScale: Double {
        get { mergedScheme.scrolling.hotkeys.resolvedAccelerationScale }
        set {
            guard newValue.isFinite else { return }
            scheme.scrolling.hotkeys.accelerationScale = Decimal(min(20, max(0.1, newValue)))
        }
    }
}
