// SPDX-License-Identifier: MIT
// Copyright (c) 2026 MouseWorkbench contributors

import Foundation

extension Scheme.Buttons.Mapping.Action {
    struct OpenTarget: Codable, Equatable, Hashable {
        enum Mode: String, Codable { case open, execute }
        var path: String = ""
        var arguments: [String] = []
        var mode: Mode = .open

        var fileURL: URL {
            URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }

        struct ExecutionRequest: Equatable {
            let executable: URL
            let arguments: [String]
        }

        func executionRequest() -> ExecutionRequest {
            if FileManager.default.isExecutableFile(atPath: fileURL.path) {
                return .init(executable: fileURL, arguments: arguments)
            }
            if let handle = try? FileHandle(forReadingFrom: fileURL) {
                defer { try? handle.close() }
                if let data = try? handle.read(upToCount: 4096),
                   let prefix = String(data: data, encoding: .utf8),
                   let firstLine = prefix.components(separatedBy: .newlines).first,
                   firstLine.hasPrefix("#!") {
                    let words = firstLine.dropFirst(2).split(whereSeparator: { $0.isWhitespace }).map(String.init)
                    if let interpreter = words.first, interpreter.hasPrefix("/") {
                        return .init(executable: URL(fileURLWithPath: interpreter),
                            arguments: Array(words.dropFirst()) + [fileURL.path] + arguments)
                    }
                }
            }
            switch fileURL.pathExtension.lowercased() {
            case "sh":
                return .init(executable: URL(fileURLWithPath: "/bin/sh"), arguments: [fileURL.path] + arguments)
            case "command", "zsh":
                return .init(executable: URL(fileURLWithPath: "/bin/zsh"), arguments: [fileURL.path] + arguments)
            case "scpt", "applescript":
                return .init(executable: URL(fileURLWithPath: "/usr/bin/osascript"), arguments: [fileURL.path] + arguments)
            default:
                return .init(executable: fileURL, arguments: arguments)
            }

        }
    }
}
