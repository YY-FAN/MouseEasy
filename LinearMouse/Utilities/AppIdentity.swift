// SPDX-License-Identifier: MIT
// Copyright (c) 2026 MouseWorkbench contributors

import Foundation

enum AppIdentity {
    static let configurationDirectory = "MouseWorkbenchDev"
    static let configurationFilename = "settings.json"

    static func configurationURL(applicationSupport: URL) -> URL {
        applicationSupport
            .appendingPathComponent(configurationDirectory, isDirectory: true)
            .appendingPathComponent(configurationFilename)
    }

    static var configurationSchemaURL: String {
        Bundle.main.resourceURL?
            .appendingPathComponent("Configuration.json").absoluteString ?? ""
    }
}
