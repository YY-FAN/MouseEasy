// MIT License
// Keyboard action bindings for the independent local application.

import CoreGraphics
import Foundation
import KeyKit

extension Scheme.Buttons {
    struct KeyboardMapping: Codable, Equatable, Identifiable {
        enum Behavior: String, Codable, CaseIterable {
            case perform
            case `repeat`
            case hold
        }

        var id = UUID()
        var keyCode: UInt16?
        var modifiers: UInt64 = 0
        var enabled = true
        var behavior: Behavior = .perform
        var action: Mapping.Action = .arg0(.none)

        static let modifierMask = CGEventFlags([
            .maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn
        ]).rawValue

        private static let modifierKeyCodes = Set<UInt16>([54, 55, 56, 57, 58, 59, 60, 61, 62, 63])
        private static let keyNames = KeyCodeResolver()

        init() {}

        init(
            id: UUID = UUID(),
            keyCode: UInt16,
            modifiers: UInt64 = 0,
            enabled: Bool = true,
            behavior: Behavior = .perform,
            action: Mapping.Action
        ) {
            self.id = id
            self.keyCode = keyCode
            self.modifiers = modifiers & Self.modifierMask
            self.enabled = enabled
            self.behavior = behavior
            self.action = action
        }

        var isValid: Bool {
            guard let keyCode, !Self.modifierKeyCodes.contains(keyCode) else { return false }
            if behavior == .hold {
                guard case let .arg1(.keyPress(keys)) = action else { return false }
                return !keys.isEmpty
            }
            return action != .arg0(.auto)
        }

        var triggerDescription: String {
            guard let keyCode else { return NSLocalizedString("Not recorded", comment: "") }
            let flags = CGEventFlags(rawValue: modifiers)
            let symbols: [(CGEventFlags, String)] = [
                (.maskControl, "⌃"), (.maskAlternate, "⌥"), (.maskShift, "⇧"),
                (.maskCommand, "⌘"), (.maskSecondaryFn, "fn ")
            ]
            let prefix = symbols.filter { flags.contains($0.0) }.map(\.1).joined()
            let key = Self.keyNames.key(from: keyCode)?.description ?? String(format: NSLocalizedString("Key code %lld", comment: ""), Int64(keyCode))
            return prefix + key
        }

        func hasSameTrigger(as other: Self) -> Bool {
            keyCode != nil && keyCode == other.keyCode
                && (modifiers & Self.modifierMask) == (other.modifiers & Self.modifierMask)
        }

        func matches(keyCode: UInt16, modifiers: UInt64) -> Bool {
            self.keyCode == keyCode && self.modifiers & Self.modifierMask == modifiers & Self.modifierMask
        }

        static func merge(_ source: [Self], into target: inout [Self]?) {
            guard !source.isEmpty else { target = []; return }
            var merged = target ?? []
            for mapping in source {
                merged.removeAll { $0.hasSameTrigger(as: mapping) }
                merged.append(mapping)
            }
            target = merged
        }

        private enum CodingKeys: String, CodingKey {
            case id, keyCode, modifiers, enabled, behavior, action
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            keyCode = try container.decodeIfPresent(UInt16.self, forKey: .keyCode)
            modifiers = (try container.decodeIfPresent(UInt64.self, forKey: .modifiers) ?? 0) & Self.modifierMask
            enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            behavior = try container.decodeIfPresent(Behavior.self, forKey: .behavior) ?? .perform
            action = try container.decode(Mapping.Action.self, forKey: .action)
        }
    }
}
