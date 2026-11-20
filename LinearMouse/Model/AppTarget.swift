// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

enum AppTarget: Hashable, Codable {
    case bundle(String)
    case executable(String)
    case executableName(String)

    private enum CodingKeys: String, CodingKey { case app, processPath, processName }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard values.allKeys.count == 1, let key = values.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected one app, processPath or processName"))
        }
        let value = try values.decode(String.self, forKey: key)
        guard !value.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: key, in: values, debugDescription: "Empty application identifier")
        }
        switch key {
        case .app: self = .bundle(value)
        case .processPath: self = .executable(value)
        case .processName: self = .executableName(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .bundle(id): try values.encode(id, forKey: .app)
        case let .executable(path): try values.encode(path, forKey: .processPath)
        case let .executableName(name): try values.encode(name, forKey: .processName)
        }
    }

    func matches(_ context: Scheme.MatchContext) -> Bool {
        switch self {
        case let .bundle(id):
            if context.app == id { return true }
            // Include an app's helpers without excluding unrelated apps launched by it.
            return (context.app == nil || context.app?.hasPrefix(id + ".") == true)
                && (context.parentApp == id || context.groupApp == id)
        case let .executable(path): return context.processPath == path
        case let .executableName(name): return context.processName == name
        }
    }
}
