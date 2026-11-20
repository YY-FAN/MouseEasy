// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import SwiftUI

extension Scheme.Scrolling {
    struct Smoothed: Equatable, Codable, ImplicitInitable {
        struct PresetProfile: Equatable {
            var response: Double
            var inputExponent: Double
            var accelerationGain: Double
            var decay: Double
            var velocityScale: Double
        }

        enum Preset: String, Codable, Equatable, CaseIterable, Identifiable {
            var id: Self {
                self
            }

            case custom
            case linear
            case easeIn
            case easeOut
            case easeInOut
            case quadratic
            case cubic
            case quartic
            case easeOutCubic
            case easeInOutCubic
            case easeOutQuartic
            case easeInOutQuartic
            case smooth
            case flow
        }

        var enabled: Bool?
        var preset: Preset?
        var response: Decimal?
        var speed: Decimal?
        var acceleration: Decimal?
        var inertia: Decimal?
        var minimumStep: Decimal?
        var duration: Decimal?
        var durationEnabled: Bool?
        var bouncing: Bool?

        init() {}

        init(
            enabled: Bool? = nil,
            preset: Preset? = nil,
            response: Decimal? = nil,
            speed: Decimal? = nil,
            acceleration: Decimal? = nil,
            inertia: Decimal? = nil,
            minimumStep: Decimal? = nil,
            duration: Decimal? = nil,
            durationEnabled: Bool? = nil,
            bouncing: Bool? = nil
        ) {
            self.enabled = enabled
            self.preset = preset
            self.response = response
            self.speed = speed
            self.acceleration = acceleration
            self.inertia = inertia
            self.minimumStep = minimumStep
            self.duration = duration
            self.durationEnabled = durationEnabled
            self.bouncing = bouncing
        }
    }
}

extension Scheme.Scrolling.Smoothed {
    static let responseRange: ClosedRange<Double> = 0.0 ... 2.0
    static let speedRange: ClosedRange<Double> = 0.0 ... 8.0
    static let accelerationRange: ClosedRange<Double> = 0.0 ... 8.0
    static let inertiaRange: ClosedRange<Double> = 0.0 ... 8.0
    static let minimumStepRange: ClosedRange<Double> = 0.0 ... 120.0
    static let durationRange: ClosedRange<Double> = 0.0 ... 2.0

    var usesCustomDuration: Bool {
        durationEnabled ?? (duration != nil)
    }

    /// A point-distance floor for a complete wheel notch. High-resolution wheel
    /// packets divide this floor by their hardware multiplier before use.
    func normalizedWheelInput(_ input: Double, resolutionMultiplier: Int = 1) -> Double {
        guard input != 0 else { return 0 }
        let configuredStep = minimumStep?.asTruncatedDouble ?? 0
        guard configuredStep.isFinite else { return input }
        let floor = configuredStep.clamped(to: Self.minimumStepRange) / Double(max(resolutionMultiplier, 1))
        return input.sign == .minus ? -max(abs(input), floor) : max(abs(input), floor)
    }

    var resolvedPreset: Preset {
        preset ?? .defaultPreset
    }

    var resolvedPresetProfile: PresetProfile {
        resolvedPreset.profile
    }

    var isEnabled: Bool {
        enabled ?? true
    }

    var allowsBouncing: Bool {
        bouncing ?? true
    }

    func merge(into smoothed: inout Self) {
        if let enabled {
            smoothed.enabled = enabled
        }

        if let preset {
            smoothed.preset = preset
        }

        if let response {
            smoothed.response = response
        }

        if let speed {
            smoothed.speed = speed
        }

        if let acceleration {
            smoothed.acceleration = acceleration
        }

        if let inertia {
            smoothed.inertia = inertia
        }

        if let minimumStep {
            smoothed.minimumStep = minimumStep
        }

        if let duration {
            smoothed.duration = duration
        }

        if let durationEnabled {
            smoothed.durationEnabled = durationEnabled
        }

        if let bouncing {
            smoothed.bouncing = bouncing
        }
    }

    func merge(into smoothed: inout Self?) {
        if smoothed == nil {
            smoothed = Self()
        }

        merge(into: &smoothed!)
    }
}

extension Scheme.Scrolling.Smoothed.Preset {
    struct Presentation: Equatable {
        var title: LocalizedStringKey
        var subtitle: LocalizedStringKey
        var showsEditableBadge = false
    }

    static var defaultPreset: Self {
        .easeInOut
    }

