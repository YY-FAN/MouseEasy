// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppMover
import Combine
import Defaults
import KeyKit
import LaunchAtLogin
import os.log
import SwiftUI

struct AppLifecycleAdmission {
    enum Target: Equatable {
        case running
        case suspended
        case stopped
    }

    var sessionActive = true
    var sleeping = false
    var terminationCleanupStarted = false

    var target: Target {
        if terminationCleanupStarted || !sessionActive {
            return .stopped
        }
        return sleeping ? .suspended : .running
    }

    var allowsStart: Bool {
        target == .running
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "AppDelegate")

    private lazy var autoUpdateManager = AutoUpdateManager.shared
    private lazy var statusItem = StatusItem.shared
    private var subscriptions = Set<AnyCancellable>()
    private var lifecycleAdmission = AppLifecycleAdmission()
    private var lifecycleReady = false
    private var workspaceNotificationObservers = [NSObjectProtocol]()
    private var terminationRequest: BoundedCleanupRequest?

    /// Runs the one-time legacy -> SMAppService login-item migration on launch.
    ///
    /// It's a no-op below macOS 13 and after the first successful run. This call
    /// was lost in 5437d88 and is restored here (issue #1328).
    override init() {
        if ProcessEnvironment.isRunningApp, !CommandLine.arguments.contains("--validate-config") {
            LaunchAtLogin.migrateIfNeeded()
        }
    }

    func applicationWillFinishLaunching(_: Notification) {
        if let result = LocalConfigurationAudit.runIfRequested(arguments: CommandLine.arguments) {
            exit(result)
        }
        if (ProcessEnvironment.isRunningApp || ProcessEnvironment.isSettingsPreview) && !Defaults[.showInDock] {
            NSApp.setActivationPolicy(.accessory)
        }
        guard ProcessEnvironment.isRunningApp else {
            return
        }

        _ = statusItem
        setupNotifications()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--show-general") {
            SettingsState.shared.navigation = .general
        }
        #if DEBUG
            if ProcessEnvironment.isSettingsPreview {
                prepareSettingsPreview()
                finishWindowPresentation(notification)
                return
            }
        #endif
        guard ProcessEnvironment.isRunningApp else {
            return
        }
        LinearMouse.updateApplicationMenuNames()

        #if !DEBUG
            if AppMover.moveIfNecessary() {
                return
            }
        #endif

        guard AccessibilityPermission.enabled else {
            NSApp.setActivationPolicy(.accessory)
            AccessibilityPermissionWindow.shared.show()
            return
        }

