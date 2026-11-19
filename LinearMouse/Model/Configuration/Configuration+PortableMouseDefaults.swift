// SPDX-License-Identifier: MIT
// Copyright (c) 2026 WheelEase contributors

import Foundation

extension Configuration {
    struct PortableMouseDefaultsSummary: Codable, Equatable {
        var changed: Bool
        var sourceSchemeCount: Int
        var ordinaryButtonMappings: Int
        var excludedDeviceSpecificMappings: Int
        var copiesScrolling: Bool
        var sourceFollowsDefaults: Bool
    }

    enum PortableMouseDefaultsError: Error, LocalizedError {
        case selectSpecificMouse
        case missingSourceProfile
        case incompatibleRuleOrder
        case noPortableSettings
        case sourceScopeTooBroad

        var errorDescription: String? {
            switch self {
            case .selectSpecificMouse:
                return NSLocalizedString("Select a configured mouse to use its settings as the defaults.", comment: "")
            case .missingSourceProfile:
                return NSLocalizedString("This mouse has no settings of its own. Select a configured mouse.", comment: "")
            case .incompatibleRuleOrder:
                return NSLocalizedString("The default mouse rule comes after a device rule. The existing order was preserved.", comment: "")
            case .noPortableSettings:
                return NSLocalizedString("This profile has no scroll or standard mouse button settings to share.", comment: "")
            case .sourceScopeTooBroad:
                return NSLocalizedString("The source rule covers several devices. Their overrides were preserved.", comment: "")
            }
        }
    }

    var hasPortableMouseDefaults: Bool {
        schemes.contains { scheme in
            scheme.isDeviceWideMouseDefaults && Self.portableProjection(of: scheme) != Scheme()
        }
    }

    func canUseAsPortableMouseDefaultsSource(_ source: DeviceMatcher) -> Bool {
        source.category == [.mouse] && source.categoryOnlyValue == nil
            && schemes.contains { Self.isDeviceWideSource($0, matching: source) }
    }

    /// Explicitly promote the selected mouse's ordinary preferences. This is
    /// never called as a reaction to the last-active device changing.
    /// Existing device/app/display overrides remain in place and in order.
    @discardableResult
    mutating func setPortableMouseDefaults(
        from source: DeviceMatcher,
        sourceFollowsDefaults: Bool = false
    ) throws -> PortableMouseDefaultsSummary {
        guard source.category == [.mouse], source.categoryOnlyValue == nil else {
            throw PortableMouseDefaultsError.selectSpecificMouse
        }
        let sourceCount = schemes.filter { Self.isDeviceWideSource($0, matching: source) }.count
        guard sourceCount > 0 else { throw PortableMouseDefaultsError.missingSourceProfile }
        if sourceFollowsDefaults {
            let broadPortableSource = schemes.contains { scheme in
                guard Self.isDeviceWideSource(scheme, matching: source),
                      Self.portableProjection(of: scheme) != Scheme() else { return false }
                return scheme.if?.first?.device.map { !Self.isPromotableSourceScope($0, source: source) } ?? true
            }
            guard !broadPortableSource else { throw PortableMouseDefaultsError.sourceScopeTooBroad }
        }

        let firstSpecific = schemes.firstIndex { scheme in
            scheme.if?.contains { condition in
                guard let matcher = condition.device, matcher.hasSpecificIdentity else { return false }
                return matcher.category?.contains(.mouse) != false
            } == true
        } ?? schemes.endIndex
        let categoryIndices = schemes.indices.filter { schemes[$0].isDeviceWideMouseDefaults }
        guard !categoryIndices.contains(where: { $0 > firstSpecific }) else {
            throw PortableMouseDefaultsError.incompatibleRuleOrder
        }

        let context = Scheme.MatchContext(deviceMatcher: source)
        var deviceWide = Scheme()
        for scheme in schemes where Self.hasOnlyDeviceConditions(scheme) && scheme.isActive(in: context) {
            scheme.merge(into: &deviceWide)
        }
        let projection = Self.portableProjection(of: deviceWide)
        guard projection != Scheme() else { throw PortableMouseDefaultsError.noPortableSettings }

        let targetIndex = categoryIndices.last
        var target = targetIndex.map { schemes[$0] }
            ?? Scheme(if: [Scheme.If(device: DeviceMatcher(category: .mouse))])
        projection.merge(into: &target)
        if let mappings = target.buttons.mappings {
            target.buttons.mappings = Self.mergedMappings(mappings)
        }
        let originalSchemes = schemes
        if targetIndex.map({ schemes[$0] != target }) ?? true {
            if let targetIndex { schemes[targetIndex] = target }
            else { schemes.insert(target, at: firstSpecific) }
        }
        if sourceFollowsDefaults {
            for index in schemes.indices {
                guard Self.isDeviceWideSource(schemes[index], matching: source),
                      let scope = schemes[index].if?.first?.device,
                      Self.isPromotableSourceScope(scope, source: source) else { continue }
                Self.removePortableOverrides(from: &schemes[index])
            }
        }
        let sourceMappings = deviceWide.buttons.mappings ?? []
        return .init(
            changed: schemes != originalSchemes,
            sourceSchemeCount: sourceCount,
            ordinaryButtonMappings: projection.buttons.mappings?.count ?? 0,
            excludedDeviceSpecificMappings: sourceMappings.filter { !Self.isPortableMapping($0) }.count,
            copiesScrolling: projection.$scrolling != nil,
            sourceFollowsDefaults: sourceFollowsDefaults
        )
    }

