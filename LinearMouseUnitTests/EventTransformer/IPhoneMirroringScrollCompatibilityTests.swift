// MIT License

import CoreGraphics
@testable import LinearMouse
import XCTest

final class IPhoneMirroringScrollCompatibilityTests: XCTestCase {
    func testOnlyTargetsMouseInMirroring() {
        XCTAssertTrue(IPhoneMirroringScrollCompatibility.shouldUse(
            bundleIdentifier: "com.apple.ScreenContinuity", isMouse: true
        ))
        XCTAssertFalse(IPhoneMirroringScrollCompatibility.shouldUse(
            bundleIdentifier: "com.apple.ScreenContinuity", isMouse: false
        ))
        XCTAssertFalse(IPhoneMirroringScrollCompatibility.shouldUse(
            bundleIdentifier: "com.apple.Safari", isMouse: true
        ))
    }

    func testRebuildsReversedWheelAndRoutesToHIDWithoutPosting() throws {
        let original = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil, units: .line, wheelCount: 3,
            wheel1: -2, wheel2: 3, wheel3: 1
        ))
        original.location = CGPoint(x: 120, y: 240)
        original.flags = [.maskShift]
        var delivered: CGEvent?
        var location: CGEventTapLocation?
        XCTAssertTrue(IPhoneMirroringScrollCompatibility.post(original) { event, tap in
            delivered = event
            location = tap
        })
        let event = try XCTUnwrap(delivered)
        XCTAssertFalse(event === original)
        XCTAssertEqual(location, .cghidEventTap)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), -2)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis2), 3)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis3), 1)
        XCTAssertEqual(event.flags, original.flags)
        XCTAssertEqual(event.location, original.location)
        XCTAssertTrue(IPhoneMirroringScrollCompatibility.isReposted(event))
        XCTAssertFalse(IPhoneMirroringScrollCompatibility.isReposted(original))
        XCTAssertNil(IPhoneMirroringScrollCompatibility.makeRepostedEvent(from: event))
    }

    func testKeepsSubpixelDeltaAndZeroDeltaEndPhases() throws {
        let original = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
            wheel1: 0, wheel2: 0, wheel3: 0
        ))
        original.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -0.125)
        original.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: -0.125)
        original.setIntegerValueField(.scrollWheelEventScrollPhase, value: 4)
        original.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 3)
        let output = try XCTUnwrap(IPhoneMirroringScrollCompatibility.makeRepostedEvent(from: original))
        XCTAssertEqual(output.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
                       original.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1))
        XCTAssertEqual(output.getIntegerValueField(.scrollWheelEventScrollPhase), 4)
        XCTAssertEqual(output.getIntegerValueField(.scrollWheelEventMomentumPhase), 3)
    }
}