        setup()
        finishWindowPresentation(notification)
    }

    private func finishWindowPresentation(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let reason = event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
        let senderPID = event?.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        let senderID = senderPID.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        let backgroundLaunch = reason == keyAELaunchedAsLogInItem || reason == keyAELaunchedAsServiceItem ||
            senderID == (Bundle.main.bundleIdentifier ?? "") + "-LaunchAtLoginHelper"
        let ordinaryOpen = event?.eventID == kAEOpenApplication ||
            notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool == true
        let explicitShow = CommandLine.arguments.contains("--show") || CommandLine.arguments.contains("--show-general")
        if explicitShow || (ordinaryOpen && !backgroundLaunch) {
            SettingsWindowController.shared.bringToFront()
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationShouldHandleReopen(_ application: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        guard ProcessEnvironment.isRunningApp || ProcessEnvironment.isSettingsPreview else {
            return true
        }

        if let modal = application.modalWindow {
            modal.bringToFront()
        } else if ProcessEnvironment.isRunningApp && !AccessibilityPermission.enabled {
            AccessibilityPermissionWindow.shared.show(activateIfVisible: true)
        } else {
            SettingsWindowController.shared.bringToFront()
        }
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard ProcessEnvironment.isRunningApp else {
            return .terminateNow
        }

        guard terminationRequest == nil else {
            return .terminateLater
        }
        lifecycleAdmission.terminationCleanupStarted = true

        let request = BoundedCleanupRequest(
            onTimeout: {
                os_log(
                    "Timed out waiting for application termination cleanup",
                    log: Self.log,
                    type: .error
                )
            },
            completion: { _ in
                sender.reply(toApplicationShouldTerminate: true)
            }
        )
        terminationRequest = request

        stop {
            request.complete()
        }
        return .terminateLater
    }
}

extension AppDelegate {
    func setup() {
        setupConfiguration()
        setupNotifications()
        KeyboardSettingsSnapshot.shared.refresh()
        ModifierActionsTransformer.zoomShortcutResolver.refresh()
        KeyCodeResolver.prepareForEventProcessing()
        lifecycleReady = true
        startIfAllowed()
    }

    func setupConfiguration() {
        if ConfigurationState.shared.load() {
            DeviceState.shared.introducePortableMouseScopeIfNeeded()
        }
        // Start watching the configuration file for hot reload
        ConfigurationState.shared.startHotReload()
    }

    func setupNotifications() {
        guard workspaceNotificationObservers.isEmpty else {
            return
        }

        // Prepare user notifications for error popups
        Notifier.shared.setup()
        let notificationCenter = NSWorkspace.shared.notificationCenter
        workspaceNotificationObservers.append(notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            os_log("Session inactive", log: Self.log, type: .info)
            self?.lifecycleAdmission.sessionActive = false
            self?.reconcileLifecycle()
        })

        workspaceNotificationObservers.append(notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            os_log("Session active", log: Self.log, type: .info)
            self?.lifecycleAdmission.sessionActive = true
            KeyboardSettingsSnapshot.shared.refresh()
            ModifierActionsTransformer.zoomShortcutResolver.refresh()
            self?.reconcileLifecycle()
        })

        workspaceNotificationObservers.append(notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            os_log("System will sleep", log: Self.log, type: .info)
            self?.lifecycleAdmission.sleeping = true
            self?.reconcileLifecycle()
        })

        workspaceNotificationObservers.append(notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            os_log("System did wake", log: Self.log, type: .info)
            self?.lifecycleAdmission.sleeping = false
            self?.reconcileLifecycle()
        })
    }

    func startIfAllowed() {
        guard lifecycleAdmission.allowsStart else {
            return
        }

        activateRunningLifecycle()
    }

    func reconcileLifecycle() {
        guard lifecycleReady else {
            return
        }

        switch lifecycleAdmission.target {
        case .running:
            activateRunningLifecycle()
        case .suspended:
            BatteryDeviceMonitor.shared.disable()
            GlobalEventTap.shared.stop()
            DeviceManager.shared.suspendForSleep()
        case .stopped:
            stop()
        }
    }

    private func activateRunningLifecycle() {
        DeviceManager.shared.resumeFromSleep { [weak self] in
            guard let self, self.lifecycleAdmission.target == .running else {
                self?.reconcileLifecycle()
                return
            }

            start()
        }
    }

    func start() {
        DeviceManager.shared.start()
        BatteryDeviceMonitor.shared.enable()
        GlobalEventTap.shared.start()
    }

    func stop(
        logitechTeardownPolicy: DeviceManagerLogitechTeardownPolicy = .restore,
        completion: (() -> Void)? = nil
    ) {
        BatteryDeviceMonitor.shared.disable()
        GlobalEventTap.shared.stop()
        DeviceManager.shared.stop(
            logitechTeardownPolicy: logitechTeardownPolicy,
            completion: completion
        )
    }
}

#if DEBUG
    private extension AppDelegate {
        func prepareSettingsPreview() {
            let mouse = DeviceMatcher(category: .mouse)
            var example = Scheme(if: [Scheme.If(device: mouse)])
            example.scrolling.reverse.vertical = true
            example.scrolling.smoothed.vertical = Scheme.Scrolling.Smoothed.Preset.flow.defaultConfiguration
            example.buttons.mappings = Scheme.Buttons.windowSwitchingPreset
            ConfigurationState.shared.configuration = Configuration(schemes: [example])
            DeviceState.shared.selectMouseDefaults()
            LinearMouse.updateApplicationMenuNames()
        }
    }
#endif