    private static func hasOnlyDeviceConditions(_ scheme: Scheme) -> Bool {
        guard let conditions = scheme.if else { return true }
        return !conditions.isEmpty && conditions.allSatisfy(\.hasOnlyDeviceCondition)
    }

    private static func isDeviceWideSource(_ scheme: Scheme, matching source: DeviceMatcher) -> Bool {
        guard let conditions = scheme.if, conditions.count == 1,
              let condition = conditions.first, condition.hasOnlyDeviceCondition,
              let matcher = condition.device, matcher.hasSpecificIdentity,
              matcher.category?.contains(.mouse) != false else { return false }
        return matcher.isSatisfied(by: source)
    }

    private static func isPromotableSourceScope(_ scope: DeviceMatcher, source: DeviceMatcher) -> Bool {
        if scope == source || scope == source.condition { return true }
        // Older profiles may also address this exact mouse model without its
        // serial. When explicitly promoting the source, these model aliases
        // follow the shared defaults too; vendor-only rules remain protected.
        return scope.category == [.mouse] && scope.serialNumber == nil
            && scope.vendorID != nil && scope.vendorID == source.vendorID
            && scope.productID != nil && scope.productID == source.productID
            && scope.productName != nil && scope.productName == source.productName
    }

    private static func portableProjection(of scheme: Scheme) -> Scheme {
        var projection = Scheme()
        if var scrolling = scheme.$scrolling, scrolling != Scheme.Scrolling() {
            // Existing merge methods may materialize empty implicit containers
            // while evaluating inout arguments. They carry no preference.
            if scrolling.reverse == .init() { scrolling.$reverse = nil }
            if scrolling.distance == .init() { scrolling.$distance = nil }
            if scrolling.acceleration == .init() { scrolling.$acceleration = nil }
            if scrolling.speed == .init() { scrolling.$speed = nil }
            if scrolling.smoothed == .init() { scrolling.$smoothed = nil }
            if scrolling.modifiers == .init() { scrolling.$modifiers = nil }
            // A virtual vendor button number is not an ordinary mouse input.
            if var hotkeys = scrolling.$hotkeys {
                if let acceleration = hotkeys.acceleration,
                   acceleration.type == .mouse, acceleration.code > 31 {
                    hotkeys.accelerationScale = nil
                }
                for role in Scheme.Scrolling.ScrollHotkeys.Role.allCases {
                    if let binding = hotkeys[role], binding.type == .mouse, binding.code > 31 {
                        hotkeys[role] = nil
                    }
                }
                scrolling.$hotkeys = hotkeys == .init() ? nil : hotkeys
            }
            if scrolling != .init() { projection.$scrolling = scrolling }
        }

        var buttons = Scheme.Buttons()
        let portableMappings = (scheme.buttons.mappings ?? []).filter(isPortableMapping)
        if !portableMappings.isEmpty { buttons.mappings = mergedMappings(portableMappings) }
        buttons.universalBackForward = scheme.buttons.universalBackForward
        buttons.switchPrimaryButtonAndSecondaryButtons = scheme.buttons.switchPrimaryButtonAndSecondaryButtons
        if let swipe = scheme.buttons.$swipe, swipe != .init() { buttons.$swipe = swipe }
        if let autoScroll = scheme.buttons.$autoScroll, autoScroll != .init(),
           autoScroll.trigger.map(isPortableTriggerMapping) ?? true {
            buttons.$autoScroll = autoScroll
        }
        // Pointer speed/DPI, Logitech controls, keyboard bindings and hardware
        // debouncing stay with the original device instead of being broadened.
        if buttons != .init() { projection.$buttons = buttons }
        return projection
    }

