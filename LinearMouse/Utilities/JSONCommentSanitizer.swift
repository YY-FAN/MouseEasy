// SPDX-License-Identifier: MIT
// Copyright (c) 2026 MouseWorkbench contributors

import Foundation

/// Accepts editable JSON with // comments, /* comments */, and optional trailing
/// commas. Removed text becomes spaces, preserving UTF-8 byte offsets and lines
/// for Foundation's subsequent JSON diagnostics. String contents are unchanged.
enum JSONCommentSanitizer {
    enum SanitizationError: LocalizedError, Equatable {
        case unterminatedBlockComment(line: Int)

        var errorDescription: String? {
            switch self {
            case let .unterminatedBlockComment(line):
                return String(format: NSLocalizedString("Unterminated block comment starting on line %lld.", comment: ""), Int64(line))
            }
        }
    }

    private enum State {
        case value
        case string
        case lineComment
        case blockComment(startLine: Int)
    }

    static func sanitize(_ source: String, allowingTrailingCommas: Bool = true) throws -> String {
        let input = Array(source.utf8)
        var output = input
        var state = State.value
        var escaped = false
        var line = 1
        var index = 0

        while index < input.count {
            let byte = input[index]
            if byte == 13 || (byte == 10 && (index == 0 || input[index - 1] != 13)) {
                line += 1
            }

            switch state {
            case .string:
                if escaped {
                    escaped = false
                } else if byte == 92 {
                    escaped = true
                } else if byte == 34 {
                    state = .value
                }
            case .lineComment:
                if byte == 10 || byte == 13 {
                    state = .value
                } else {
                    output[index] = 32
                }
            case .blockComment:
                if byte == 42, index + 1 < input.count, input[index + 1] == 47 {
                    output[index] = 32
                    output[index + 1] = 32
                    index += 2
                    state = .value
                    continue
                }
                if byte != 10 && byte != 13 {
                    output[index] = 32
                }
            case .value:
                if byte == 34 {
                    state = .string
                } else if byte == 47, index + 1 < input.count {
                    let next = input[index + 1]
                    if next == 47 || next == 42 {
                        output[index] = 32
                        output[index + 1] = 32
                        state = next == 47 ? .lineComment : .blockComment(startLine: line)
                        index += 2
                        continue
                    }
                }
            }
            index += 1
        }

        if case let .blockComment(startLine) = state {
            throw SanitizationError.unterminatedBlockComment(line: startLine)
        }
        if allowingTrailingCommas {
            removeTrailingCommas(in: &output)
        }
        return String(decoding: output, as: UTF8.self)
    }

    private static func removeTrailingCommas(in bytes: inout [UInt8]) {
        var inString = false
        var escaped = false
        var previousValueByte: UInt8?
        for index in bytes.indices {
            let byte = bytes[index]
            if inString {
                if escaped {
                    escaped = false
                } else if byte == 92 {
                    escaped = true
                } else if byte == 34 {
                    inString = false
                }
                previousValueByte = byte
                continue
            }
            if byte == 34 {
                inString = true
            } else if byte == 44 {
                var next = index + 1
                while next < bytes.count && isWhitespace(bytes[next]) {
                    next += 1
                }
                if next < bytes.count, bytes[next] == 93 || bytes[next] == 125,
                   let previousValueByte,
                   ![UInt8(123), 91, 44, 58].contains(previousValueByte) {
                    bytes[index] = 32
                }
            }
            if !isWhitespace(byte) {
                previousValueByte = byte
            }
        }
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 32 || byte == 9 || byte == 10 || byte == 13
    }
}
