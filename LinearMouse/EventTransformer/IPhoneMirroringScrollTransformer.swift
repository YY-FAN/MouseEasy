// MIT License
// Independently implemented for this build. No Mos implementation is included.

import CoreGraphics
import Dispatch
import IOKit.hidsystem

/// Final wheel stage, after reverse, modifier actions, and any smooth input
/// consumption. Returning nil avoids delivering an unmodified duplicate.
final class IPhoneMirroringScrollTransformer: EventTransformer {
    var handlesPointerMotion: Bool { false }
    private let preservesSourceEvent: Bool
    private let preserveContinuousScrolling: Bool
    private let reversesDirection: Bool
    private let eventSink: (CGEvent, CGEventTapLocation) -> Void

    init(preservesSourceEvent: Bool = false, preserveContinuousScrolling: Bool = false,
         reversesDirection: Bool = false, eventSink: @escaping (CGEvent, CGEventTapLocation) -> Void) {
        self.preservesSourceEvent = preservesSourceEvent
        self.preserveContinuousScrolling = preserveContinuousScrolling
        self.reversesDirection = reversesDirection
        self.eventSink = eventSink
    }

    func transform(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent? {
        guard event.type == .scrollWheel,
              context.device?.category == .mouse,
              !IPhoneMirroringScrollCompatibility.isReposted(event) else {
            return event
        }
        let native = preserveContinuousScrolling && ScrollWheelEventView(event).continuous
        if native && !reversesDirection { return event }
        return IPhoneMirroringScrollCompatibility.post(event, preservesSourceEvent: preservesSourceEvent || native,
                                                       using: eventSink) ? nil : event
    }
}

/// Default vertical scrolling repeats wheel events. Horizontal and reversed
/// scrolling keep the original hardware event and scale its travel in place.
final class IPhoneMirroringSystemWheelTransformer: EventTransformer {
    var handlesPointerMotion: Bool { false }
    private let reverse: Bool
    private let multiplier: Double
    private let verticalSwitchKeys: CGEventFlags
    private let horizontalSwitchKeys: CGEventFlags
    private let nativeShiftVertical: Bool
    private let nativeShiftHorizontal: Bool
    private var pendingQuarters = 0
    private var previousRepeatSign: FloatingPointSign?
    private var verticalRounding = Rounding()
    private var horizontalRounding = Rounding()
    private let eventSink: (CGEvent, CGEventTapLocation) -> Void

    init(settings: MirrorScrollSettings, modifiers: Scheme.Scrolling.Bidirectional<Scheme.Scrolling.Modifiers> = .init(),
         eventSink: @escaping (CGEvent, CGEventTapLocation) -> Void) {
        reverse = settings.reversesSystemWheel
        multiplier = settings.wheelMultiplier
        verticalSwitchKeys = Self.axisSwitchKeys(modifiers.vertical)
        horizontalSwitchKeys = Self.axisSwitchKeys(modifiers.horizontal)
        nativeShiftVertical = (modifiers.vertical?.shift ?? .auto) == .auto
        nativeShiftHorizontal = (modifiers.horizontal?.shift ?? .auto) == .auto
        self.eventSink = eventSink
    }

    private static func axisSwitchKeys(_ modifiers: Scheme.Scrolling.Modifiers?) -> CGEventFlags {
        var keys = CGEventFlags()
        for (flag, action) in modifiers?.keyedActions ?? [] where action == .alterOrientation {
            keys.insert(flag)
        }
        return keys
    }

    func transform(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent? {
        guard event.type == .scrollWheel, context.device?.category == .mouse,
              event.getIntegerValueField(.eventSourceUnixProcessID) == 0,
              !event.isLinearMouseSyntheticEvent, !IPhoneMirroringScrollCompatibility.isReposted(event) else {
            return event
        }

        let held = event.flags.intersection([.maskShift, .maskCommand, .maskControl, .maskAlternate, .maskSecondaryFn])
        if held.isEmpty {
            guard reverse || multiplier > 1 else { return event }
        } else {
            guard held.rawValue.nonzeroBitCount == 1,
                  held == .maskShift || verticalSwitchKeys.contains(held) || horizontalSwitchKeys.contains(held) else { return event }
        }
        let view = ScrollWheelEventView(event)
        guard view.scrollPhase == nil, view.momentumPhase == .none,
              event.getIntegerValueField(.scrollWheelEventDeltaAxis3) == 0,
              event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis3) == 0,
              event.getDoubleValueField(.scrollWheelEventPointDeltaAxis3) == 0 else { return event }
        let y = WheelAxis.vertical.distance(event, view)
        let x = WheelAxis.horizontal.distance(event, view)
        guard let distance = y ?? x, y == nil || x == nil else { return event }
        let vertical = y != nil
        if !held.isEmpty {
            if (vertical ? verticalSwitchKeys : horizontalSwitchKeys).contains(held) {
                swapAxes(event, view: view, key: held)
                if vertical {
                    WheelAxis.horizontal.scale(event, view, by: multiplier, distance: distance, rounding: &horizontalRounding)
                } else {
                    WheelAxis.vertical.scale(event, view, by: multiplier, distance: distance, rounding: &verticalRounding)
                }
            } else if held == .maskShift, vertical ? nativeShiftVertical : nativeShiftHorizontal {
                // macOS or the receiver handles Shift. Scale the source without swapping it again.
                let source = vertical ? WheelAxis.vertical : .horizontal
                source.scale(event, view, by: multiplier, distance: distance, rounding: &horizontalRounding)
            }
            return event
        }
        if !vertical {
            WheelAxis.horizontal.scale(event, view, by: multiplier, distance: distance, rounding: &horizontalRounding)
            return event
        }
        guard !view.continuous else { return event }
        if reverse {
            WheelAxis.vertical.scale(event, view, by: -multiplier, distance: distance, rounding: &verticalRounding)
            return event
        }

        guard view.deltaYFixedPt != 0 || view.deltaYPt != 0 || view.deltaY != 0 else { return event }
        if distance.sign != previousRepeatSign { pendingQuarters = 0 }
        previousRepeatSign = distance.sign
        pendingQuarters += Int((multiplier - 1) * 4)
        let extraEvents = pendingQuarters / 4
        pendingQuarters %= 4
        for _ in 0 ..< extraEvents {
            guard let copy = event.copy() else { break }
            copy.setIntegerValueField(.eventSourceUserData, value: IPhoneMirroringScrollCompatibility.repostedEventMarker)
            copy.timestamp = DispatchTime.now().uptimeNanoseconds
            eventSink(copy, .cghidEventTap)
        }
        return event
    }

