// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Cocoa
import Defaults
import SwiftUI

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private var released = true
    private var dockObservation: Defaults.Observation?

    private func initWindowIfNeeded() {
        guard released else {
            return
        }

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 900)
        let initialSize = NSSize(width: min(560, screen.width - 40), height: 202)
        let window = NSWindow(
            contentRect: .init(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.delegate = self
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.title = LinearMouse.appName
        window.backgroundColor = SettingsTheme.windowBackground
        window.titlebarAppearsTransparent = true

        window.contentMinSize = NSSize(width: initialSize.width, height: 0)
        window.contentViewController = NSHostingController(rootView: MouseEasySettingsRoot(width: initialSize.width) { [weak window] height in
            guard let window else { return }
            let frame = window.frame
            let currentHeight = window.contentRect(forFrameRect: frame).height
            let delta = height.rounded(.up) - currentHeight
            guard abs(delta) >= 1 else { return }

            var resized = frame
            resized.size.width = window.frameRect(forContentRect: .init(origin: .zero, size: initialSize)).width
            resized.size.height += delta
            resized.origin.y -= delta
            if let screen = window.screen ?? NSScreen.main {
                let visible = screen.visibleFrame
                resized.origin.y = min(max(resized.minY, visible.minY), visible.maxY - resized.height)
            }
            window.setFrame(resized, display: true)
        })
        window.center()

        self.window = window
        released = false

        dockObservation = Defaults.observe(.showInDock, options: []) { [weak self, weak window] _ in
            DispatchQueue.main.async {
                guard let self, let window, self.window === window, !self.released else { return }
                let wasKey = window.isKeyWindow
                self.applyDockPreference()
                if wasKey { window.bringToFront() }
            }
        }
    }

    private func applyDockPreference() {
        let policy: NSApplication.ActivationPolicy = Defaults[.showInDock] ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    func bringToFront() {
        initWindowIfNeeded()

        guard let window else {
            return
        }

        applyDockPreference()
        // Finish the Launch Services reopen event and the Dock policy change
        // before ordering the requested window.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, !self.released, self.window === window else { return }
            window.bringToFront()
            self.finishActivationIfNeeded(for: window)
        }
    }

    private func finishActivationIfNeeded(for window: NSWindow) {
        // Launch Services may finish restoring the previous app after the new
        // window has already been ordered, especially for a hidden Dock icon.
        let requested = ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) { [weak self, weak window] in
            guard let self, let window, self.window === window, !self.released,
                  window.isVisible, !NSApp.isHidden, !NSApp.isActive else { return }
            // Respect a click or keystroke that moved focus after the request.
            let elapsed = ProcessInfo.processInfo.systemUptime - requested
            let input: [CGEventType] = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
            guard input.allSatisfy({ CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) >= elapsed })
            else { return }
            window.bringToFront()
        }
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        dockObservation?.invalidate()
        dockObservation = nil
        released = true
        if NSApp.activationPolicy() != .accessory { NSApp.setActivationPolicy(.accessory) }
    }
}

private struct MouseEasySettingsRoot: View {
    @ObservedObject private var state = SettingsState.shared
    @ObservedObject private var schemeState = SchemeState.shared
    @ObservedObject private var deviceState = DeviceState.shared
    @State private var defaultsMessage: String?
    let width: CGFloat
    let resize: (CGFloat) -> Void

    private var page: SettingsState.Navigation { state.navigation ?? .scrolling }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(SettingsState.Navigation.allCases, id: \.self, content: navigationButton)
                TipButton()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            Divider()

            SettingsPage {
                if page != .general {
                    scopeControls.padding(.horizontal, 4)
                }

                switch page {
                case .scrolling: ScrollingSettings()
                case .buttons: ButtonsSettings()
                case .pointer: PointerSettings()
                case .general: GeneralSettings()
                }
            }
            .id(page)
        }
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { geometry in
            Color.clear.preference(key: SettingsWindowHeight.self, value: geometry.size.height)
        })
        .onPreferenceChange(SettingsWindowHeight.self) { height in
            guard height > 0 else { return }
            DispatchQueue.main.async { resize(height) }
        }
        .background(SettingsTheme.canvas)
        .accentColor(SettingsControlColor.accent)
    }

    private var scopeControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Applies to")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                DeviceIndicator()
                AppIndicator()
                DisplayIndicator()
            }
            if !usesMouseDefaults {
                HStack(spacing: 8) {
                    Button("Back to all mice", action: selectMouseDefaults)
                        .buttonStyle(SettingsSecondaryButtonStyle())
                    if deviceState.currentDeviceMatcher?.categoryOnlyValue != .mouse,
                       schemeState.currentApp == nil, schemeState.currentDisplay == nil,
                       schemeState.canSaveCurrentMouseAsDefaults {
                        Button("Use this mouse as default", action: saveMouseDefaults)
                            .buttonStyle(SettingsSecondaryButtonStyle())
                    }
                }
            }
        }
        .font(.body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert(isPresented: Binding(get: { defaultsMessage != nil }, set: { if !$0 { defaultsMessage = nil } })) {
            Alert(title: Text("Default mouse settings"), message: Text(defaultsMessage ?? ""), dismissButton: .default(Text("OK")))
        }
    }

    private var usesMouseDefaults: Bool {
        deviceState.currentDeviceMatcher?.categoryOnlyValue == .mouse
            && schemeState.currentApp == nil && schemeState.currentDisplay == nil
    }

    private func selectMouseDefaults() {
        schemeState.currentApp = nil
        schemeState.currentDisplay = nil
        deviceState.selectMouseDefaults()
    }

    private func saveMouseDefaults() {
        do {
            _ = try schemeState.saveCurrentMouseAsDefaults()
            selectMouseDefaults()
            defaultsMessage = NSLocalizedString("New mice will inherit these scroll and standard button settings.", comment: "")
        } catch {
            defaultsMessage = error.localizedDescription
        }
    }

    private func navigationButton(_ tab: SettingsState.Navigation) -> some View {
        let selected = page == tab
        return Button {
            state.navigation = tab
        } label: {
            Label(tab.title, systemImage: tab.navigationSymbol)
                .font(.body.weight(selected ? .semibold : .medium))
                .foregroundColor(selected ? SettingsControlColor.accent : .secondary)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(selected ? SettingsControlColor.accent.opacity(0.11) : Color.clear)
                .cornerRadius(7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SettingsWindowHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension SettingsState.Navigation {
    var navigationSymbol: String {
        switch self {
        case .scrolling: return "arrow.up.arrow.down"
        case .buttons: return "computermouse"
        case .pointer: return "cursorarrow"
        case .general: return "gearshape"
        }
    }
}
