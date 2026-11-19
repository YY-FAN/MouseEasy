// SPDX-License-Identifier: MIT
// Copyright (c) 2026 MouseWorkbench contributors

import Darwin
import Foundation

/// Source-preserving diagnostics; explicit export writes only a new copy.
/// It exits before accessibility, device or input setup.
enum LocalConfigurationAudit {
    static func runIfRequested(arguments: [String]) -> Int32? {
        guard let index = arguments.firstIndex(of: "--validate-config") else { return nil }
        guard arguments.indices.contains(index + 1) else {
            FileHandle.standardError.write(Data("Missing configuration path\n".utf8))
            return 2
        }
        do {
            let inputURL = URL(fileURLWithPath: arguments[index + 1])
            var configuration = try Configuration.load(from: inputURL)
            var report: [String: Any] = ["valid": true, "schemes": configuration.schemes.count]
            if let sourceIndex = arguments.firstIndex(of: "--portable-mouse-source") {
                guard arguments.indices.contains(sourceIndex + 1),
                      let outputIndex = arguments.firstIndex(of: "--export-config-copy"),
                      arguments.indices.contains(outputIndex + 1) else {
                    throw PortableDefaultsExportError.missingOutput
                }
                let sourceData = try Data(contentsOf: URL(fileURLWithPath: arguments[sourceIndex + 1]))
                let source = try JSONDecoder().decode(DeviceMatcher.self, from: sourceData)
                let summary = try configuration.setPortableMouseDefaults(
                    from: source,
                    sourceFollowsDefaults: arguments.contains("--source-follows-defaults")
                )
                let destination = URL(fileURLWithPath: arguments[outputIndex + 1])
                guard destination.resolvingSymlinksInPath().standardizedFileURL
                        != inputURL.resolvingSymlinksInPath().standardizedFileURL,
                      !FileManager.default.fileExists(atPath: destination.path) else {
                    throw PortableDefaultsExportError.existingOutput
                }
                try configuration.dump().write(to: destination, options: .withoutOverwriting)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
                report["portableMouseDefaults"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(summary))
                report["schemes"] = configuration.schemes.count
            }
            if let deviceIndex = arguments.firstIndex(of: "--match-device"), arguments.indices.contains(deviceIndex + 1) {
                let deviceData = try Data(contentsOf: URL(fileURLWithPath: arguments[deviceIndex + 1]))
                let matcher = try JSONDecoder().decode(DeviceMatcher.self, from: deviceData)
                let appIndex = arguments.firstIndex(of: "--application")
                let app = appIndex.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
                let effective = configuration.matchScheme(withDeviceMatcher: matcher, withApp: app)
                report["effectiveScheme"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(effective))
            }
            let output = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            FileHandle.standardOutput.write(output)
            FileHandle.standardOutput.write(Data("\n".utf8))
            return 0
        } catch {
            FileHandle.standardError.write(Data("Configuration validation failed: \(error)\n".utf8))
            return 1
        }
    }

    private enum PortableDefaultsExportError: Error, LocalizedError {
        case missingOutput, existingOutput
        var errorDescription: String? {
            switch self {
            case .missingOutput: return "Portable mouse export requires a source matcher and a new output path"
            case .existingOutput: return "Portable mouse export never overwrites the source or an existing output"
            }
        }
    }
}
