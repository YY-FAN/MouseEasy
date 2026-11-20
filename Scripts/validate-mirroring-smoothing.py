#!/usr/bin/env python3
"""Exercise production mirror smoothing with a clock and sink, never post input.

Only app/device scheduling dependencies are replaced. Scroll model, engine,
transformer, CGEvent views, phase construction and mirror event rebuilding are
compiled from production sources. OSLog bundle IDs use a fixed test identifier.
"""
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
work = Path(tempfile.mkdtemp(prefix="mouse-mirror-smoothing-"))
sdk = Path("/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk")
if not sdk.exists():
    sdk = Path(subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip())
target = f"{platform.machine()}-apple-macosx{'11.0' if platform.machine() == 'arm64' else '10.15'}"
base = ["swiftc", "-sdk", str(sdk), "-target", target, "-module-cache-path", str(work / "cache")]
gesture = sorted((root / "Modules/GestureKit/Sources/GestureKit").glob("*.swift"))
subprocess.run(base + ["-swift-version", "6", "-emit-library", "-emit-module", "-module-name", "GestureKit",
    "-emit-module-path", str(work / "GestureKit.swiftmodule"), *map(str, gesture),
    "-o", str(work / "libGestureKit.dylib")], check=True)

support = r'''
import AppKit
import CoreGraphics
import Foundation
struct Scheme { struct Scrolling {} }
extension Comparable { func clamped(to r: ClosedRange<Self>) -> Self { min(max(r.lowerBound, self), r.upperBound) } }
extension Decimal { var asTruncatedDouble: Double { Double(truncating: self as NSNumber) } }
class MouseEventView { let event: CGEvent; init(_ event: CGEvent) { self.event = event } }
final class Device {
    enum Category { case mouse, trackpad }
    var category: Category = .mouse
    var highResolutionWheelNormalizationMultiplier: Int? = nil
}
struct EventTransformerContext { var device: Device? }
protocol EventTransformer { var handlesPointerMotion: Bool { get }; func transform(_ e: CGEvent, in c: EventTransformerContext) -> CGEvent? }
extension EventTransformer { var handlesPointerMotion: Bool { false } }
protocol Deactivatable { func deactivate() }
final class EventThreadTimer { var invalidated = false; func invalidate() { invalidated = true } }
final class EventThread {
    static let shared = EventThread()
    var lastInterval: Double = 0
    func scheduleTimer(interval: Double, repeats: Bool, handler: @escaping () -> Void) -> EventThreadTimer? {
        lastInterval = interval
        return EventThreadTimer()
    }
}
enum LogitechHighResolutionWheelUnitReader {
    struct UnitResolution { let rawUnits: Double; let units: Double }
    static func horizontalUnitResolution(from: ScrollWheelEventView, multiplier: Int) -> UnitResolution { fatalError("Unexpected hardware path") }
    static func verticalUnitResolution(from: ScrollWheelEventView, multiplier: Int) -> UnitResolution { fatalError("Unexpected hardware path") }
}
'''
(work / "Support.swift").write_text(support)
sources = [work / "Support.swift"]
production = [
    "LinearMouse/Utilities/Codable/ImplicitOptional.swift",
    "LinearMouse/Model/Configuration/Scheme/Scrolling/Bidirectional.swift",
    "LinearMouse/Model/Configuration/Scheme/Scrolling/Modifiers.swift",
    "LinearMouse/Model/Configuration/Scheme/Scrolling/Smoothed.swift",
    "LinearMouse/EventTransformer/SmoothedScrollingEngine.swift",
    "LinearMouse/EventTransformer/SmoothedScrollingDeliveryProfile.swift",
    "LinearMouse/EventTransformer/SmoothedScrollingTransformer.swift",
    "LinearMouse/EventView/ScrollWheelEventView.swift",
    "LinearMouse/EventTransformer/IPhoneMirroringScrollCompatibility.swift",
    "LinearMouse/EventTransformer/IPhoneMirroringScrollTransformer.swift",
    "LinearMouse/EventTransformer/ReverseScrollingTransformer.swift",
]
for index, relative in enumerate(production):
    text = (root / relative).read_text().replace('Bundle.main.bundleIdentifier!', '"mouse.mirror.validation"')
    destination = work / f"Source{index}.swift"
    destination.write_text(text)
    sources.append(destination)
