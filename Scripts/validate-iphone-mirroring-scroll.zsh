#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
audit_dir="$(mktemp -d /tmp/mouse-mirroring-validation.XXXXXX)"
cat > "$audit_dir/Probe.swift" <<'SWIFT'
import AppKit
import CoreGraphics
import Foundation

@main
struct MirroringScrollValidation {
    static func main() throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }
        }
        check(IPhoneMirroringScrollCompatibility.shouldUse(
            bundleIdentifier: "com.apple.ScreenContinuity", isMouse: true
        ), "Mirror mouse route was not selected")
        check(!IPhoneMirroringScrollCompatibility.shouldUse(
            bundleIdentifier: "com.apple.ScreenContinuity", isMouse: false
        ), "Trackpad must not use the compatibility route")
        check(!IPhoneMirroringScrollCompatibility.shouldUse(
            bundleIdentifier: "com.apple.Safari", isMouse: true
        ), "Other apps must retain their normal route")

        let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .line,
                            wheelCount: 3, wheel1: -2, wheel2: 3, wheel3: 1)!
        wheel.location = CGPoint(x: 120, y: 240)
        wheel.flags = [.maskShift]
        var deliveries: [(CGEvent, CGEventTapLocation)] = []
        check(IPhoneMirroringScrollCompatibility.post(wheel) { event, tap in
            deliveries.append((event, tap))
        }, "Wheel event was not rebuilt")
        let (rebuilt, tap) = deliveries[0]
        check(rebuilt !== wheel, "Must create a clean event")
        check(tap == .cghidEventTap, "Mirror scroll must use HID delivery")
        check(rebuilt.getIntegerValueField(.scrollWheelEventDeltaAxis1) == -2,
              "Reversed vertical delta was lost")
        check(rebuilt.getIntegerValueField(.scrollWheelEventDeltaAxis2) == 3,
              "Horizontal delta was lost")
        check(rebuilt.getIntegerValueField(.scrollWheelEventDeltaAxis3) == 1,
              "Third axis was lost")
        check(rebuilt.location == wheel.location && rebuilt.flags == wheel.flags,
              "Location or modifiers were changed")
        check(IPhoneMirroringScrollCompatibility.isReposted(rebuilt), "Missing loop marker")
        check(!IPhoneMirroringScrollCompatibility.isReposted(wheel), "Original event was changed")
        check(IPhoneMirroringScrollCompatibility.makeRepostedEvent(from: rebuilt) == nil,
              "A repost must not be reposted again")
        check(IPhoneMirroringScrollCompatibility.requiresProcessResolution(for: wheel),
              "Wheel event needs app resolution even with no app-specific rules")

        let smooth = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                             wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0)!
        smooth.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -0.125)
        smooth.setIntegerValueField(.scrollWheelEventScrollPhase, value: 4)
        smooth.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 3)
        let smoothOutput = IPhoneMirroringScrollCompatibility.makeRepostedEvent(from: smooth)!
        check(smoothOutput.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
              == smooth.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
              "Subpixel delta changed")
        check(smoothOutput.getIntegerValueField(.scrollWheelEventScrollPhase) == 4,
              "Zero-delta scroll ending was dropped")
        check(smoothOutput.getIntegerValueField(.scrollWheelEventMomentumPhase) == 3,
              "Momentum ending was dropped")

        let generated = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0)!
        generated.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: -6)
        generated.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: 3)
        generated.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -6)
        generated.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 3)
        generated.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(CGScrollPhase.changed.rawValue))
        let rebuiltPixel = IPhoneMirroringScrollCompatibility.makeRepostedEvent(from: generated, usesCanonicalPixelDeltas: true)!
        let reference = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                wheelCount: 3, wheel1: -6, wheel2: 3, wheel3: 0)!
        let referenceScroll = NSEvent(cgEvent: reference)!
        let rebuiltScroll = NSEvent(cgEvent: rebuiltPixel)!
        check(rebuiltScroll.hasPreciseScrollingDeltas && rebuiltScroll.scrollingDeltaY == -6
              && rebuiltScroll.scrollingDeltaX == 3, "Synthetic pixel movement did not survive reposting")
        check(rebuiltScroll.deltaY == referenceScroll.deltaY && rebuiltScroll.deltaX == referenceScroll.deltaX,
              "Legacy and pixel deltas disagree with a system-generated event")
        check(rebuiltPixel.getIntegerValueField(.scrollWheelEventDeltaAxis1)
              == reference.getIntegerValueField(.scrollWheelEventDeltaAxis1)
              && rebuiltPixel.getIntegerValueField(.scrollWheelEventDeltaAxis2)
              == reference.getIntegerValueField(.scrollWheelEventDeltaAxis2),
              "Synthetic pixel movement lost its signed legacy wheel steps")
        check(rebuiltPixel.getIntegerValueField(.scrollWheelEventScrollPhase) == Int64(CGScrollPhase.changed.rawValue),
              "Pixel normalization changed the scroll phase")

        let companion = CGEvent(source: nil)!
        companion.type = CGEventType(rawValue: 29)!
        companion.setIntegerValueField(CGEventField(rawValue: 110)!, value: 6)
        let companionOutput = IPhoneMirroringScrollCompatibility.makeRepostedEvent(from: companion)!
        check(companionOutput.type == companion.type, "Gesture companion type changed")
        check(companionOutput.getIntegerValueField(CGEventField(rawValue: 110)!) == 6,
              "Gesture companion payload changed")
        print("PASS: app/device policy, signed three-axis wheel, HID route, loop marker, subpixel phases, canonical pixel encoding")
        print("0 events posted; real iPhone Mirroring behavior is not verified by this probe")
    }
}
SWIFT

swiftc -parse-as-library -module-cache-path "$audit_dir/ModuleCache" \
    "$project_dir/LinearMouse/EventTransformer/IPhoneMirroringScrollCompatibility.swift" \
    "$audit_dir/Probe.swift" -o "$audit_dir/validate"
"$audit_dir/validate"
