// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import Combine
import Foundation

extension AppTarget {
    var displayName: String {
        switch self {
        case let .bundle(id): return (try? readInstalledApp(bundleIdentifier: id))?.bundleName ?? id
        case let .executable(path): return URL(fileURLWithPath: path).lastPathComponent
        case let .executableName(name): return name
        }
    }

    var identifier: String {
        switch self {
        case let .bundle(id), let .executable(id), let .executableName(id): return id
        }
    }

    static func alphabetically(_ lhs: Self, _ rhs: Self) -> Bool {
        let order = lhs.displayName.localizedStandardCompare(rhs.displayName)
        return order == .orderedSame ? lhs.identifier < rhs.identifier : order == .orderedAscending
    }
}

class AppPickerState: ObservableObject {
    static let shared = AppPickerState()

    @Published private(set) var installedApps: [InstalledApp] = []
    @Published private(set) var runningTargets: [AppTarget] = []

    func refreshInstalledApps() {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        runningTargets = Set(running.compactMap { app -> AppTarget? in
            if let id = app.bundleIdentifier { return .bundle(id) }
            return app.executableURL.map { .executableName($0.lastPathComponent) }
        }).sorted(by: AppTarget.alphabetically)

        var apps: [String: InstalledApp] = [:]
        for directory in FileManager.default.urls(for: .applicationDirectory, in: .allDomainsMask) {
            for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
                if let app = try? readInstalledApp(at: url) { apps[app.bundleIdentifier] = app }
            }
        }
        installedApps = apps.values.sorted { $0.bundleName.localizedStandardCompare($1.bundleName) == .orderedAscending }
    }
}