synthetic = (root / "LinearMouse/Utilities/CGEvent+LinearMouseSynthetic.swift").read_text()
synthetic = "import CoreGraphics\n" + synthetic[synthetic.index("extension CGEvent {"):]
(work / "Synthetic.swift").write_text(synthetic)
sources.append(work / "Synthetic.swift")
main = r'''
import AppKit
import CoreGraphics
import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message) }
func wheel(_ y: Int32, x: Int32 = 0) -> CGEvent {
    CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0)!
}
let profile = Scheme.Scrolling.Smoothed.Preset.flow.defaultConfiguration
require(profile.bouncing == false, "Regression must use the shipped no-bounce profile")
let tuning = Scheme.Scrolling.Bidirectional(vertical: profile)
// Continuous mice can report pixels with or without gesture phases.
// Both forms must survive the fresh-install policy on desktop and in Mirroring.
for mirror in [false, true] {
    let context = EventTransformerContext(device: Device())
    let discreteOnly = SmoothedScrollingTransformer(smoothed: tuning,
        deliveryProfile: mirror ? .iPhoneMirroring : .standard,
        usesMirrorWheelTuning: mirror, preserveContinuousScrolling: true, now: { 0 },
        eventSink: { _ in preconditionFailure("Unexpected synthetic event") })
    let mirrorOutput = IPhoneMirroringScrollTransformer(preserveContinuousScrolling: true,
        eventSink: { _, _ in preconditionFailure("Native event was needlessly reposted") })
    require(discreteOnly.transform(wheel(1), in: context) == nil, "Discrete wheel was not smoothed")
    for phase: Int64 in [0, Int64(CGScrollPhase.began.rawValue), Int64(CGScrollPhase.ended.rawValue)] {
        let native = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
            wheel1: phase == Int64(CGScrollPhase.ended.rawValue) ? 0 : 9, wheel2: 0, wheel3: 0)!
        native.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        let fields: [CGEventField] = [.scrollWheelEventScrollPhase, .scrollWheelEventMomentumPhase,
            .scrollWheelEventIsContinuous, .scrollWheelEventPointDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1]
        let before = fields.map { native.getDoubleValueField($0) }
        require(discreteOnly.transform(native, in: context) === native, "Continuous mouse input was intercepted")
        if mirror { require(mirrorOutput.transform(native, in: context) === native, "Native mirror event changed") }
        require(fields.map { native.getDoubleValueField($0) } == before, "Continuous event fields changed")
        discreteOnly.tick()
    }
}
var now = 0.0
var delivered: [(Double, CGEvent)] = []
let transformer = SmoothedScrollingTransformer(smoothed: tuning, deliveryProfile: .iPhoneMirroring,
    now: { now }, eventSink: { event in
        require(event.type == .scrollWheel, "Mirror emitted an extra private gesture companion")
        IPhoneMirroringScrollCompatibility.post(event, usesCanonicalPixelDeltas: true) { rebuilt, tap in
            require(tap == .cghidEventTap, "Wrong delivery point")
            delivered.append((now, rebuilt))
        }
    })
let reversed = ReverseScrollingTransformer(vertically: true).transform(wheel(1), in: .init(device: nil))!
require(transformer.transform(reversed, in: .init(device: nil)) == nil, "Physical sample was not consumed")
require(abs(EventThread.shared.lastInterval - 1.0 / 60.0) < 0.000001, "Mirror is not paced at 60 Hz")
let reference = SmoothedScrollingEngine(smoothed: tuning)
reference.feed(deltaX: 0, deltaY: -36, timestamp: 0, inputKind: .wheel)
var referenceDistance = 0.0
for tick in 1 ... 180 {
    now = Double(tick) / 60.0
    if let emission = reference.advance(to: now) { referenceDistance += emission.deltaY }
    transformer.tick()
}
require(delivered.count > 5, "No smooth stream was delivered")
let phaseField = CGEventField.scrollWheelEventScrollPhase
let momentumField = CGEventField.scrollWheelEventMomentumPhase
let began = delivered.filter { $0.1.getIntegerValueField(phaseField) == Int64(CGScrollPhase.began.rawValue) }
let ended = delivered.filter { $0.1.getIntegerValueField(phaseField) == Int64(CGScrollPhase.ended.rawValue) }
require(began.count == 1 && ended.count == 1, "Touch phases must describe a single complete series")
require(delivered.contains { $0.1.getIntegerValueField(momentumField) == Int64(CGMomentumScrollPhase.end.rawValue) }, "Missing final momentum end")
var pointDistance = 0.0
for (index, item) in delivered.enumerated() {
    let (time, event) = item
    let value = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
    pointDistance += value
    require(value <= 0, "Direction reversal changed during the tail")
    require(event.getIntegerValueField(.scrollWheelEventIsContinuous) == 1, "Discrete event leaked into smooth stream")
    require(IPhoneMirroringScrollCompatibility.isReposted(event), "Missing single-pass marker")
    require(IPhoneMirroringScrollCompatibility.makeRepostedEvent(from: event) == nil, "Reposting loop")
    if index > 0 { require(time - delivered[index - 1].0 >= (1.0 / 60.0 - 0.000001), "Burst exceeded one frame") }
}
require(abs(pointDistance - referenceDistance) < 1, "Point quantization lost more than one pixel of total distance")
let countAtEnd = delivered.count
now += 1
transformer.tick()
require(delivered.count == countAtEnd, "Ended stream continued emitting events")

var cancelled: [CGEvent] = []
now = 0
let touching = SmoothedScrollingTransformer(smoothed: tuning, deliveryProfile: .iPhoneMirroring,
    now: { now }, eventSink: { cancelled.append($0.copy() ?? $0) })
_ = touching.transform(wheel(-1), in: .init(device: nil))
now = 1.0 / 60
touching.tick()
touching.deactivate()
require(cancelled.last?.getIntegerValueField(phaseField) == Int64(CGScrollPhase.cancelled.rawValue), "Deactivate did not cancel touch series")
require(cancelled.last?.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) == 0, "Cancellation moved the page")

var momentumEvents: [CGEvent] = []
now = 0
let coasting = SmoothedScrollingTransformer(smoothed: tuning, deliveryProfile: .iPhoneMirroring,
    now: { now }, eventSink: { momentumEvents.append($0.copy() ?? $0) })
_ = coasting.transform(wheel(-1), in: .init(device: nil))
for tick in 1 ... 14 { now = Double(tick) / 60; coasting.tick() }
require(momentumEvents.contains { $0.getIntegerValueField(momentumField) == Int64(CGMomentumScrollPhase.begin.rawValue) }, "Test never reached momentum")
coasting.deactivate()
require(momentumEvents.last?.getIntegerValueField(momentumField) == Int64(CGMomentumScrollPhase.end.rawValue), "Deactivate did not end momentum")

let partial = try JSONDecoder().decode(MirrorScrollSettings.self, from: Data(#"{"frequency":30,"speed":1.4}"#.utf8))
require(partial.hz == 30 && partial.tuning.speed == Decimal(string: "1.4") && partial.isEnabled, "Partial mirror settings failed")
require(partial.resolvedWheelMode == .smooth, "Existing settings must keep smooth scrolling")
let nativeMode = try JSONDecoder().decode(MirrorScrollSettings.self, from: Data(#"{"nativeWheelEvents":true}"#.utf8))
require(nativeMode.resolvedWheelMode == .reversed, "Raw wheel preference did not migrate")
let systemMode = try JSONDecoder().decode(MirrorScrollSettings.self, from: Data(#"{"nativeWheelEvents":true,"wheelMode":"system"}"#.utf8))
require(systemMode.resolvedWheelMode == .system, "System mode must supersede the legacy setting")
var nativeFrames: [CGEvent] = []
let nativeMirror = IPhoneMirroringScrollTransformer(preservesSourceEvent: true) { event, tap in
    require(tap == .cghidEventTap, "Raw mirror wheel took the wrong route")
    nativeFrames.append(event)
}
let mouseContext = EventTransformerContext(device: Device())
let metadata: [CGEventField] = [.scrollWheelEventDeltaAxis2, .scrollWheelEventPointDeltaAxis2,
    .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventIsContinuous, .scrollWheelEventScrollCount,
    .scrollWheelEventScrollPhase, .scrollWheelEventMomentumPhase, .eventSourceUserData]
let wheelFields = metadata + [.scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1]
let legacySystem = try JSONDecoder().decode(MirrorScrollSettings.self,
    from: Data(#"{"wheelMode":"system","systemReverseVertical":true,"systemWheelDistance":2}"#.utf8))
require(legacySystem.reversesSystemWheel && legacySystem.wheelMultiplier == 1, "Saved mirror reversal lost")
require(MirrorScrollSettings(wheelMode: .system, repeatSystemWheel: true).wheelMultiplier == 2, "Build 34 boost lost")
require(MirrorScrollSettings(wheelMode: .smooth, repeatSystemWheel: true).wheelMultiplier == 1, "Inactive boost leaked from legacy mode")
require(MirrorScrollSettings(enabled: false, systemReverseVertical: true, systemWheelMultiplier: 3).wheelMultiplier == 1,
        "Disabled mirror setting did not migrate to system defaults")
require(!MirrorScrollSettings(enabled: false, systemReverseVertical: true).reversesSystemWheel, "Disabled reversal leaked")
let systemDefault = IPhoneMirroringSystemWheelTransformer(settings: .init()) { _, _ in
    preconditionFailure("A saved distance preference silently enabled extra events")
}
func hardwareWheel(_ y: Int32, x: Int32 = 0) -> CGEvent {
    let event = wheel(y, x: x)
    event.timestamp = 1234
    event.flags = []
    event.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
    return event
}
let original = hardwareWheel(2)
let baseline = wheelFields.map(original.getDoubleValueField)
require(systemDefault.transform(original, in: mouseContext) === original, "System baseline lost the original")
require(baseline == wheelFields.map(original.getDoubleValueField), "System baseline changed original wheel fields")
var extras = [CGEvent]()
let systemRepeat = IPhoneMirroringSystemWheelTransformer(settings: .init(wheelMode: .system, repeatSystemWheel: true)) { copy, tap in
    require(tap == .cghidEventTap, "Wrong delivery path")
    extras.append(copy)
}
for delta: Int32 in [1, 1, -1, -2, 4, 0] {
    let event = hardwareWheel(delta)
    // Some high-resolution discrete input carries distance only in the precise field.
    if delta == 0 { ScrollWheelEventView(event).deltaYFixedPt = -0.25 }
    let before = wheelFields.map(event.getDoubleValueField)
    let count = extras.count
    require(systemRepeat.transform(event, in: mouseContext) === event, "Repeat swallowed the real event")
    require(before == wheelFields.map(event.getDoubleValueField) && event.timestamp == 1234,
            "Repeat changed the original input")
    require(extras.count == count + 1, "Expected exactly one extra discrete event")
    let copy = extras.last!
    require(copy !== event && IPhoneMirroringScrollCompatibility.isReposted(copy) && copy.timestamp != event.timestamp,
            "Extra event must be distinct and tagged")
    let distanceAndPhase = wheelFields.filter { $0 != .eventSourceUserData }
    require(distanceAndPhase.map(copy.getDoubleValueField) == distanceAndPhase.map(event.getDoubleValueField),
            "Extra event changed distance, direction or gesture phases")
    require(systemRepeat.transform(copy, in: mouseContext) === copy && extras.count == count + 1,
            "Repeat generated feedback")
}
let countBeforeBypass = extras.count
let trackpad = Device()
trackpad.category = .trackpad
let precise = hardwareWheel(1)
ScrollWheelEventView(precise).continuous = true
let otherApp = hardwareWheel(1)
otherApp.setIntegerValueField(.eventSourceUnixProcessID, value: 501)
let phaseOnlyWheel = hardwareWheel(1)
ScrollWheelEventView(phaseOnlyWheel).scrollPhase = .ended
let synthetic = hardwareWheel(1)
synthetic.isLinearMouseSyntheticEvent = true
let bypass = [hardwareWheel(0), hardwareWheel(1, x: 1), precise, otherApp, phaseOnlyWheel, synthetic]
for event in bypass {
    require(systemRepeat.transform(event, in: mouseContext) === event, "Ineligible input was consumed")
}
for modifier: CGEventFlags in [.maskShift, .maskControl, .maskCommand, .maskAlternate, .maskSecondaryFn] {
    let event = hardwareWheel(1)
    event.flags = modifier
    _ = systemRepeat.transform(event, in: mouseContext)
}
_ = systemRepeat.transform(original, in: .init(device: trackpad))
require(countBeforeBypass == extras.count, "Repeated a shortcut, trackpad, synthetic or non-vertical input")
print("PASS: experimental mirror repeat leaves original intact, sends one marked discrete copy per input, bypasses other inputs and defaults off")
// Mirror wheel routing bypasses the desktop modifier chain. Exercise the configured
// bindings on the native route, both with default tuning and with reversal/boost on.
let axisFields: [[CGEventField]] = [
    [.scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1,
     .scrollWheelEventRawDeltaAxis1, .scrollWheelEventAcceleratedDeltaAxis1],
    [.scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2,
     .scrollWheelEventRawDeltaAxis2, .scrollWheelEventAcceleratedDeltaAxis2]
]
let bindings = Scheme.Scrolling.Bidirectional<Scheme.Scrolling.Modifiers>(
    vertical: .init(shift: .alterOrientation, option: .alterOrientation), horizontal: .init(control: .alterOrientation))
let presetTunings = [false, true].flatMap { reverse in
    MirrorScrollSettings.wheelMultipliers.map { MirrorScrollSettings(systemReverseVertical: reverse, systemWheelMultiplier: $0) }
}
for tuning in presetTunings {
    let rate = tuning.wheelMultiplier
    let switcher = IPhoneMirroringSystemWheelTransformer(settings: tuning, modifiers: bindings) { _, _ in
        preconditionFailure("A modifier reposted a wheel event")
    }
    for (key, side, sourceAxis) in [(CGEventFlags.maskAlternate, NX_DEVICELALTKEYMASK, 0),
                                    (.maskAlternate, NX_DEVICERALTKEYMASK, 0),
                                    (.maskShift, NX_DEVICELSHIFTKEYMASK, 0),
                                    (.maskControl, NX_DEVICERCTLKEYMASK, 1)] {
        for sign in [-1.0, 1.0] {
            let event = hardwareWheel(0)
            event.flags = [.maskAlphaShift, key, .init(rawValue: UInt64(side))]
            let values = [1.0, 0.75, 8, -1, -0.75].map { $0 * sign }
            for (field, value) in zip(axisFields[sourceAxis], values) { event.setDoubleValueField(field, value: value) }
            require(switcher.transform(event, in: mouseContext) === event, "Axis switch lost original hardware event")
            require(event.flags == .maskAlphaShift && event.timestamp == 1234, "Shortcut changed unrelated metadata")
            require(axisFields[sourceAxis].allSatisfy { event.getDoubleValueField($0) == 0 } &&
                axisFields[1-sourceAxis].map(event.getDoubleValueField) == values.map { $0 * rate },
                "Configured shortcut lost the selected speed or changed direction")
            let native = NSEvent(cgEvent: event)!
            require(sourceAxis == 0 ? native.scrollingDeltaX != 0 && native.scrollingDeltaY == 0 :
                    native.scrollingDeltaY != 0 && native.scrollingDeltaX == 0, "AppKit received the wrong axis")
        }
    }
    let fractional = hardwareWheel(0)
    fractional.flags = .maskAlternate
    fractional.setDoubleValueField(.scrollWheelEventRawDeltaAxis1, value: -0.125)
    _ = switcher.transform(fractional, in: mouseContext)
    require(fractional.getDoubleValueField(.scrollWheelEventRawDeltaAxis2) == -0.125 * rate &&
        fractional.getDoubleValueField(.scrollWheelEventRawDeltaAxis1) == 0, "Raw-only wheel shortcut was lost")
    let bypassCases: [(CGEvent, Device, CGEventFlags)] = [
        (hardwareWheel(1), trackpad, .maskAlternate),
        (hardwareWheel(1), mouseContext.device!, [.maskCommand, .maskAlternate]),
        (hardwareWheel(1), mouseContext.device!, .maskControl),
        (hardwareWheel(0, x: 1), mouseContext.device!, .maskAlternate),
        (phaseOnlyWheel, mouseContext.device!, .maskAlternate),
        (otherApp, mouseContext.device!, .maskAlternate)
    ]
    for (event, device, flags) in bypassCases {
        event.flags = flags
        let fields = axisFields.flatMap { $0 }
        let initial = fields.map(event.getDoubleValueField)
        require(switcher.transform(event, in: .init(device: device)) === event &&
            event.flags == flags && fields.map(event.getDoubleValueField) == initial, "Ineligible shortcut changed the input")
    }
}
// Exercise physical tilt as well as native Shift, where the receiver can still do the axis change.
for rate in MirrorScrollSettings.wheelMultipliers + [1.25, 1.5] {
    for reverse in [false, true] {
        let tuning = MirrorScrollSettings(systemReverseVertical: reverse, systemWheelMultiplier: rate)
        let stage = IPhoneMirroringSystemWheelTransformer(settings: tuning, modifiers: bindings) { _, _ in
            preconditionFailure("Horizontal acceleration generated an extra event")
        }
        let native = IPhoneMirroringSystemWheelTransformer(settings: tuning) { _, _ in
            preconditionFailure("Native Shift generated an extra event")
        }
        for (key, sourceAxis, outputAxis, handler) in [
            (CGEventFlags(), 1, 1, stage), (.maskAlternate, 0, 1, stage),
            (.maskShift, 0, 0, native), (.maskShift, 1, 1, native)
        ] {
            for direction in [-1.0, 1.0] {
                var pointTotal = 0.0, lineTotal = 0.0
                for _ in 0..<8 {
                    let event = hardwareWheel(0)
                    event.flags = key
                    let values = [1.0, 0.75, 7, -2, -0.5].map { $0 * direction }
                    for (field, value) in zip(axisFields[sourceAxis], values) { event.setDoubleValueField(field, value: value) }
                    require(handler.transform(event, in: mouseContext) === event && event.timestamp == 1234,
                            "Horizontal acceleration replaced the hardware event")
                    let result = axisFields[outputAxis].map(event.getDoubleValueField)
                    lineTotal += result[0]
                    pointTotal += result[2]
                    require(result[1] == values[1] * rate && result[3] == values[3] * rate && result[4] == values[4] * rate &&
                        axisFields[1-outputAxis].allSatisfy { event.getDoubleValueField($0) == 0 }, "Unexpected horizontal speed or axis")
                    require(event.flags == (handler === native ? key : []), "Changed native Shift or kept the mapped modifier")
                }
                require(lineTotal == direction * 8 * rate && pointTotal == direction * 56 * rate, "Lost fractional horizontal travel")
            }
        }
    }
}
let ignoredShift = IPhoneMirroringSystemWheelTransformer(settings: .init(systemWheelMultiplier: 5),
    modifiers: .init(vertical: .init(shift: .zoom))) { _, _ in preconditionFailure("Reposted a shortcut") }
let zoomWheel = hardwareWheel(1)
zoomWheel.flags = .maskShift
let beforeZoom = axisFields[0].map(zoomWheel.getDoubleValueField)
_ = ignoredShift.transform(zoomWheel, in: mouseContext)
require(zoomWheel.flags == .maskShift && axisFields[0].map(zoomWheel.getDoubleValueField) == beforeZoom, "Accelerated a zoom shortcut")
let tilted = hardwareWheel(0, x: 1)
let coastingTilt = tilted.copy()!
ScrollWheelEventView(coastingTilt).momentumPhase = .begin
let markedTilt = tilted.copy()!
markedTilt.setIntegerValueField(.eventSourceUserData, value: IPhoneMirroringScrollCompatibility.repostedEventMarker)
for (event, device) in [(tilted, trackpad), (coastingTilt, mouseContext.device!), (markedTilt, mouseContext.device!)] {
    let fields = axisFields.flatMap { $0 }
    let before = fields.map(event.getDoubleValueField)
    require(ignoredShift.transform(event, in: .init(device: device)) === event &&
            fields.map(event.getDoubleValueField) == before, "Accelerated a trackpad, momentum or already handled tilt")
}
print("PASS: Option/Shift-to-horizontal and physical tilt receive mirror speed, 1x–5x, legacy fractional rates, both directions and vertical reversal states")
// Count original pass-throughs and HID-path outputs in both directions.
require(MirrorScrollSettings.wheelMultipliers == [1, 2, 3, 4, 5], "Mirror speed presets must be 1x through 5x")
for rate in MirrorScrollSettings.wheelMultipliers + [1.25, 1.5] {
    for reverse in [false, true] {
        var posts = [CGEvent]()
        let stage = IPhoneMirroringSystemWheelTransformer(settings:
            .init(systemReverseVertical: reverse, systemWheelMultiplier: rate)) { event, tap in
            require(tap == .cghidEventTap, "Mirror wheel left the HID path")
            posts.append(event)
        }
        for direction: Int32 in [-1, 1] {
            var outputCount = 0
            var pointTotal = 0.0
            var lineTotal: Int64 = 0
            for _ in 0..<8 {
                let event = hardwareWheel(2 * direction)
                event.location = CGPoint(x: 60, y: 80)
                event.setIntegerValueField(.scrollWheelEventScrollCount, value: 3)
                let inputView = ScrollWheelEventView(event)
                inputView.deltaYFixedPt = 0.75 * Double(direction)
                inputView.deltaYPt = 7 * Double(direction)
                event.setDoubleValueField(.scrollWheelEventRawDeltaAxis1, value: 1.25 * Double(direction))
                event.setDoubleValueField(.scrollWheelEventAcceleratedDeltaAxis1, value: 33.75 * Double(direction))
                let start = posts.count
                let passthrough = stage.transform(event, in: mouseContext)
                require(passthrough === event, "Lost the hardware event")
                let added = Array(posts.dropFirst(start))
                let delivered = added + (passthrough.map { [$0] } ?? [])
                outputCount += delivered.count
                for item in delivered {
                    let factor = reverse ? -rate : 1
                    let v = ScrollWheelEventView(item)
                    lineTotal += v.deltaY
                    pointTotal += v.deltaYPt
                    require(abs(Double(v.deltaY) - factor * Double(2 * direction)) < 1 &&
                        v.deltaYFixedPt == factor * 0.75 * Double(direction) &&
                        abs(v.deltaYPt - factor * 7 * Double(direction)) < 1, "Wrong travel per wheel sample")
                    require(item.getDoubleValueField(.scrollWheelEventRawDeltaAxis1) == factor * 1.25 * Double(direction) &&
                        item.getDoubleValueField(.scrollWheelEventAcceleratedDeltaAxis1) == factor * 33.75 * Double(direction),
                        "Raw or accelerated wheel travel was lost")
                    require(v.deltaX == 0 && !v.continuous && v.scrollPhase == nil && v.momentumPhase == .none &&
                        item.location == event.location && item.getIntegerValueField(.scrollWheelEventScrollCount) == 3,
                        "Generated a gesture or changed the target")
                }
                for copy in added {
                    let before = posts.count
                    require(IPhoneMirroringScrollCompatibility.isReposted(copy) &&
                        stage.transform(copy, in: mouseContext) === copy && posts.count == before, "Reposting loop")
                }
            }
            require(outputCount == (reverse ? 8 : Int(8 * rate)), "Wrong wheel event count")
            let signedRate = reverse ? -rate : rate
            require(Double(lineTotal) == 16 * Double(direction) * signedRate &&
                    pointTotal == 56 * Double(direction) * signedRate, "Fractional speed lost cumulative travel")
        }
        let before = posts.count
        for event in bypass {
            require(stage.transform(event, in: mouseContext) === event, "Bypassed input was replaced")
        }
        require(stage.transform(original, in: .init(device: trackpad)) === original && posts.count == before,
                "Unexpected output for native gestures or trackpad")
    }
}
print("PASS: system wheel, five rates, both directions, legacy settings, reverse retains the hardware event")
// Hardware and logical scroll directions can disagree. Earlier tests used
// matching signs for every field, so both UI settings could appear to pass.
for rate in MirrorScrollSettings.wheelMultipliers {
    for sign: Int32 in [-1, 1] {
        for rawSign in [-1.0, 1.0] {
            let input = hardwareWheel(sign)
            let logical = Double(sign)
            input.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: logical * 10)
            input.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: logical)
            input.setDoubleValueField(.scrollWheelEventRawDeltaAxis1, value: rawSign * 2)
            input.setDoubleValueField(.scrollWheelEventAcceleratedDeltaAxis1, value: rawSign * 9)
            var outputs = [CGEvent]()
            let stage = IPhoneMirroringSystemWheelTransformer(settings: .init(systemReverseVertical: true, systemWheelMultiplier: rate)) {
                item, _ in outputs.append(item)
            }
            let fields: [CGEventField] = [.scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1,
                    .scrollWheelEventPointDeltaAxis1, .scrollWheelEventRawDeltaAxis1, .scrollWheelEventAcceleratedDeltaAxis1]
            let before = fields.map(input.getDoubleValueField)
            require(stage.transform(input, in: mouseContext) === input && outputs.isEmpty, "Replaced physical input")
            require(input.timestamp == 1234 && !IPhoneMirroringScrollCompatibility.isReposted(input), "Lost original metadata")
            let wire: CGEvent
            if #available(macOS 12, *) {
                wire = CGEvent(withDataAllocator: nil, data: input.data!)!
            } else {
                wire = input
            }
            for (field, source) in zip(fields, before) {
                let value = wire.getDoubleValueField(field)
                require(value * source < 0 && abs(value + source * rate) < 1, "Native wheel direction or distance changed")
            }
        }
    }
}
print("PASS: hardware event retained, five delta fields reverse in their own coordinates at five rates")
var rawOnlyPosts = [CGEvent]()
let rawOnlyStage = IPhoneMirroringSystemWheelTransformer(settings: .init(systemReverseVertical: true, systemWheelMultiplier: 3)) {
    item, _ in rawOnlyPosts.append(item)
}
let rawOnlyWheel = hardwareWheel(0)
rawOnlyWheel.setDoubleValueField(.scrollWheelEventRawDeltaAxis1, value: 0.25)
require(rawOnlyStage.transform(rawOnlyWheel, in: mouseContext) === rawOnlyWheel &&
        rawOnlyPosts.isEmpty && rawOnlyWheel.getDoubleValueField(.scrollWheelEventRawDeltaAxis1) == -0.75 &&
        rawOnlyWheel.getDoubleValueField(.scrollWheelEventAcceleratedDeltaAxis1) == 0, "Raw-only input changed units")
rawOnlyWheel.setDoubleValueField(.scrollWheelEventRawDeltaAxis2, value: 0.5)
require(rawOnlyStage.transform(rawOnlyWheel, in: mouseContext) === rawOnlyWheel && rawOnlyPosts.isEmpty,
        "Mixed axes must pass through intact")
let reversedClick = ReverseScrollingTransformer(vertically: true).transform(wheel(1), in: mouseContext)!
reversedClick.timestamp = 1234
require(nativeMirror.transform(reversedClick, in: mouseContext) == nil && nativeFrames.count == 1,
        "Raw mirror mode must send exactly one reversed wheel event")
let rawWheel = ScrollWheelEventView(nativeFrames[0])
require(rawWheel.deltaY == -1 && rawWheel.deltaX == 0 && !rawWheel.continuous,
        "Raw mirror wheel type or direction changed")
require(rawWheel.scrollPhase == nil && rawWheel.momentumPhase == .none, "Raw mirror wheel gained gesture phases")
require(nativeFrames[0].timestamp == reversedClick.timestamp, "Reversal did not preserve the original hardware-event timestamp")
print("PASS: mirror raw wheel keeps reversal and produces a single original detent")
require(MirrorScrollSettings(speed: 20, duration: -1, frequency: 45).scrollSpeed == 4, "Imported speed clamp failed")
require(MirrorScrollSettings(duration: -1, frequency: 45).hz == 60 && MirrorScrollSettings(duration: -1).tail == 0, "Imported frequency or tail handling failed")
let slowProfile = SmoothedScrollingDeliveryProfile.mirror30Hz
require(slowProfile.preservesScrollPhases && !slowProfile.emitsGestureCompanions && slowProfile.accumulatesMomentumSubpixels, "30 Hz transport lost mirror behavior")
now = 0
var slowEvents = [CGEvent]()
let slow = SmoothedScrollingTransformer(smoothed: .init(vertical: partial.tuning, horizontal: partial.tuning),
    deliveryProfile: slowProfile, now: { now }, eventSink: { slowEvents.append($0) })
_ = slow.transform(wheel(-1), in: .init(device: nil))
require(abs(EventThread.shared.lastInterval - 1.0 / 30) < 0.000001, "30 Hz preference not applied")
for step in 1 ... 90 { now = Double(step) / 30; slow.tick() }
require(slowEvents.allSatisfy { $0.type == .scrollWheel } && slowEvents.contains { $0.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) < 0 }, "30 Hz lost signed movement")
require(slowEvents.last?.getIntegerValueField(momentumField) == Int64(CGMomentumScrollPhase.end.rawValue), "30 Hz did not end")

// A phase-less precision wheel can deliver less than one point of physical
// input. Verify that such a stroke starts promptly without requiring more samples.
func precisionWheel(_ delta: Double, horizontal: Bool) -> CGEvent {
    let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0)!
    let view = ScrollWheelEventView(event)
    view.continuous = true
    if horizontal { view.deltaXFixedPt = delta } else { view.deltaYFixedPt = delta }
    return event
}
let mirror = MirrorScrollSettings()

func isolatedWheel(_ input: CGEvent, profile: SmoothedScrollingDeliveryProfile) -> [(x: Double, y: Double)] {
    var now = 0.0
    var frames: [(x: Double, y: Double)] = []
    let reverse = ReverseScrollingTransformer(vertically: true)
    let transformer = SmoothedScrollingTransformer(smoothed: .init(vertical: mirror.tuning, horizontal: mirror.tuning),
        deliveryProfile: profile, usesMirrorWheelTuning: true, now: { now }, eventSink: { event in
            guard let rebuilt = IPhoneMirroringScrollCompatibility.makeRepostedEvent(
                from: event, usesCanonicalPixelDeltas: true
            ) else { return }
            let view = ScrollWheelEventView(rebuilt)
            frames.append((view.deltaXPt, view.deltaYPt))
        })
    let reversed = reverse.transform(input, in: .init(device: nil))!
    require(transformer.transform(reversed, in: .init(device: nil)) == nil, "An original wheel axis leaked past smoothing")
    for frame in 1 ... 90 {
        now = Double(frame) * profile.timerInterval
        transformer.tick()
    }
    return frames
}

for profile in [SmoothedScrollingDeliveryProfile.iPhoneMirroring, .mirror30Hz] {
    let sample = precisionWheel(36, horizontal: false)
    // A predominantly vertical wheel event can carry a tiny horizontal value.
    ScrollWheelEventView(sample).deltaXFixedPt = 0.5
    let frames = isolatedWheel(sample, profile: profile)
    let distances = frames.map { -$0.y }
    let oldFirst = profile == .iPhoneMirroring ? 24.0 : 48.0
    let oldPeak = profile == .iPhoneMirroring ? 24.0 : 49.0
    require(distances.first.map { $0 >= 6 && $0 < oldFirst * 0.7 } == true, "Isolated detent did not start gently on frame one")
    require(distances.max().map { $0 < oldPeak * 0.90 } == true, "Isolated detent peak barely changed")
    require(abs(distances.reduce(0, +) - 94) <= 1, "A notch should travel the same distance at 30 and 60 Hz")
    require(frames.allSatisfy { $0.x == 0 && $0.y <= 0 }, "Reversed vertical scroll leaked horizontal or opposite motion")

    let sideways = isolatedWheel(precisionWheel(36, horizontal: true), profile: profile)
    require(sideways.contains { $0.x > 0 } && sideways.allSatisfy { $0.y == 0 }, "Explicit horizontal wheel movement was lost")
    let diagonal = isolatedWheel(wheel(1, x: 1), profile: profile)
    require(diagonal.contains { $0.x > 0 && $0.y < 0 }, "Deliberate two-axis input lost an axis")
    print("Isolated detent \(Int(1 / profile.timerInterval)) Hz: first \(distances.first ?? 0), peak \(distances.max() ?? 0), total \(distances.reduce(0, +)), horizontal 0")
}

for deliveryProfile in [SmoothedScrollingDeliveryProfile.iPhoneMirroring, .mirror30Hz] {
    let interval = deliveryProfile.timerInterval
    for horizontal in [false, true] {
        let deltaField: CGEventField = horizontal ? .scrollWheelEventPointDeltaAxis2 : .scrollWheelEventPointDeltaAxis1
        let sign = horizontal ? 1.0 : -1.0
        now = 0
        var frames = [CGEvent]()
        let precision = SmoothedScrollingTransformer(smoothed: .init(vertical: mirror.tuning, horizontal: mirror.tuning),
            deliveryProfile: deliveryProfile, usesMirrorWheelTuning: true,
            now: { now }, eventSink: { event in
                if let rebuilt = IPhoneMirroringScrollCompatibility.makeRepostedEvent(from: event, usesCanonicalPixelDeltas: true) {
                    frames.append(rebuilt)
                }
            })
        require(precision.transform(precisionWheel(sign * 0.25, horizontal: horizontal), in: .init(device: nil)) == nil,
                "Precision sample was not consumed")
        now = interval
        precision.tick()
        require(frames.count == 1 && frames[0].getIntegerValueField(phaseField) == Int64(CGScrollPhase.began.rawValue),
                "One small input did not begin scrolling on the first frame")
        require(frames[0].getDoubleValueField(deltaField) * sign >= 6, "First mirror movement was too small or changed direction")
        now += interval
        precision.tick()
        require(frames.count == 2 && frames[1].getIntegerValueField(phaseField) == Int64(CGScrollPhase.changed.rawValue),
                "The first short stroke had no changed frame")
        require(frames[1].getDoubleValueField(deltaField) * sign > 0, "Changed frame lost movement")
        now += 0.001
        _ = precision.transform(precisionWheel(-sign * 0.25, horizontal: horizontal), in: .init(device: nil))
        now += interval - 0.001
        let frameCount = frames.count
        precision.tick()
        require(frames.count == frameCount + 1, "Reversal started a second synthetic gesture")
        require(frames.last?.getIntegerValueField(phaseField) == Int64(CGScrollPhase.changed.rawValue)
            && frames.last!.getDoubleValueField(deltaField) * sign < 0, "First small reverse input was lost")
        require(frames.allSatisfy { $0.getIntegerValueField(momentumField) == 0 }, "Mirror wheel emitted a momentum swipe")
        precision.deactivate()
    }
}

// Discrete detents can be slower than the original 40 ms touch window even
// during one steady turn. Check the HID event stream across those gaps.
let detentTimes = (0 ..< 8).map { Double($0) * 0.07 }
func steadyWheel(speed: Double?, usesMirrorWheelTuning: Bool, times: [Double],
                 eventAtIndex: (Int) -> CGEvent = { _ in wheel(1) }, dropsFrames: Bool = false, tail: Double? = nil,
                 profile: SmoothedScrollingDeliveryProfile = .iPhoneMirroring) -> [(time: Double, event: CGEvent)] {
    let tuning = MirrorScrollSettings(speed: speed, duration: tail).tuning
    var now = 0.0
    var frames: [(time: Double, event: CGEvent)] = []
    let transformer = SmoothedScrollingTransformer(smoothed: .init(vertical: tuning), deliveryProfile: profile,
        usesMirrorWheelTuning: usesMirrorWheelTuning, now: { now }, eventSink: { event in
            if let rebuilt = IPhoneMirroringScrollCompatibility.makeRepostedEvent(from: event, usesCanonicalPixelDeltas: true) {
                frames.append((now, rebuilt))
            }
        })
    var nextDetent = 0
    let lastTick = Int(ceil(((times.last ?? 0) + 1.5) / profile.timerInterval))
    for frame in 1 ... lastTick {
        let tickTime = Double(frame) * profile.timerInterval
        while nextDetent < times.count && times[nextDetent] <= tickTime {
            now = times[nextDetent]
            let event = eventAtIndex(nextDetent)
            _ = transformer.transform(event, in: .init(device: nil))
            nextDetent += 1
        }
        if !dropsFrames || frame % 4 != 0 {
            now = tickTime
            transformer.tick()
        }
    }
    return frames
}
let oldCadence = steadyWheel(speed: 0.90, usesMirrorWheelTuning: false, times: detentTimes)
let newCadence = steadyWheel(speed: nil, usesMirrorWheelTuning: true, times: detentTimes)
func detentDistance(_ frames: [(time: Double, event: CGEvent)]) -> Double {
    frames.reduce(0) { $0 + $1.event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) }
}
func starts(_ frames: [(time: Double, event: CGEvent)]) -> Int {
    frames.filter { $0.event.getIntegerValueField(phaseField) == Int64(CGScrollPhase.began.rawValue) }.count
}
func largestFrameGap(_ frames: [(time: Double, event: CGEvent)]) -> TimeInterval {
    let moving = frames.filter { $0.time <= detentTimes.last! && $0.event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) > 0 }
    return zip(moving, moving.dropFirst()).map { $1.time - $0.time }.max() ?? 0
}
require(starts(oldCadence) > 1 && starts(newCadence) == 1, "Steady detents restarted the touch gesture")
require(largestFrameGap(newCadence) <= 1.0 / 60 + 0.000001, "Steady detents had a missing movement frame")
let movingTimes = newCadence.filter { $0.event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) != 0 }.map(\.time)
require(Set(movingTimes).count == movingTimes.count, "A tick delivered duplicate movement")
let oldDistance = detentDistance(oldCadence)
let newDistance = detentDistance(newCadence)
require((1.10 ... 1.55).contains(newDistance / oldDistance), "Steady motion should get moderately faster without overshooting")
require(abs(newDistance - 484) <= 5, "Steady wheel speed diverged from the accepted 0.5.9 build")
require(newCadence.last?.event.getIntegerValueField(phaseField) == Int64(CGScrollPhase.ended.rawValue),
        "Grouped detents did not end their swipe")
print("Steady detents, old/new: gesture starts \(starts(oldCadence))/\(starts(newCadence)), largest moving-frame gap \(largestFrameGap(oldCadence))/\(largestFrameGap(newCadence)) s, distance \(oldDistance)/\(newDistance) points")

let fineCadence = steadyWheel(speed: nil, usesMirrorWheelTuning: true, times: detentTimes, eventAtIndex: { _ in precisionWheel(4.5, horizontal: false) })
for (index, start) in detentTimes.dropLast().enumerated() {
    let delta = detentDistance(fineCadence.filter { $0.time >= start && $0.time < detentTimes[index + 1] })
    require(delta >= 15, "A fine notch stopped moving during consecutive scrolling")
}
let slowTimes = (0 ..< 8).map { Double($0) * 0.16 }
let slowDetents = steadyWheel(speed: nil, usesMirrorWheelTuning: true, times: slowTimes)
require(detentDistance(slowDetents) > 750, "Slow standard notches remained sluggish")
require(starts(slowDetents) == 1 && slowDetents.allSatisfy { $0.event.getIntegerValueField(momentumField) == 0 },
        "Slow turns split into multiple gestures")
let delayed = steadyWheel(speed: nil, usesMirrorWheelTuning: true, times: slowTimes, dropsFrames: true)
require(starts(delayed) == 1 && abs(detentDistance(delayed) - detentDistance(slowDetents)) <= 1,
        "Delayed ticks lost wheel distance or split the swipe")
print("Slow precision and regular detents: \(detentDistance(fineCadence)) and \(detentDistance(slowDetents)) points")
print("Slow turn: one gesture; distance with every fourth tick skipped: \(detentDistance(delayed)) points")

// Inspect the time between delivered, nonzero point deltas during a slow turn.
func movingFrameTimes(_ frames: [(time: Double, event: CGEvent)]) -> [Double] {
    frames.filter { $0.event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) != 0 }.map(\.time)
}
var timingFailures = [String]()
for profile in [SmoothedScrollingDeliveryProfile.iPhoneMirroring, .mirror30Hz] {
    for gaps in [[0.275], [0.285], [0.32], [0.26, 0.31, 0.29, 0.32]] {
        var times = [0.0]
        for i in 0 ..< 7 { times.append(times.last! + gaps[i % gaps.count]) }
        let frames = steadyWheel(speed: nil, usesMirrorWheelTuning: true, times: times, profile: profile)
        let moving = movingFrameTimes(frames).filter { $0 >= times[2] && $0 <= times.last! }
        require(moving.count >= 2, "Missing slow turn movement")
        let maxGap = zip(moving, moving.dropFirst()).map { $1 - $0 }.max()!
        print("Cadence \(gaps), \(Int(1/profile.timerInterval)) Hz: longest moving-frame interval \(Int((maxGap * 1000).rounded())) ms, starts \(starts(frames)), distance \(detentDistance(frames))")
        if maxGap > 0.085 || starts(frames) > 2 || !(730 ... 800).contains(detentDistance(frames)) {
            timingFailures.append("Interrupted slow turn at \(gaps), \(profile)")
        }
        require(frames.last?.event.getIntegerValueField(phaseField) == Int64(CGScrollPhase.ended.rawValue),
                "The final slow notch never ended")
    }
}
// Relative packet timings from two slow wheel turns. Each row is a burst;
// the application switch between the turns is intentionally excluded.
// Equal input amplitudes isolate timing from macOS wheel acceleration.
let packetTurns: [[[Int]]] = [
    [
        [0, 23, 58, 93],
        [581, 642, 681, 715, 815],
        [1162, 1208, 1251],
        [1704, 1808, 1835],
        [2452, 2490, 2529, 2608],
        [3202, 3235, 3264],
        [3733, 3768, 3810, 3846],
        [4286, 4311, 4329, 4356, 4438],
        [4821, 4847, 4866, 4900],
        [5319, 5334, 5353, 5373, 5388, 5463],
    ],
    [
        [0, 25, 52, 95],
        [596, 631, 658, 676, 712],
        [1188, 1242, 1267, 1306],
        [1717, 1751, 1779, 1815],
        [2264, 2278, 2297, 2324],
        [2692, 2717, 2745, 2761, 2806],
        [3237, 3253, 3271, 3290, 3324],
        [3705, 3729, 3757, 3773, 3798],
        [4176, 4208, 4219, 4239, 4263],
        [4622, 4650, 4658, 4677, 4693],
        [5062, 5090, 5104, 5124, 5149],
        [5529, 5552, 5563, 5585, 5606],
        [5987, 6004, 6021, 6040, 6056, 6082],
        [6434, 6450, 6469, 6490, 6505],
        [6888, 6899, 6925, 6957, 6987],
        [7540, 7548, 7566, 7582, 7604],
        [7906, 7918, 7934, 7952],
    ],
]
for profile in [SmoothedScrollingDeliveryProfile.iPhoneMirroring, .mirror30Hz] {
    for (turn, originalDistance) in zip(packetTurns, [2476.0, 4583.0]) {
        let bursts = turn.map { $0.map { Double($0) / 1000 } }
        let times = bursts.flatMap { $0 }
        let replay = steadyWheel(speed: nil, usesMirrorWheelTuning: true, times: times, profile: profile)
        require(abs(detentDistance(replay) / originalDistance - 1) < 0.04,
                "Burst smoothing changed the overall travel")
        let moving = movingFrameTimes(replay)
        // The pause between separate strokes is intentional. Check responsiveness
        // during the measured input packets and exclude the user's lift intervals.
        for burst in bursts {
            for time in burst {
                let nextMove = moving.first { $0 >= time }
                require(nextMove.map { $0 - time <= profile.timerInterval + 0.001 } == true,
                        "No movement on the first timer tick after a burst packet")
            }
            let active = moving.filter { $0 >= burst.first! && $0 <= burst.last! }
            let worstGap = zip(active, active.dropFirst()).map { $1 - $0 }.max() ?? 0
            require(worstGap <= 2 * profile.timerInterval + 0.001, "Movement stalled inside an active burst")
        }
        let phases = replay.compactMap { ScrollWheelEventView($0.event).scrollPhase }
        var open = false
        for phase in phases {
            if phase == .began {
                require(!open, "Duplicate begin")
                open = true
            } else {
                require(open, "Scroll phase without begin")
            }
            if phase == .ended || phase == .cancelled { open = false }
        }
        require(!open && moving.last! - times.last! <= 0.55, "Scroll did not settle after release")
    }
}
// Reproduce the nine wheel bursts recorded while the mirror remained in front.
// The logged line deltas are the axis values used by the discrete-wheel path.
let observedBursts: [[(ms: Int, lines: Int32)]] = [
    [(0, 1), (22, 1), (60, 2), (171, 2), (231, 3)],
    [(617, 1), (652, 1), (690, 2), (748, 3)],
    [(1184, 1), (1206, 1), (1247, 2), (1342, 2)],
    [(1772, 1), (1796, 1), (1824, 2), (1923, 2)],
    [(2336, 1), (2363, 1), (2392, 2), (2420, 3)],
    [(2901, 1), (2921, 1), (2940, 2), (2996, 3)],
    [(3454, 1), (3478, 1), (3518, 2)],
    [(3946, 1), (4006, 1), (4050, 1)],
    [(4588, 1), (4656, 1), (4721, 1)],
]
let observedPackets = observedBursts.flatMap { $0 }
for profile in [SmoothedScrollingDeliveryProfile.iPhoneMirroring, .mirror30Hz] {
    let replay = steadyWheel(speed: nil, usesMirrorWheelTuning: true,
        times: observedPackets.map { Double($0.ms) / 1000 },
        eventAtIndex: { wheel(-observedPackets[$0].lines) }, profile: profile)
    let begins = replay.filter { ScrollWheelEventView($0.event).scrollPhase == .began }
    let ends = replay.filter { ScrollWheelEventView($0.event).scrollPhase == .ended }
    let longest = zip(begins, ends).map { $1.time - $0.time }.max() ?? 0
    print("Observed bursts at \(Int(1/profile.timerInterval)) Hz: \(begins.count) strokes, longest \(Int((longest * 1000).rounded())) ms, travel \(detentDistance(replay)) pt")
    if begins.count != observedBursts.count || ends.count != begins.count {
        timingFailures.append("Separate wheel bursts were joined or left open")
    }
    for (burst, pair) in zip(observedBursts, zip(begins, ends)) {
        let firstPacketTime = Double(burst[0].ms) / 1000
        require(pair.0.time < pair.1.time, "Empty or unbalanced touch")
        require(abs(ScrollWheelEventView(pair.1.event).deltaYPt) < 0.0001, "A touch end added motion")
        if pair.0.time < firstPacketTime || pair.0.time > firstPacketTime + profile.timerInterval + 0.001 {
            timingFailures.append("New stroke did not begin on the next moving frame")
        }
    }
}
// Real line deltas and relative input times during the same-page trackpad/wheel comparison.
let comparisonBursts: [[(ms: Int, lines: Int32)]] = [
    [(0, 1), (66, 1), (110, 1), (334, 1), (408, 1), (496, 1)],
    [(964, 1), (1000, 1), (1036, 2), (1134, 2), (1214, 2)],
    [(1784, 1), (1816, 1), (1852, 2), (1890, 3), (1942, 4)],
    [(2426, 1), (2452, 1), (2470, 2), (2493, 4), (2532, 4)],
    [(3052, 1), (3078, 1), (3096, 2), (3128, 4), (3192, 4)],
    [(3614, 1), (3632, 1), (3650, 3), (3668, 4), (3694, 4)],
    [(4140, 1), (4158, 1), (4176, 3), (4204, 4), (4238, 4), (4318, 4)],
    [(4678, 1), (4696, 1), (4724, 2), (4740, 4), (4776, 4)],
    [(5188, 1), (5214, 1), (5232, 2), (5250, 4), (5274, 4), (5304, 5)],
    [(5840, 1), (5858, 1), (5876, 3), (5894, 4), (5912, 5), (5956, 5)],
    [(7022, 1), (7076, 1), (7130, 1), (7282, 1), (7426, 1)],
]
let comparisonPackets = comparisonBursts.flatMap { $0 }
func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    return (sorted[(sorted.count - 1) / 2] + sorted[sorted.count / 2]) / 2
}
for profile in [SmoothedScrollingDeliveryProfile.iPhoneMirroring, .mirror30Hz] {
    let frames = steadyWheel(speed: nil, usesMirrorWheelTuning: true,
        times: comparisonPackets.map { Double($0.ms) / 1000 },
        eventAtIndex: { wheel(-comparisonPackets[$0].lines) }, profile: profile)
    let starts = frames.filter { ScrollWheelEventView($0.event).scrollPhase == .began }.map(\.time)
    let ends = frames.filter { ScrollWheelEventView($0.event).scrollPhase == .ended }.map(\.time)
    require(starts.count == comparisonBursts.count && ends.count == starts.count, "One contact per measured wheel stroke")
    let durations = zip(starts, ends).map { $1 - $0 }
    let lifts = zip(ends, starts.dropFirst()).map { $1 - $0 }
    let travel = detentDistance(frames)
    // Build 31 produced this signed total with the same input and timer.
    require(abs(travel + 7049) <= 1, "The timing comparison changed wheel travel")
    print("Same-page replay \(Int(1/profile.timerInterval)) Hz: strokes \(starts.count), median contact \(Int((median(durations)*1000).rounded())) ms, median lift \(Int((median(lifts)*1000).rounded())) ms, travel \(travel) pt")
    for (start, burst) in zip(starts, comparisonBursts) {
        let latency = start - Double(burst[0].ms) / 1000
        require(latency >= 0 && latency <= profile.timerInterval + 0.001, "A new stroke was delayed")
    }
    if !(0.18 ... 0.36).contains(median(durations)) || median(lifts) < 0.22 {
        timingFailures.append("Measured wheel strokes lacked a trackpad-like contact and lift interval")
    }
}
let burstWithoutTail = packetTurns[0].flatMap { $0 }.map { Double($0) / 1000 }
let stoppedBurst = steadyWheel(speed: nil, usesMirrorWheelTuning: true, times: burstWithoutTail, tail: 0)
require(movingFrameTimes(stoppedBurst).last! - burstWithoutTail.last! < 0.10,
        "A burst extended scrolling after the user turned the tail off")
let spaced = [0.0, 0.32, 0.64, 0.96]
let noTail = steadyWheel(speed: nil, usesMirrorWheelTuning: true, times: spaced, tail: 0)
require(movingFrameTimes(noTail).last! - spaced.last! < 0.10, "Zero tail unexpectedly extended a notch")
let isolated = movingFrameTimes(steadyWheel(speed: nil, usesMirrorWheelTuning: true, times: [0]))
let afterPause = steadyWheel(speed: nil, usesMirrorWheelTuning: true, times: [0, 1])
let restarted = movingFrameTimes(afterPause).filter { $0 >= 1 }
require(starts(afterPause) == 2 && restarted.count == isolated.count, "A fresh gesture inherited stale wheel cadence")
require(abs(restarted.last! - 1 - isolated.last!) < 1.0 / 60 + 0.000001, "A pause prolonged the next isolated stroke")
require((0.12 ... 0.20).contains(isolated.last!), "Default single notch glide was too short or drifted after release")
print("Isolated notch: last moving frame \(Int((isolated.last! * 1000).rounded())) ms")
fflush(stdout)
require(timingFailures.isEmpty, timingFailures.joined(separator: ", "))

now = 0
let desktop = SmoothedScrollingTransformer(smoothed: tuning, now: { now }, eventSink: { _ in })
_ = desktop.transform(wheel(1), in: .init(device: nil))
require(abs(EventThread.shared.lastInterval - 1.0 / 120.0) < 0.000001, "Desktop cadence changed")
desktop.deactivate()
print("PASS: production mirror transformer, 60 Hz single stream, full phases with bouncing off, signed total distance, subpixel carry, idle stop, touch/momentum cleanup, desktop cadence")
print("Reference distance: \(referenceDistance), delivered point distance: \(pointDistance), frames: \(delivered.count)")
print("PASS: single precision wheel startup and small reversal at 30/60 Hz on both axes")
print("0 input events posted; iPhone Mirroring smoothness still requires user testing")
'''
(work / "main.swift").write_text(main)
sources.append(work / "main.swift")
command = base + ["-swift-version", "5", "-Onone", "-I", str(work), "-L", str(work), "-lGestureKit",
    "-Xlinker", "-rpath", "-Xlinker", str(work), "-framework", "IOKit", "-framework", "SceneKit",
    "-import-objc-header", str(root / "LinearMouse/LinearMouse-Bridging-Header.h"),
    *map(str, sources), "-o", str(work / "validate-mirror-smoothing")]
print(f"Building production mirror smoothing probe in {work}", flush=True)
subprocess.run(command, check=True)
subprocess.run([str(work / "validate-mirror-smoothing")], check=True)
