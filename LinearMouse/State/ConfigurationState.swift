// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import Combine
import Defaults
import Foundation
import os.log
import SwiftUI

class ConfigurationState: ObservableObject {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "AppDelegate")

    static let shared = ConfigurationState()

    #if DEBUG
        private static let testConfigurationURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("linearmouse-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("linearmouse.json")
    #endif

    var configurationPaths: [URL] {
        #if DEBUG
            if ProcessEnvironment.isRunningTest || ProcessEnvironment.isSettingsPreview {
                return [Self.testConfigurationURL]
            }
        #endif

        let applicationSupportURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return [AppIdentity.configurationURL(applicationSupport: applicationSupportURL)]
    }

    var configurationPath: URL {
        configurationPaths.first { FileManager.default.fileExists(atPath: $0.path) } ?? configurationPaths
            .last!
    }

    private var configurationSaveDebounceTimer: Timer?
    @Published var configuration = Configuration() {
        didSet {
            configurationSaveDebounceTimer?.invalidate()
            guard !loading, ProcessEnvironment.isRunningApp else {
                return
            }

            configurationSaveDebounceTimer = Timer.scheduledTimer(
                withTimeInterval: 0.2,
                repeats: false
            ) { [weak self] _ in
                guard let self else {
                    return
                }

                os_log(
                    "Saving new configuration: %{public}@",
                    log: Self.log,
                    type: .info,
                    String(describing: self.configuration)
                )
                self.save()
            }
        }
    }

    @Published private(set) var loading = false

    private var subscriptions = Set<AnyCancellable>()

    private var configurationFileWatcher: FileWatcher?
    private var reloadDebounceWorkItem: DispatchWorkItem?
}

extension ConfigurationState {
    func reloadFromDisk() {
        do {
            let newConfig = try Configuration.load(from: configurationPath)
            guard newConfig != configuration else {
                return
            }

            loading = true
            configuration = newConfig
            loading = false

            Notifier.shared.notify(
                title: NSLocalizedString("Configuration Reloaded", comment: ""),
                body: NSLocalizedString("Your configuration changes are now active.", comment: "")
            )
        } catch CocoaError.fileReadNoSuchFile {
            loading = true
            configuration = .init()
            loading = false

            Notifier.shared.notify(
                title: NSLocalizedString("Configuration Reloaded", comment: ""),
                body: NSLocalizedString("Your configuration changes are now active.", comment: "")
            )
        } catch {
            Notifier.shared.notify(
                title: NSLocalizedString("Failed to reload configuration", comment: ""),
                body: error.localizedDescription
            )
        }
    }

    func startHotReload() {
        stopHotReload()

        configurationFileWatcher = FileWatcher(
            fileURLsProvider: { [weak self] in
                self?.configurationPaths ?? []
            },
            queue: .main
        ) { [weak self] in
            self?.scheduleReloadFromExternalChange()
        }
        configurationFileWatcher?.start()
    }

    func stopHotReload() {
        reloadDebounceWorkItem?.cancel()
        reloadDebounceWorkItem = nil

        configurationFileWatcher?.stop()
        configurationFileWatcher = nil
    }

    private func scheduleReloadFromExternalChange() {
        reloadDebounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.reloadFromDisk()
        }
        reloadDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Self.shared.configurationPath.absoluteURL])
    }

    func load() -> Bool {
        loading = true
        defer {
            loading = false
        }

        do {
            configuration = try Configuration.loadOrCreate(
                at: configurationPath, previouslyConfigured: Defaults[.portableMouseScopeIntroduced]
            )
            // Publish migration only after its backup and atomic write succeed.
            do {
                try configuration.migrateLegacyGestureButtons(persistingTo: configurationPath)
            } catch {
                os_log(
                    "Gesture migration failed: %{public}@",
                    log: Self.log,
                    type: .error,
                    error.localizedDescription
                )
            }
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = String(
                format: NSLocalizedString("Failed to load the configuration: %@", comment: ""),
                error.localizedDescription
            )
            alert.runModal()
            return false
        }
    }

    func save() {
        guard ProcessEnvironment.isRunningApp else {
            return
        }

        do {
            try configuration.dump(to: configurationPath)
        } catch {
            let alert = NSAlert()
            alert.messageText = String(
                format: NSLocalizedString("Failed to save the configuration: %@", comment: ""),
                error.localizedDescription
            )
            alert.runModal()
        }
    }
}

extension ConfigurationState {
    @discardableResult
    func savePortableMouseDefaults(
        from source: DeviceMatcher,
        sourceFollowsDefaults: Bool = true
    ) throws -> Configuration.PortableMouseDefaultsSummary {
        var prepared = configuration
        let summary = try prepared.setPortableMouseDefaults(from: source, sourceFollowsDefaults: sourceFollowsDefaults)
        guard summary.changed else { return summary }
        let destination = configurationPath
        if FileManager.default.fileExists(atPath: destination.path) {
            let backup = destination.deletingLastPathComponent()
                .appendingPathComponent("settings-before-mouse-defaults-\(UUID().uuidString).json")
            try Data(contentsOf: destination).write(to: backup, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        // Publish only after both the independent backup and atomic write succeed.
        try prepared.dump(to: destination)
        loading = true
        configuration = prepared
        loading = false
        return summary
    }

    func importConfiguration(from source: URL) throws {
        let imported = try Configuration.load(from: source)
        let destination = configurationPath
        if FileManager.default.fileExists(atPath: destination.path) {
            let backup = destination.deletingLastPathComponent()
                .appendingPathComponent("settings-before-import-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: destination, to: backup)
        }
        try imported.dump(to: destination)
        loading = true
        configuration = imported
        loading = false
    }

    func exportConfiguration(to destination: URL) throws {
        try configuration.dump(to: destination)
    }
}