    static var recommendedCases: [Self] {
        [
            .flow,
            .easeInOut,
            .easeIn,
            .easeOut,
            .linear,
            .quadratic,
            .cubic,
            .easeOutCubic,
            .easeInOutCubic,
            .quartic,
            .easeOutQuartic,
            .easeInOutQuartic,
            .smooth,
            .custom
        ]
    }

    var profile: Scheme.Scrolling.Smoothed.PresetProfile {
        switch self {
        case .custom:
            return .init(response: 0.64, inputExponent: 1.00, accelerationGain: 0.10, decay: 0.89, velocityScale: 32)
        case .linear:
            return .init(response: 0.94, inputExponent: 0.96, accelerationGain: 0.04, decay: 0.83, velocityScale: 34)
        case .easeIn:
            return .init(response: 0.34, inputExponent: 1.18, accelerationGain: 0.08, decay: 0.93, velocityScale: 24)
        case .easeOut:
            return .init(response: 0.90, inputExponent: 0.92, accelerationGain: 0.08, decay: 0.84, velocityScale: 34)
        case .easeInOut:
            return .init(response: 0.68, inputExponent: 1.06, accelerationGain: 0.10, decay: 0.89, velocityScale: 31)
        case .quadratic:
            return .init(response: 0.58, inputExponent: 1.12, accelerationGain: 0.12, decay: 0.88, velocityScale: 33)
        case .cubic:
            return .init(response: 0.52, inputExponent: 1.18, accelerationGain: 0.14, decay: 0.89, velocityScale: 35)
        case .quartic:
            return .init(response: 0.46, inputExponent: 1.24, accelerationGain: 0.16, decay: 0.90, velocityScale: 37)
        case .easeOutCubic:
            return .init(response: 0.94, inputExponent: 0.86, accelerationGain: 0.08, decay: 0.82, velocityScale: 35)
        case .easeInOutCubic:
            return .init(response: 0.62, inputExponent: 1.12, accelerationGain: 0.12, decay: 0.89, velocityScale: 33)
        case .easeOutQuartic:
            return .init(response: 0.98, inputExponent: 0.80, accelerationGain: 0.08, decay: 0.80, velocityScale: 36)
        case .easeInOutQuartic:
            return .init(response: 0.56, inputExponent: 1.18, accelerationGain: 0.14, decay: 0.90, velocityScale: 34)
        case .smooth:
            return .init(response: 0.80, inputExponent: 0.98, accelerationGain: 0.06, decay: 0.93, velocityScale: 33)
        case .flow:
            return .init(response: 0.86, inputExponent: 1.00, accelerationGain: 0.05, decay: 0.91, velocityScale: 30)
        }
    }

    var presentation: Presentation {
        switch self {
        case .custom:
            return .init(
                title: "Custom",
                subtitle: "Use this when you want to fine-tune the feel yourself.",
                showsEditableBadge: true
            )
        case .linear:
            return .init(title: "Linear", subtitle: "Direct and immediate, with a short controlled tail.")
        case .easeIn:
            return .init(title: "Ease In", subtitle: "Soft start that builds momentum as you keep scrolling.")
        case .easeOut:
            return .init(title: "Ease Out", subtitle: "Fast initial response that settles quickly.")
        case .easeInOut:
            return .init(title: "Ease In Out", subtitle: "Balanced ramp-up and release.")
        case .quadratic:
            return .init(title: "Ease In Quad", subtitle: "Ease-in quad with a noticeable but manageable ramp-up.")
        case .cubic:
            return .init(title: "Ease In Cubic", subtitle: "Ease-in cubic with a stronger progressive build.")
        case .quartic:
            return .init(title: "Ease In Quartic", subtitle: "Ease-in quartic with the strongest front-loaded ramp.")
        case .easeOutCubic:
            return .init(title: "Ease Out Cubic", subtitle: "Fast cubic pickup that settles into a shorter tail.")
        case .easeInOutCubic:
            return .init(title: "Ease In Out Cubic", subtitle: "Cubic ease-in-out with a weightier middle section.")
        case .easeOutQuartic:
            return .init(title: "Ease Out Quartic", subtitle: "Very fast quartic pickup with a crisp release.")
        case .easeInOutQuartic:
            return .init(title: "Ease In Out Quartic", subtitle: "Quartic ease-in-out with the boldest mid-curve.")
        case .smooth:
            return .init(title: "Smooth", subtitle: "Stable and fluid, with a longer carry than Linear.")
        case .flow:
            return .init(title: "Flow", subtitle: "Respond quickly to the wheel and stop smoothly.")
        }
    }