    /// Once explicitly requested, the source follows the newly promoted values
    /// too. Only the fields actually eligible for promotion are removed.
    private static func removePortableOverrides(from scheme: inout Scheme) {
        if var scrolling = scheme.$scrolling {
            scrolling.preserveContinuousScrolling = nil
            scrolling.$reverse = nil
            scrolling.$distance = nil
            scrolling.$acceleration = nil
            scrolling.$speed = nil
            scrolling.$smoothed = nil
            scrolling.$modifiers = nil
            if var hotkeys = scrolling.$hotkeys {
                let keepsVendorAcceleration = hotkeys.acceleration.map { $0.type == .mouse && $0.code > 31 } ?? false
                for role in Scheme.Scrolling.ScrollHotkeys.Role.allCases {
                    if let binding = hotkeys[role], binding.type != .mouse || binding.code <= 31 {
                        hotkeys[role] = nil
                    }
                }
                if !keepsVendorAcceleration { hotkeys.accelerationScale = nil }
                scrolling.$hotkeys = hotkeys == .init() ? nil : hotkeys
            }
            scheme.$scrolling = scrolling == .init() ? nil : scrolling
        }
        if var buttons = scheme.$buttons {
            if let mappings = buttons.mappings {
                let retained = mappings.filter { !isPortableMapping($0) }
                buttons.mappings = retained.isEmpty ? nil : retained
            }
            buttons.universalBackForward = nil
            buttons.switchPrimaryButtonAndSecondaryButtons = nil
            buttons.$swipe = nil
            if let autoScroll = buttons.$autoScroll,
               autoScroll.trigger.map(isPortableTriggerMapping) ?? true {
                buttons.$autoScroll = nil
            }
            scheme.$buttons = buttons == .init() ? nil : buttons
        }
    }

    private static func isPortableMapping(_ mapping: Scheme.Buttons.Mapping) -> Bool {
        mapping.valid && isPortableTriggerMapping(mapping)
    }

    private static func isPortableTriggerMapping(_ mapping: Scheme.Buttons.Mapping) -> Bool {
        guard let trigger = mapping.effectiveTrigger else { return false }
        return trigger.statefulButtons.allSatisfy { button in
            if case let .mouse(number) = button { return (0 ... 31).contains(number) }
            return false
        }
    }

    private static func mergedMappings(_ mappings: [Scheme.Buttons.Mapping]) -> [Scheme.Buttons.Mapping] {
        var result = [Scheme.Buttons.Mapping]()
        for var mapping in mappings {
            mapping.normalizeAsStructured()
            guard let trigger = mapping.effectiveTrigger else { continue }
            if let index = result.firstIndex(where: { $0.effectiveTrigger?.isEquivalent(to: trigger) == true }) {
                result[index].mergeOutcomes(from: mapping)
            } else { result.append(mapping) }
        }
        return result
    }
}

private extension Scheme.If {
    var hasOnlyDeviceCondition: Bool {
        app == nil && parentApp == nil && groupApp == nil && processName == nil
            && processPath == nil && display == nil
    }
}

private extension Scheme {
    var isDeviceWideMouseDefaults: Bool {
        guard let conditions = self.if, conditions.count == 1,
              let condition = conditions.first else { return false }
        return condition.hasOnlyDeviceCondition && condition.device?.categoryOnlyValue == .mouse
    }
}

private extension DeviceMatcher {
    var hasSpecificIdentity: Bool {
        vendorID != nil || productID != nil || productName != nil || serialNumber != nil
    }
}
