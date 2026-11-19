// SPDX-License-Identifier: MIT
// Copyright (c) 2026 MouseWorkbench contributors

import AppKit
import Foundation

enum OpenTargetExecutor {
    static func perform(_ target: Scheme.Buttons.Mapping.Action.OpenTarget) throws {
        let url = target.fileURL
        guard !target.path.isEmpty, FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        if target.mode == .execute {
            let request = target.executionRequest()
            guard FileManager.default.isExecutableFile(atPath: request.executable.path) else {
                throw CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: request.executable.path])
            }
            let process = Process()
            process.executableURL = request.executable
            process.arguments = request.arguments
            process.environment = ProcessInfo.processInfo.environment.filter {
                !$0.key.hasPrefix("DYLD_") && !$0.key.hasPrefix("__XPC_DYLD_")
            }
            process.standardInput = FileHandle.nullDevice
            try process.run()
        } else if url.pathExtension.lowercased() == "app" {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = target.arguments
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if let error { NSLog("Open application failed: %@", error.localizedDescription) }
            }
        } else {
            guard NSWorkspace.shared.open(url) else {
                throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: url.path])
            }
        }
    }
}
