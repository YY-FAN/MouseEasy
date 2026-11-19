// SPDX-License-Identifier: MIT
// Copyright (c) 2026 MouseWorkbench contributors

import Foundation

@main
enum JSONCommentSanitizerTests {
    static func require(_ condition: @autoclosure () -> Bool, _ description: String) {
        precondition(condition(), description)
    }

    static func object(_ source: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(JSONCommentSanitizer.sanitize(source).utf8)) as! [String: Any]
    }

    static func main() throws {
        let configuration = """
        {
          // custom mouse settings
          "enabled": true,
          "devices": [1, 2, /* retained position */],
        }
        """
        let parsed = try object(configuration)
        require(parsed["enabled"] as? Bool == true, "Boolean setting retained")
        require(parsed["devices"] as? [Int] == [1, 2], "Nested array trailing comma accepted")
        let sanitized = try JSONCommentSanitizer.sanitize(configuration)
        require(Array(sanitized.utf8).count == Array(configuration.utf8).count, "Byte positions preserved")
        require(sanitized.filter { $0 == "\n" }.count == configuration.filter { $0 == "\n" }.count, "Line count preserved")

        let literals = try object(#"{"url":"https://example.com/path//x","text":"a\"/* literal */","comma":",]"} // comment"#)
        require(literals["url"] as? String == "https://example.com/path//x", "URL preserved")
        require(literals["text"] as? String == "a\"/* literal */", "Escaped quote and comment marker preserved")
        require(literals["comma"] as? String == ",]", "Trailing-comma-like string preserved")

        let unicode = "/* 中文🙂 */\r\n{\r\n\"名字\":\"鼠标\",// 注释\r\n\"value\":1,\r\n}"
        let unicodeObject = try object(unicode)
        require(unicodeObject["名字"] as? String == "鼠标", "Unicode strings preserved")
        let unicodeSanitized = try JSONCommentSanitizer.sanitize(unicode)
        require(unicodeSanitized.utf8.count == unicode.utf8.count, "Unicode comment byte offsets preserved")
        require(unicodeSanitized.components(separatedBy: "\r\n").count == unicode.components(separatedBy: "\r\n").count, "CRLF retained")

        for invalid in ["{,}", "[1,,]", "{\"x\":,}"] {
            let text = try JSONCommentSanitizer.sanitize(invalid)
            require((try? JSONSerialization.jsonObject(with: Data(text.utf8))) == nil, "Malformed comma rejected: \(invalid)")
        }
        let strictCommas = try JSONCommentSanitizer.sanitize("[1,]", allowingTrailingCommas: false)
        require(strictCommas == "[1,]", "Strict mode keeps trailing comma for decoder")

        do {
            _ = try JSONCommentSanitizer.sanitize("{}\r\n\r\n/* unfinished")
            preconditionFailure("Unclosed block comment accepted")
        } catch let error as JSONCommentSanitizer.SanitizationError {
            require(error == .unterminatedBlockComment(line: 3), "Opening comment line reported")
        }
        let quoted = try object(#"{"x":"/* not a comment","y":"\\"}"#)
        require(quoted["x"] as? String == "/* not a comment", "Unclosed marker inside string accepted")
        require(quoted["y"] as? String == "\\", "Escaped backslash preserved")
        print("PASS: independent JSONC comments, strings, positions, trailing commas, and invalid input checks")
    }
}