    private func swapAxes(_ event: CGEvent, view: ScrollWheelEventView, key: CGEventFlags) {
        let rawX = event.getDoubleValueField(.scrollWheelEventRawDeltaAxis2)
        let rawY = event.getDoubleValueField(.scrollWheelEventRawDeltaAxis1)
        let acceleratedX = event.getDoubleValueField(.scrollWheelEventAcceleratedDeltaAxis2)
        let acceleratedY = event.getDoubleValueField(.scrollWheelEventAcceleratedDeltaAxis1)
        // Swap the original wheel's line, pixel and HID deltas, then its independent raw fields.
        view.swapXY()
        event.setDoubleValueField(.scrollWheelEventRawDeltaAxis1, value: rawX)
        event.setDoubleValueField(.scrollWheelEventRawDeltaAxis2, value: rawY)
        event.setDoubleValueField(.scrollWheelEventAcceleratedDeltaAxis1, value: acceleratedX)
        event.setDoubleValueField(.scrollWheelEventAcceleratedDeltaAxis2, value: acceleratedY)
        // Exactly one shortcut key is down. Remove its generic and sided flags from
        // this wheel event so the receiver cannot apply the shortcut a second time.
        let sideBits = NX_DEVICELALTKEYMASK | NX_DEVICERALTKEYMASK | NX_DEVICELSHIFTKEYMASK | NX_DEVICERSHIFTKEYMASK |
            NX_DEVICELCTLKEYMASK | NX_DEVICERCTLKEYMASK | NX_DEVICELCMDKEYMASK | NX_DEVICERCMDKEYMASK
        event.flags.subtract(key.union(CGEventFlags(rawValue: UInt64(sideBits))))
    }

    private struct Rounding {
        var sign: FloatingPointSign?
        var lines = 0.0
        var points = 0.0
    }

    private struct WheelAxis {
        let line, fixed, point, raw, accelerated: CGEventField
        let hid: ReferenceWritableKeyPath<ScrollWheelEventView, Double>

        static let vertical = Self(line: .scrollWheelEventDeltaAxis1, fixed: .scrollWheelEventFixedPtDeltaAxis1,
                                   point: .scrollWheelEventPointDeltaAxis1, raw: .scrollWheelEventRawDeltaAxis1,
                                   accelerated: .scrollWheelEventAcceleratedDeltaAxis1, hid: \.ioHidScrollY)
        static let horizontal = Self(line: .scrollWheelEventDeltaAxis2, fixed: .scrollWheelEventFixedPtDeltaAxis2,
                                     point: .scrollWheelEventPointDeltaAxis2, raw: .scrollWheelEventRawDeltaAxis2,
                                     accelerated: .scrollWheelEventAcceleratedDeltaAxis2, hid: \.ioHidScrollX)

        func distance(_ event: CGEvent, _ view: ScrollWheelEventView) -> Double? {
            for field in [fixed, point, line, accelerated, raw] {
                let delta = event.getDoubleValueField(field)
                if delta != 0 { return delta }
            }
            let deviceDelta = view[keyPath: hid]
            return deviceDelta == 0 ? nil : deviceDelta
        }

        func scale(_ event: CGEvent, _ view: ScrollWheelEventView, by factor: Double, distance: Double, rounding: inout Rounding) {
            guard factor != 1 else { return }
            let sign = (distance * factor).sign
            if rounding.sign != sign { rounding = Rounding(sign: sign) }
            // Read all channels before writing. Hardware and logical travel may have opposite signs.
            let lines = wholeUnits(Double(event.getIntegerValueField(line)) * factor, remainder: &rounding.lines)
            let points = wholeUnits(event.getDoubleValueField(point) * factor, remainder: &rounding.points)
            let fixedValue = event.getDoubleValueField(fixed) * factor
            let rawValue = event.getDoubleValueField(raw) * factor
            let acceleratedValue = event.getDoubleValueField(accelerated) * factor
            let deviceDelta = view[keyPath: hid] * factor
            event.setIntegerValueField(line, value: Int64(lines))
            event.setDoubleValueField(fixed, value: fixedValue)
            event.setDoubleValueField(point, value: Double(points))
            event.setDoubleValueField(raw, value: rawValue)
            event.setDoubleValueField(accelerated, value: acceleratedValue)
            view[keyPath: hid] = deviceDelta
        }
    }

    private static func wholeUnits(_ displacement: Double, remainder: inout Double) -> Int32 {
        let total = displacement + remainder
        let whole = total.rounded(.towardZero)
        remainder = total - whole
        return Int32(min(Double(Int32.max), max(Double(Int32.min), whole)))
    }
}
