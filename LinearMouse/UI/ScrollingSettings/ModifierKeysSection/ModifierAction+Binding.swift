// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import SwiftUI

struct WheelModifierKey: Hashable {
    typealias Modifiers = Scheme.Scrolling.Modifiers

    let label: String
    let action: WritableKeyPath<Modifiers, Modifiers.Action?>

    static let all = [
        Self(label: "⌃ Ctrl", action: \.control),
        Self(label: "⇧ Shift", action: \.shift),
        Self(label: "⌥ Option", action: \.option),
        Self(label: "⌘ Cmd", action: \.command)
    ]
}

extension Scheme.Scrolling.Modifiers {
    var axisSwitchKeys: [WheelModifierKey] {
        get { WheelModifierKey.all.filter { self[keyPath: $0.action] == .alterOrientation } }
        set {
            for key in WheelModifierKey.all {
                if newValue.contains(key) {
                    self[keyPath: key.action] = .alterOrientation
                } else if self[keyPath: key.action] == .alterOrientation {
                    self[keyPath: key.action] = .auto
                }
            }
        }
    }
}

extension Binding where Value == Scheme.Scrolling.Modifiers.Action? {
    var kind: Binding<Scheme.Scrolling.Modifiers.Action.Kind> {
        Binding<Scheme.Scrolling.Modifiers.Action.Kind>(
            get: {
                wrappedValue?.kind ?? .defaultAction
            },
            set: {
                wrappedValue = Scheme.Scrolling.Modifiers.Action(kind: $0)
            }
        )
    }

    var speedFactor: Binding<Double> {
        Binding<Double>(
            get: {
                guard case let .changeSpeed(speedFactor) = wrappedValue else {
                    return 1
                }

                return speedFactor.asTruncatedDouble
            },
            set: { value in
                if value < 0 {
                    wrappedValue = .changeSpeed(scale: Decimal(value).rounded(0))
                } else if 0 ..< 0.1 ~= value {
                    wrappedValue = .changeSpeed(scale: Decimal(value * 20).rounded(0) / 20)
                } else if 0.1 ..< 1 ~= value {
                    wrappedValue = .changeSpeed(scale: Decimal(value).rounded(1))
                } else {
                    wrappedValue = .changeSpeed(scale: Decimal(value * 2).rounded(0) / 2)
                }
            }
        )
    }
}

extension Scheme.Scrolling.Modifiers.Action.Kind {
    @ViewBuilder
    func label(for direction: Scheme.Scrolling.BidirectionalDirection) -> some View {
        switch self {
        case .defaultAction:
            Text("Inherit default action")
        case .ignore:
            Text("Ignore this modifier")
        case .noAction:
            Text("Do nothing")
        case .alterOrientation:
            if direction == .vertical {
                Text("Scroll horizontally")
            } else {
                Text("Scroll vertically")
            }
        case .changeSpeed:
            Text("Change scroll speed")
        case .bypassSmoothing:
            Text("Bypass smoothing")
        case .zoom:
            Text("Zoom with shortcuts")
        case .zoomReversed:
            Text("Zoom with shortcuts (reversed)")
        case .pinchZoom:
            Text("Smooth zoom")
        case .pinchZoomReversed:
            Text("Smooth zoom (reversed)")
        }
    }
}