    var defaultConfiguration: Scheme.Scrolling.Smoothed {
        let values: (response: Decimal, speed: Decimal, acceleration: Decimal, inertia: Decimal)

        switch self {
        case .custom:
            values = (0.68, 1.00, 1.00, 0.80)
        case .linear:
            values = (0.92, 1.00, 0.78, 0.44)
        case .easeIn:
            values = (0.38, 0.92, 0.86, 1.00)
        case .easeOut:
            values = (0.88, 1.02, 0.94, 0.42)
        case .easeInOut:
            values = (0.68, 1.02, 1.10, 0.74)
        case .quadratic:
            values = (0.58, 1.04, 1.18, 0.72)
        case .cubic:
            values = (0.54, 1.08, 1.24, 0.76)
        case .quartic:
            values = (0.48, 1.12, 1.32, 0.82)
        case .easeOutCubic:
            values = (0.94, 1.06, 0.92, 0.42)
        case .easeInOutCubic:
            values = (0.62, 1.06, 1.20, 0.78)
        case .easeOutQuartic:
            values = (0.98, 1.10, 0.90, 0.38)
        case .easeInOutQuartic:
            values = (0.56, 1.10, 1.28, 0.82)
        case .smooth:
            values = (0.80, 1.00, 0.88, 0.92)
        case .flow:
            values = (0.82, 1.00, 0.95, 0.85)
        }

        return .init(
            enabled: true,
            preset: self,
            response: values.response,
            speed: values.speed,
            acceleration: values.acceleration,
            inertia: values.inertia,
            minimumStep: self == .flow ? 24 : nil,
            duration: self == .flow ? Decimal(string: "0.32") : nil,
            durationEnabled: self == .flow ? true : nil,
            bouncing: self != .flow
        )
    }
}

struct MirrorScrollSettings: Codable, Equatable {
    enum WheelMode: String, Codable, CaseIterable {
        case smooth, reversed, system

        var title: String {
            switch self {
            case .smooth: NSLocalizedString("Smooth scrolling", comment: "")
            case .reversed: NSLocalizedString("Reverse only", comment: "")
            case .system: NSLocalizedString("System wheel", comment: "")
            }
        }
    }

    // Slow, distinct wheel notches keep enough movement even at high hardware resolution.
    static let minimumWheelNotchInput = 24.0
    static let wheelMultipliers: [Double] = [1, 2, 3, 4, 5]

    var enabled: Bool?
    var speed: Double?
    var response: Double?
    var duration: Double?
    var frequency: Int?
    var nativeWheelEvents: Bool?
    var wheelMode: WheelMode?
    var repeatSystemWheel: Bool?
    var systemReverseVertical: Bool?
    // Retained for older builds. This adjusted event distance rather than event count.
    var systemWheelDistance: Double?
    var systemWheelMultiplier: Double?

    var isEnabled: Bool { enabled ?? true }
    var resolvedWheelMode: WheelMode { wheelMode ?? (nativeWheelEvents == true ? .reversed : .smooth) }
    var reversesSystemWheel: Bool { isEnabled && systemReverseVertical == true }
    var wheelMultiplier: Double {
        guard isEnabled else { return 1 }
        if let systemWheelMultiplier {
            // Keep the exact speed of an existing installation until the user changes it.
            if systemWheelMultiplier == 1.25 || systemWheelMultiplier == 1.5 { return systemWheelMultiplier }
            return Self.wheelMultipliers.contains(systemWheelMultiplier) ? systemWheelMultiplier : 1
        }
        return resolvedWheelMode == .system && repeatSystemWheel == true ? 2 : 1
    }
    var hz: Int { frequency == 30 ? 30 : 60 }
    var scrollSpeed: Double { (speed ?? 1.25).clamped(to: 0.1 ... 4) }
    var responsiveness: Double { (response ?? 0.62).clamped(to: 0 ... 2) }
    var tail: Double { (duration ?? 0.18).clamped(to: 0 ... 0.8) }

    var tuning: Scheme.Scrolling.Smoothed {
        .init(enabled: true, preset: .flow, response: Decimal(responsiveness), speed: Decimal(scrollSpeed),
              acceleration: 0, minimumStep: 0, duration: Decimal(tail), durationEnabled: true, bouncing: false)
    }
}
