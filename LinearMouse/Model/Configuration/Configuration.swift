// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import Defaults
import Foundation

struct Configuration: Codable, Equatable {
    let jsonSchema = AppIdentity.configurationSchemaURL

    var mirrorScrolling: MirrorScrollSettings?
    var schemes: [Scheme] = []

    enum CodingKeys: String, CodingKey {
        case jsonSchema = "$schema"
        case mirrorScrolling
        case schemes
    }

    enum ConfigurationError: Error {
        case unsupportedEncoding
        case parseError(Error)
    }
}

extension Configuration.ConfigurationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupportedEncoding:
            return NSLocalizedString("Unsupported encoding, expected UTF-8", comment: "")
        case let .parseError(underlyingError):
            if let decodingError = underlyingError as? DecodingError {
                switch decodingError {
                case let .typeMismatch(type, context):
                    return String(
                        format: NSLocalizedString("Type mismatch: expected %1$@ at %2$@", comment: ""),
                        String(describing: type),
                        String(describing: context.codingPath.map(\.stringValue).joined(separator: "."))
                    )
                case let .keyNotFound(codingKey, context):
                    return String(
                        format: NSLocalizedString("Missing key %1$@ at %2$@", comment: ""),
                        String(describing: codingKey.stringValue),
                        String(describing: context.codingPath.map(\.stringValue).joined(separator: "."))
                    )
                default:
                    break
                }
                return String(describing: underlyingError)
            }
            // TODO: More detailed description in underlyingError.
            return String(
                format: NSLocalizedString("Invalid JSON: %@", comment: ""),
                underlyingError.localizedDescription
            )
        }
    }
}

extension Configuration {
    var usesProcessConditions: Bool {
        schemes.contains { scheme in
            scheme.if?.contains { condition in
                condition.app != nil ||
                    condition.parentApp != nil ||
                    condition.groupApp != nil ||
                    condition.processName != nil ||
                    condition.processPath != nil
            } ?? false
        }
    }

    static func load(from string: String) throws -> Configuration {
        do {
            let json = try JSONCommentSanitizer.sanitize(string)
            guard let data = json.data(using: .utf8) else {
                throw ConfigurationError.unsupportedEncoding
            }
            let decoder = JSONDecoder()
            return try decoder.decode(Configuration.self, from: data)
        } catch {
            throw ConfigurationError.parseError(error)
        }
    }

    static func load(from data: Data) throws -> Configuration {
        guard let string = String(data: data, encoding: .utf8) else {
            throw ConfigurationError.unsupportedEncoding
        }
        return try load(from: string)
    }

    static func load(from url: URL) throws -> Configuration {
        try load(from: Data(contentsOf: url))
    }

    /// Read existing settings verbatim. An empty list of rules is a valid user choice.
    static func loadOrCreate(at url: URL, previouslyConfigured: Bool) throws -> Configuration {
        do {
            return try load(from: url)
        } catch CocoaError.fileReadNoSuchFile {
            var initial = Configuration()
            if !previouslyConfigured {
                var mouse = Scheme(if: [.init(device: DeviceMatcher(category: .mouse))])
                mouse.scrolling.smoothed.vertical = Scheme.Scrolling.Smoothed.Preset.flow.defaultConfiguration
                mouse.scrolling.preserveContinuousScrolling = true
                initial.schemes = [mouse]
            }

            let destination = url.resolvingSymlinksInPath()
            let directory = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let staging = directory.appendingPathComponent(".settings-\(UUID().uuidString).tmp")
            try initial.dump().write(to: staging, options: .atomic)
            defer { try? FileManager.default.removeItem(at: staging) }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.path)
            // Publish a complete file without replacing one created concurrently.
            if renamex_np(staging.path, destination.path, UInt32(RENAME_EXCL)) != 0 {
                let code = errno
                if code == EEXIST { return try load(from: url) }
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
            }
            return initial
        }
    }

    func dump() throws -> Data {
        let encoder = JSONEncoder()

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        return try encoder.encode(self)
    }

    func dump(to url: URL) throws {
        let parentDirectory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDirectory.path) {
            try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        }
        try dump().write(to: url.resolvingSymlinksInPath(), options: .atomic)
    }

    func matchScheme(in context: Scheme.MatchContext) -> Scheme {
        // TODO: Backtrace the merge path
        // TODO: Optimize the algorithm

        var mergedScheme = Scheme()
        mergedScheme.if = [Scheme.If(matchContext: context)]

        for scheme in schemes where scheme.isActive(in: context) {
            scheme.merge(into: &mergedScheme)
        }

        return mergedScheme
    }

    func matchScheme(
        withDevice device: Device? = nil,
        withApp app: String? = nil,
        withParentApp parentApp: String? = nil,
        withGroupApp groupApp: String? = nil,
        withDisplay display: String? = nil,
        withProcessName processName: String? = nil,
        withProcessPath processPath: String? = nil
    ) -> Scheme {
        matchScheme(
            in: Scheme.MatchContext(
                device: device,
                app: app,
                parentApp: parentApp,
                groupApp: groupApp,
                display: display,
                processName: processName,
                processPath: processPath
            )
        )
    }

    func matchScheme(
        withDeviceMatcher deviceMatcher: DeviceMatcher? = nil,
        withApp app: String? = nil,
        withParentApp parentApp: String? = nil,
        withGroupApp groupApp: String? = nil,
        withDisplay display: String? = nil,
        withProcessName processName: String? = nil,
        withProcessPath processPath: String? = nil
    ) -> Scheme {
        matchScheme(
            in: Scheme.MatchContext(
                deviceMatcher: deviceMatcher,
                app: app,
                parentApp: parentApp,
                groupApp: groupApp,
                display: display,
                processName: processName,
                processPath: processPath
            )
        )
    }

    func matchScheme(
        withDevice device: Device? = nil,
        withPid pid: pid_t? = nil,
        withDisplay display: String? = nil
    ) -> Scheme {
        matchScheme(
            withDevice: device,
            withProcess: pid?.processIdentity,
            withDisplay: display
        )
    }

    func matchScheme(
        withDevice device: Device? = nil,
        withProcess process: ProcessIdentity? = nil,
        withDisplay display: String? = nil
    ) -> Scheme {
        matchScheme(
            withDevice: device,
            withApp: process?.bundleIdentifier,
            withParentApp: process?.parent?.bundleIdentifier,
            withGroupApp: process?.group?.bundleIdentifier,
            withDisplay: display,
            withProcessName: process?.processName,
            withProcessPath: process?.processPath
        )
    }
}
