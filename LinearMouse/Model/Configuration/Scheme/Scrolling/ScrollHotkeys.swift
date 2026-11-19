// MIT License

import CoreGraphics
import Foundation

extension Scheme.Scrolling {
    struct ScrollHotkeys: Codable, Equatable, ImplicitInitable {
        enum Role: String, CaseIterable, Identifiable {
            case acceleration, alterOrientation, bypassSmoothing
            var id: String { rawValue }

            var title: String {
                switch self {
                case .acceleration: NSLocalizedString("Accelerate scrolling", comment: "")
                case .alterOrientation: NSLocalizedString("Switch scroll axis", comment: "")
                case .bypassSmoothing: NSLocalizedString("Bypass smoothing", comment: "")
                }
            }
        }

        struct Binding: Codable, Equatable, Hashable {
            enum InputType: String, Codable { case keyboard, mouse }
            var type: InputType
            var code: UInt16
            var modifiers: UInt64 = 0
            var enabled: Bool? = true
            var label: String?

            var isEnabled: Bool { enabled ?? true }
            static var disabled: Self { .init(type: .keyboard, code: 0, enabled: false) }
            static let relevantModifiers: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]

            func matches(modifierFlags: CGEventFlags) -> Bool {
                modifierFlags.intersection(Self.relevantModifiers).rawValue
                    == (modifiers & Self.relevantModifiers.rawValue)
            }
        }

        var acceleration: Binding?
        var alterOrientation: Binding?
        var bypassSmoothing: Binding?
        var accelerationScale: Decimal?

        init() {}

        subscript(role: Role) -> Binding? {
            get {
                switch role {
                case .acceleration: acceleration
                case .alterOrientation: alterOrientation
                case .bypassSmoothing: bypassSmoothing
                }
            }
            set {
                switch role {
                case .acceleration: acceleration = newValue
                case .alterOrientation: alterOrientation = newValue
                case .bypassSmoothing: bypassSmoothing = newValue
                }
            }
        }

        var hasEnabledBinding: Bool { Role.allCases.contains { self[$0]?.isEnabled == true } }
        var resolvedAccelerationScale: Double {
            let value = accelerationScale.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 5
            return value.isFinite ? min(20, max(0.1, value)) : 5
        }

        func merge(into target: inout Self) {
            for role in Role.allCases {
                if let binding = self[role] { target[role] = binding }
            }
            if let accelerationScale { target.accelerationScale = accelerationScale }
        }
    }
}

extension Scheme.Scrolling.ScrollHotkeys.Binding {
    private enum CodingKeys: String, CodingKey { case type, code, modifiers, enabled, label }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(InputType.self, forKey: .type)
        code = try container.decode(UInt16.self, forKey: .code)
        modifiers = try container.decodeIfPresent(UInt64.self, forKey: .modifiers) ?? 0
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
        label = try container.decodeIfPresent(String.self, forKey: .label)
    }
}
