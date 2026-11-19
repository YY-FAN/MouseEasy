// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import GestureKit
import os.log

final class SmoothedScrollingTransformer: EventTransformer, Deactivatable {
    var handlesPointerMotion: Bool {
        false
    }

    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier!, category: "SmoothedScrolling"
    )
    private let smoothed: Scheme.Scrolling.Bidirectional<Scheme.Scrolling.Smoothed>
    private let deliveryProfile: SmoothedScrollingDeliveryProfile
    private let usesMirrorWheelTuning: Bool
    private let preserveContinuousScrolling: Bool
    private let highResolutionWheelMultiplier: (EventTransformerContext) -> Int?
    private let now: () -> TimeInterval
    private let eventSink: (CGEvent) -> Void
    private let delivery = SmoothedScrollEventDelivery()
    private var mirrorWheelMotion = MirrorWheelMotion()

    private var engine: SmoothedScrollingEngine
    private var timer: EventThreadTimer?
    private var lastFlags: CGEventFlags = []
    private var syntheticGestureScrollSeriesActive = false
    private var syntheticMomentumScrollActive = false

    init(
        smoothed: Scheme.Scrolling.Bidirectional<Scheme.Scrolling.Smoothed>,
        deliveryProfile: SmoothedScrollingDeliveryProfile = .standard,
        usesMirrorWheelTuning: Bool = false,
        preserveContinuousScrolling: Bool = false,
        highResolutionWheelMultiplier: @escaping (EventTransformerContext) -> Int? = {
            $0.device?.highResolutionWheelNormalizationMultiplier
        },
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        eventSink: @escaping (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) }
    ) {
        self.smoothed = smoothed
        self.deliveryProfile = deliveryProfile
        self.usesMirrorWheelTuning = usesMirrorWheelTuning
        self.preserveContinuousScrolling = preserveContinuousScrolling
        self.highResolutionWheelMultiplier = highResolutionWheelMultiplier
        self.now = now
        self.eventSink = eventSink
        engine = SmoothedScrollingEngine(smoothed: smoothed)
    }

    func transform(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent? {
        guard event.type == .scrollWheel else {
            return event
        }

        if event.bypassesSmoothedScrolling {
            // Direction reversal has already run upstream. Clear the transient
            // marker before delivery and stop the old tail when changing modes.
            event.bypassesSmoothedScrolling = false
            deactivate()
            return event
        }

        let view = ScrollWheelEventView(event)

        if event.isLinearMouseSyntheticEvent {
            return event
        }

        if preserveContinuousScrolling && view.continuous {
            if timer != nil {
                deactivate()
            } else {
                mirrorWheelMotion = MirrorWheelMotion()
            }
            return event
        }

        let rawDelta = SIMD2(deltaXInPixels(from: view, in: context), deltaYInPixels(from: view, in: context))
        let hasNativePhase = view.scrollPhase != nil
        let hasNativeMomentum = view.momentumPhase != .none
        let isNativeGesture = view.continuous && (hasNativePhase || hasNativeMomentum)
        let delta = usesMirrorWheelTuning && !isNativeGesture ? Self.dominantWheelDelta(rawDelta) : rawDelta

        let smoothsX = smoothed.horizontal != nil
        let smoothsY = smoothed.vertical != nil
        let handlesX = smoothsX && delta.x != 0
        let handlesY = smoothsY && delta.y != 0
        // Consume both original axes even if one was removed as wheel noise.
        let interceptsX = smoothsX && rawDelta.x != 0
        let interceptsY = smoothsY && rawDelta.y != 0

        if isNativeGesture {
            if mirrorWheelMotion.isRunning {
                endSyntheticGestureScrollSeriesIfNeeded(phase: .cancelled)
                stopTimer()
                delivery.resetPointDeltaRemainders()
            }
            mirrorWheelMotion = MirrorWheelMotion()
            return transformNativeContinuousGesture(
                event,
                view: view,
                deltaX: delta.x,
                deltaY: delta.y,
                handlesX: handlesX,
                handlesY: handlesY
            )
        }

        guard interceptsX || interceptsY else {
            return event
        }

        if handlesX || handlesY {
            lastFlags = event.flags
            let input = SIMD2(handlesX ? delta.x : 0, handlesY ? delta.y : 0)
            let timestamp = now()
            if usesMirrorWheelTuning {
                if mirrorWheelMotion.changesAxis(to: input) {
                    endSyntheticGestureScrollSeriesIfNeeded(phase: .cancelled)
                    mirrorWheelMotion = MirrorWheelMotion()
                    delivery.resetPointDeltaRemainders()
                }
                mirrorWheelMotion.feed(input, at: timestamp, tuning: smoothed.vertical ?? smoothed.horizontal)
            } else {
                if handlesX != handlesY {
                    engine.resetOtherAxis(ifExclusiveIncomingAxis: handlesX ? .horizontal : .vertical)
                }
                engine.feed(
                    deltaX: input.x,
                    deltaY: input.y,
                    timestamp: timestamp,
                    inputKind: .wheel,
                    wheelResolutionMultiplier: highResolutionWheelMultiplier(context) ?? 1
                )
            }
            startTimerIfNeeded()
        }

        let passthroughEvent = event.copy() ?? event
        let passthroughView = ScrollWheelEventView(passthroughEvent)
        if interceptsX {
            delivery.zeroHorizontal(on: passthroughView)
        }
        if interceptsY {
            delivery.zeroVertical(on: passthroughView)
        }

        return delivery.deltaXInPixels(from: passthroughView) == 0
            && delivery.deltaYInPixels(from: passthroughView) == 0
            ? nil
            : passthroughEvent
    }

    private static func dominantWheelDelta(_ delta: SIMD2<Double>) -> SIMD2<Double> {
        let horizontal = abs(delta.x)
        let vertical = abs(delta.y)
        // Suppress a much smaller off-axis sample from a mouse wheel. Pure
        // sideways input and deliberate two-axis motion keep their direction.
        if vertical > horizontal * 6 { return SIMD2(0, delta.y) }
        if horizontal > vertical * 6 { return SIMD2(delta.x, 0) }
        return delta
    }

    func deactivate() {
        endSyntheticGestureScrollSeriesIfNeeded(phase: .cancelled)
        stopTimer()
        mirrorWheelMotion = MirrorWheelMotion()
        engine = SmoothedScrollingEngine(smoothed: smoothed)
        delivery.resetPointDeltaRemainders()
        lastFlags = []
        syntheticMomentumScrollActive = false
    }

    private func startTimerIfNeeded() {
        guard timer == nil else {
            return
        }

        timer = EventThread.shared.scheduleTimer(
            interval: deliveryProfile.timerInterval,
            repeats: true
        ) { [weak self] in
            self?.tick()
        }
    }

    private func transformNativeContinuousGesture(
        _ event: CGEvent,
        view: ScrollWheelEventView,
        deltaX: Double,
        deltaY: Double,
        handlesX: Bool,
        handlesY: Bool
    ) -> CGEvent? {
        let interceptsX = smoothed.horizontal != nil
        let interceptsY = smoothed.vertical != nil

        guard interceptsX || interceptsY else {
            return event
        }

        lastFlags = event.flags

        if handlesX || handlesY {
            if handlesX != handlesY {
                engine.resetOtherAxis(ifExclusiveIncomingAxis: handlesX ? .horizontal : .vertical)
            }
            engine.feed(
                deltaX: handlesX ? deltaX : 0,
                deltaY: handlesY ? deltaY : 0,
                timestamp: now(),
                inputKind: .continuousGesture
            )
        }

        let shouldResetAfterNativePhase = view.scrollPhase == .ended || view.momentumPhase == .end
        let appliesPhases = allowsBouncingForConfiguredAxes(interceptsX: interceptsX, interceptsY: interceptsY)

        if let emission = engine.advance(to: now()) {
            delivery.apply(
                phases: delivery.phasesFor(emission.phase, appliesPhases: appliesPhases),
                to: view
            )

            if interceptsX {
                delivery.setHorizontal(handlesX ? emission.deltaX : 0, on: view)
            }
            if interceptsY {
                delivery.setVertical(handlesY ? emission.deltaY : 0, on: view)
            }
        } else {
            if interceptsX, !handlesX {
                delivery.zeroHorizontal(on: view)
            }
            if interceptsY, !handlesY {
                delivery.zeroVertical(on: view)
            }
        }

        if shouldResetAfterNativePhase {
            engine = SmoothedScrollingEngine(smoothed: smoothed)
            stopTimer()
            delivery.resetPointDeltaRemainders()
        }

        return event
    }

    private func deltaXInPixels(from view: ScrollWheelEventView, in context: EventTransformerContext) -> Double {
        guard let multiplier = highResolutionWheelMultiplier(context),
              multiplier > 1,
              !view.continuous else {
            return delivery.deltaXInPixels(from: view)
        }

        let unitResolution = LogitechHighResolutionWheelUnitReader.horizontalUnitResolution(
            from: view,
            multiplier: multiplier
        )
        let smoothedUnits = Self.smoothedHighResolutionUnits(from: unitResolution)
        return smoothedUnits
            * SmoothedScrollEventDelivery.inputLineStepInPoints
            / Double(multiplier)
    }

    private func deltaYInPixels(from view: ScrollWheelEventView, in context: EventTransformerContext) -> Double {
        guard let multiplier = highResolutionWheelMultiplier(context),
              multiplier > 1,
              !view.continuous else {
            return delivery.deltaYInPixels(from: view)
        }

        let unitResolution = LogitechHighResolutionWheelUnitReader.verticalUnitResolution(
            from: view,
            multiplier: multiplier
        )
        let smoothedUnits = Self.smoothedHighResolutionUnits(from: unitResolution)
        return smoothedUnits
            * SmoothedScrollEventDelivery.inputLineStepInPoints
            / Double(multiplier)
    }

    static func smoothedHighResolutionUnits(
        from unitResolution: LogitechHighResolutionWheelUnitReader.UnitResolution
    ) -> Double {
        let rawMagnitude = abs(unitResolution.rawUnits)
        guard rawMagnitude > 1 else {
            return unitResolution.rawUnits
        }

        let acceleratedMagnitude = abs(unitResolution.units)
        let accelerationConfidence = 1 - 1 / rawMagnitude
        let magnitude = rawMagnitude + (acceleratedMagnitude - rawMagnitude) * accelerationConfidence
        return unitResolution.rawUnits.sign == .minus ? -magnitude : magnitude
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func tick() {
        let timestamp = now()
        let emission: SmoothedScrollingEngine.Emission?
        if usesMirrorWheelTuning {
            emission = mirrorWheelMotion.advance(to: timestamp)
        } else {
            emission = engine.advance(to: timestamp)
        }
        if let emission { post(emission: emission) }

        let isRunning = usesMirrorWheelTuning ? mirrorWheelMotion.isRunning : engine.isRunning
        if !isRunning {
            stopTimer()
            delivery.resetPointDeltaRemainders()
        }
    }

    private func post(emission: SmoothedScrollingEngine.Emission) {
        guard
            let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: 0,
                wheel2: 0,
                wheel3: 0
            )
        else {
            return
        }

        let view = ScrollWheelEventView(event)
        view.continuous = true
        let accumulatesSubpixelDelta = emission.phase.accumulatesSyntheticSubpixelDelta
            || deliveryProfile.accumulatesMomentumSubpixels
        delivery.setSyntheticHorizontal(
            emission.deltaX,
            on: view,
            accumulatesSubpixelDelta: accumulatesSubpixelDelta
        )
        delivery.setSyntheticVertical(
            emission.deltaY,
            on: view,
            accumulatesSubpixelDelta: accumulatesSubpixelDelta
        )

        guard let phase = syntheticPhase(for: emission.phase, hasDelta: delivery.hasDelta(on: view)) else {
            return
        }

        if deliveryProfile.preservesScrollPhases, syntheticMomentumScrollActive, case .touchBegan = phase {
            endSyntheticGestureScrollSeriesIfNeeded(phase: .cancelled)
        }

        let phases = delivery.phasesFor(phase, appliesPhases: allowsBouncingForConfiguredAxes())
        delivery.apply(phases: phases, to: view)
        guard view.scrollPhase != nil || view.momentumPhase != .none || delivery.hasDelta(on: view)
        else {
            return
        }
        event.isLinearMouseSyntheticEvent = true
        event.flags = lastFlags
        let postedDeltaX = view.deltaXFixedPt
        let postedDeltaY = view.deltaYFixedPt
        postGestureScrollCompanionsIfNeeded(
            scrollPhase: phases.scrollPhase,
            deltaX: postedDeltaX,
            deltaY: postedDeltaY
        )
        eventSink(event)
        updateSyntheticMomentumState(afterPosting: phase)

        // Mirror frames are logged after the final event is rebuilt for HID delivery.
        guard deliveryProfile == .standard else { return }
        os_log(
            "post smoothed scroll deltaX=%{public}.3f deltaY=%{public}.3f phase=%{public}@ momentum=%{public}@",
            log: Self.log,
            type: .info,
            postedDeltaX,
            postedDeltaY,
            String(describing: view.scrollPhase),
            String(describing: view.momentumPhase)
        )
    }

    private func syntheticPhase(
        for phase: SmoothedScrollingEngine.Phase,
        hasDelta: Bool
    ) -> SmoothedScrollingEngine.Phase? {
        switch phase {
        case .touchBegan:
            return hasDelta ? .touchBegan : nil
        case .touchChanged:
            guard hasDelta else {
                return nil
            }
            return syntheticGestureScrollSeriesActive ? .touchChanged : .touchBegan
        case .touchEnded:
            return syntheticGestureScrollSeriesActive ? .touchEnded : nil
        case .momentumBegan:
            return hasDelta ? .momentumBegan : nil
        case .momentumChanged:
            guard hasDelta else {
                return nil
            }
            return syntheticMomentumScrollActive ? .momentumChanged : .momentumBegan
        case .momentumEnded:
            return syntheticMomentumScrollActive ? .momentumEnded : nil
        }
    }

    private func updateSyntheticMomentumState(afterPosting phase: SmoothedScrollingEngine.Phase) {
        switch phase {
        case .momentumBegan:
            syntheticMomentumScrollActive = true
        case .momentumEnded:
            syntheticMomentumScrollActive = false
        case .touchBegan, .touchChanged, .touchEnded, .momentumChanged:
            break
        }
    }

    private func postGestureScrollCompanionsIfNeeded(
        scrollPhase: CGScrollPhase?,
        deltaX: Double,
        deltaY: Double
    ) {
        guard let scrollPhase else { return }
        // A second private gesture stream can be interpreted separately by the
        // mirror. Its continuous wheel phases already describe the full scroll.
        if !deliveryProfile.emitsGestureCompanions {
            if scrollPhase == .began { syntheticGestureScrollSeriesActive = true }
            if scrollPhase == .ended || scrollPhase == .cancelled {
                syntheticGestureScrollSeriesActive = false
            }
            return
        }
        guard let gesturePhase = CGSGesturePhase(scrollPhase: scrollPhase) else { return }

        if scrollPhase == .began, !syntheticGestureScrollSeriesActive {
            GestureEvent(
                scrollSource: nil,
                phase: .mayBegin,
                deltaX: 0,
                deltaY: 0,
                flags: lastFlags
            )?.send(to: eventSink)
            GestureEvent(
                scrollSeriesSource: nil,
                started: true,
                flags: lastFlags
            )?.send(to: eventSink)
            syntheticGestureScrollSeriesActive = true
        }

        GestureEvent(
            scrollSource: nil,
            phase: gesturePhase,
            deltaX: deltaX,
            deltaY: deltaY,
            flags: lastFlags
        )?.send(to: eventSink)

        if scrollPhase == .ended || scrollPhase == .cancelled {
            GestureEvent(
                scrollSeriesSource: nil,
                started: false,
                flags: lastFlags
            )?.send(to: eventSink)
            syntheticGestureScrollSeriesActive = false
        }
    }

    private func endSyntheticGestureScrollSeriesIfNeeded(phase: CGSGesturePhase) {
        if !deliveryProfile.emitsGestureCompanions {
            guard syntheticGestureScrollSeriesActive || syntheticMomentumScrollActive,
                  let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                      wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0) else { return }
            let view = ScrollWheelEventView(event)
            view.continuous = true
            view.scrollPhase = syntheticGestureScrollSeriesActive ? .cancelled : nil
            view.momentumPhase = syntheticMomentumScrollActive ? .end : .none
            event.isLinearMouseSyntheticEvent = true
            event.flags = lastFlags
            eventSink(event)
            syntheticGestureScrollSeriesActive = false
            syntheticMomentumScrollActive = false
            return
        }
        guard syntheticGestureScrollSeriesActive else {
            return
        }

        GestureEvent(
            scrollSource: nil,
            phase: phase,
            deltaX: 0,
            deltaY: 0,
            flags: lastFlags
        )?.send(to: eventSink)
        GestureEvent(
            scrollSeriesSource: nil,
            started: false,
            flags: lastFlags
        )?.send(to: eventSink)
        syntheticGestureScrollSeriesActive = false
    }

    private func allowsBouncingForConfiguredAxes(
        interceptsX: Bool = true,
        interceptsY: Bool = true
    ) -> Bool {
        // A mirror stream needs begin/change/end even when elastic edge
        // bouncing is disabled for ordinary desktop applications.
        if deliveryProfile.preservesScrollPhases { return true }
        if interceptsX, smoothed.horizontal?.allowsBouncing == false {
            return false
        }
        if interceptsY, smoothed.vertical?.allowsBouncing == false {
            return false
        }
        return true
    }
}

private struct MirrorWheelMotion {
    private struct Pulse {
        var distance: SIMD2<Double>
        let start: TimeInterval
        let duration: TimeInterval
        var delivered = 0.0

        mutating func advance(to time: TimeInterval) -> SIMD2<Double> {
            let t = ((time - start) / duration).clamped(to: 0 ... 1)
            let progress = t == 1 ? 1 : max(delivered, t + t * t * (1 - t))
            defer { delivered = progress }
            return distance * (progress - delivered)
        }
    }

    private var pulses: [Pulse] = []
    private var lastInput: TimeInterval?
    private var burstHasMultiplePackets = false
    private var previousBurstGap: TimeInterval?
    private var endDelay: TimeInterval = 0.30
    private var lastAxis: Int?
    private var lastDirection = SIMD2<Double>.zero

    private(set) var isRunning = false

    func changesAxis(to input: SIMD2<Double>) -> Bool {
        guard let current = Self.exclusiveAxis(of: input), let lastAxis else { return false }
        return lastAxis != current
    }

    mutating func feed(_ input: SIMD2<Double>, at time: TimeInterval, tuning: Scheme.Scrolling.Smoothed?) {
        let gap = lastInput.map { time - $0 } ?? .infinity
        let reverses = (0 ..< 2).contains { axis in
            input[axis] != 0 && lastDirection[axis] != 0 && input[axis].sign != lastDirection[axis].sign
        }
        let continuesGesture = isRunning && !reverses
        isRunning = true
        lastInput = time
        lastAxis = Self.exclusiveAxis(of: input)
        lastDirection = input

        // Discard pending motion on an old axis or in the opposite direction.
        for index in pulses.indices {
            for axis in 0 ..< 2 where input[axis] == 0 || pulses[index].distance[axis].sign != input[axis].sign {
                pulses[index].distance[axis] = 0
            }
        }
        pulses.removeAll { $0.distance == .zero }

        var distance = input
        if gap >= 0.05 || reverses {
            let dominant = abs(input.x) > abs(input.y) ? 0 : 1
            let floor = MirrorScrollSettings.minimumWheelNotchInput
            let axisInput = input[dominant]
            distance[dominant] = max(abs(axisInput), floor) * (axisInput < 0 ? -1 : 1)
        }

        // Match the previous distance at a steady turn while giving separated
        // notches a full stroke. Packet bursts keep their decoded magnitude.
        let gain = continuesGesture ? (1.55 + (gap - 0.07) * 13.1).clamped(to: 1.30 ... 2.73) : 2.60
        let defaultSpeed = MirrorScrollSettings().scrollSpeed
        let speed = (tuning?.speed?.asTruncatedDouble ?? defaultSpeed).clamped(to: 0.1 ... 4)
        let response = (tuning?.response?.asTruncatedDouble ?? 0.62).clamped(to: 0 ... 2)
        let tail = (tuning?.duration?.asTruncatedDouble ?? 0.18).clamped(to: 0 ... 0.8)
        let baseDuration = (0.075 + tail * 0.5 - response * 0.022).clamped(to: 0.065 ... 0.32)
        // Overlap repeated notches slightly. Beyond the longest useful glide,
        // taper back to an isolated stroke instead of cutting at one interval.
        let longestGlide = min(2 * tail, 0.42)
        let spacedDuration = reverses ? 0 : min(1.10 * gap, longestGlide, 2 * longestGlide - gap)
        // Some wheels send several packets 10–100 ms apart on each slow turn.
        // The short spacing describes a single burst, not the rhythm of the hand.
        let withinBurst = !reverses && gap < 0.12
        if withinBurst {
            burstHasMultiplePackets = true
        } else {
            previousBurstGap = !reverses && burstHasMultiplePackets && gap <= 0.70 ? gap : nil
            burstHasMultiplePackets = false
        }
        let burstDuration = withinBurst ? min(previousBurstGap ?? 0, 2.5 * tail, 0.45) : 0
        let duration = max(baseDuration, spacedDuration, burstDuration)
        // Leave room for the next physical notch to arrive slightly late.
        // This extends only the open phase, not the distance or the animation.
        endDelay = max(0.30, duration + 0.05)
        let speedGain = (0.85 + 0.4 * speed) / (0.85 + 0.4 * defaultSpeed)
        pulses.append(.init(distance: distance * (gain * speedGain), start: time, duration: duration))
    }

    mutating func advance(to time: TimeInterval) -> SmoothedScrollingEngine.Emission? {
        guard isRunning, let lastInput else { return nil }
        var delta = SIMD2<Double>.zero
        for index in pulses.indices {
            delta += pulses[index].advance(to: time)
        }
        pulses.removeAll { $0.delivered >= 1 }
        if delta != .zero {
            return .init(deltaX: delta.x, deltaY: delta.y, phase: .touchChanged)
        }
        // A slow wheel turn remains one touch series. The easing already
        // settles the motion to zero, so no separate momentum swipe is needed.
        if pulses.isEmpty, time - lastInput >= endDelay {
            // End the touch on time, but let the next wheel notch measure the
            // physical interval even if the timer stopped between notches.
            isRunning = false
            return .init(deltaX: 0, deltaY: 0, phase: .touchEnded)
        }
        return nil
    }

    private static func exclusiveAxis(of input: SIMD2<Double>) -> Int? {
        if input.x == 0 { return 1 }
        if input.y == 0 { return 0 }
        return nil
    }
}

extension CGEvent {
    /// Internal, single-pass marker between modifier handling and smoothing.
    /// This value is deliberately distinct from posted/synthetic-event markers.
    private static let smoothingBypassUserData: Int64 = 0x4D57_4259_5041

    var bypassesSmoothedScrolling: Bool {
        get { getIntegerValueField(.eventSourceUserData) == Self.smoothingBypassUserData }
        set { setIntegerValueField(.eventSourceUserData, value: newValue ? Self.smoothingBypassUserData : 0) }
    }
}

private extension CGSGesturePhase {
    init?(scrollPhase: CGScrollPhase) {
        guard let rawValue = UInt8(exactly: scrollPhase.rawValue) else {
            return nil
        }
        self.init(rawValue: rawValue)
    }
}

private extension SmoothedScrollingEngine.Phase {
    var accumulatesSyntheticSubpixelDelta: Bool {
        switch self {
        case .touchBegan, .touchChanged, .touchEnded:
            return true
        case .momentumBegan, .momentumChanged, .momentumEnded:
            return false
        }
    }
}

private final class SmoothedScrollEventDelivery {
    static let inputLineStepInPoints = 36.0
    private static let outputLineStepInPoints = 12.0
    private var pointDeltaAccumulator = SmoothedScrollPointDeltaAccumulator()

    func resetPointDeltaRemainders() {
        pointDeltaAccumulator.reset()
    }

    func apply(
        phases: (scrollPhase: CGScrollPhase?, momentumPhase: CGMomentumScrollPhase),
        to view: ScrollWheelEventView
    ) {
        view.scrollPhase = phases.scrollPhase
        view.momentumPhase = phases.momentumPhase
    }

    func phasesFor(
        _ phase: SmoothedScrollingEngine.Phase,
        appliesPhases: Bool = true
    ) -> (scrollPhase: CGScrollPhase?, momentumPhase: CGMomentumScrollPhase) {
        guard appliesPhases else {
            return (nil, .none)
        }

        switch phase {
        case .touchBegan:
            return (.began, .none)
        case .touchChanged:
            return (.changed, .none)
        case .touchEnded:
            return (.ended, .none)
        case .momentumBegan:
            return (nil, .begin)
        case .momentumChanged:
            return (nil, .continuous)
        case .momentumEnded:
            return (nil, .end)
        }
    }

    func deltaXInPixels(from view: ScrollWheelEventView) -> Double {
        if !view.continuous {
            if view.deltaX != 0 {
                return Double(view.deltaX) * Self.inputLineStepInPoints
            }
            if view.deltaXPt != 0 {
                return view.deltaXPt * Self.inputLineStepInPoints
            }
            if view.deltaXFixedPt != 0 {
                return view.deltaXFixedPt * Self.inputLineStepInPoints * 10
            }
        }
        if view.deltaXFixedPt != 0 {
            return view.deltaXFixedPt
        }
        if view.deltaXPt != 0 {
            return view.deltaXPt
        }
        return Double(view.deltaX) * Self.inputLineStepInPoints
    }

    func deltaYInPixels(from view: ScrollWheelEventView) -> Double {
        if !view.continuous {
            if view.deltaY != 0 {
                return Double(view.deltaY) * Self.inputLineStepInPoints
            }
            if view.deltaYPt != 0 {
                return view.deltaYPt * Self.inputLineStepInPoints
            }
            if view.deltaYFixedPt != 0 {
                return view.deltaYFixedPt * Self.inputLineStepInPoints * 10
            }
        }
        if view.deltaYFixedPt != 0 {
            return view.deltaYFixedPt
        }
        if view.deltaYPt != 0 {
            return view.deltaYPt
        }
        return Double(view.deltaY) * Self.inputLineStepInPoints
    }

    func setHorizontal(_ value: Double, on view: ScrollWheelEventView) {
        view.deltaX = integerDelta(for: value)
        view.deltaXPt = pointDeltaAccumulator.horizontalPointDelta(for: value)
        view.deltaXFixedPt = value
        view.ioHidScrollX = value
    }

    func setVertical(_ value: Double, on view: ScrollWheelEventView) {
        view.deltaY = integerDelta(for: value)
        view.deltaYPt = pointDeltaAccumulator.verticalPointDelta(for: value)
        view.deltaYFixedPt = value
        view.ioHidScrollY = value
    }

    func setSyntheticHorizontal(
        _ value: Double,
        on view: ScrollWheelEventView,
        accumulatesSubpixelDelta: Bool
    ) {
        setSyntheticHorizontalOutput(
            pointDeltaAccumulator.horizontalPointDelta(
                for: value,
                accumulates: accumulatesSubpixelDelta
            ),
            on: view
        )
    }

    func setSyntheticVertical(
        _ value: Double,
        on view: ScrollWheelEventView,
        accumulatesSubpixelDelta: Bool
    ) {
        setSyntheticVerticalOutput(
            pointDeltaAccumulator.verticalPointDelta(
                for: value,
                accumulates: accumulatesSubpixelDelta
            ),
            on: view
        )
    }

    func zeroHorizontal(on view: ScrollWheelEventView) {
        view.deltaX = 0
        view.deltaXPt = 0
        view.deltaXFixedPt = 0
        view.ioHidScrollX = 0
    }

    func zeroVertical(on view: ScrollWheelEventView) {
        view.deltaY = 0
        view.deltaYPt = 0
        view.deltaYFixedPt = 0
        view.ioHidScrollY = 0
    }

    func hasDelta(on view: ScrollWheelEventView) -> Bool {
        view.deltaX != 0 || view.deltaY != 0 ||
            view.deltaXPt != 0 || view.deltaYPt != 0 ||
            view.deltaXFixedPt != 0 || view.deltaYFixedPt != 0 ||
            view.ioHidScrollX != 0 || view.ioHidScrollY != 0
    }

    private func setSyntheticHorizontalOutput(_ value: Double, on view: ScrollWheelEventView) {
        view.deltaX = integerDelta(for: value)
        view.deltaXPt = value
        view.deltaXFixedPt = value
        view.ioHidScrollX = value
    }

    private func setSyntheticVerticalOutput(_ value: Double, on view: ScrollWheelEventView) {
        view.deltaY = integerDelta(for: value)
        view.deltaYPt = value
        view.deltaYFixedPt = value
        view.ioHidScrollY = value
    }

    private func integerDelta(for value: Double) -> Int64 {
        Int64((value / Self.outputLineStepInPoints).rounded(.towardZero))
    }
}

struct SmoothedScrollPointDeltaAccumulator {
    private var horizontalRemainder = 0.0
    private var verticalRemainder = 0.0

    mutating func reset() {
        horizontalRemainder = 0
        verticalRemainder = 0
    }

    mutating func horizontalPointDelta(for value: Double, accumulates: Bool = true) -> Double {
        pointDelta(for: value, remainder: &horizontalRemainder, accumulates: accumulates)
    }

    mutating func verticalPointDelta(for value: Double, accumulates: Bool = true) -> Double {
        pointDelta(for: value, remainder: &verticalRemainder, accumulates: accumulates)
    }

    private func pointDelta(for value: Double, remainder: inout Double, accumulates: Bool) -> Double {
        guard accumulates else {
            remainder = 0
            return truncatedPointDelta(for: value)
        }

        let combinedValue = value + remainder
        let pointDelta = truncatedPointDelta(for: combinedValue)
        remainder = combinedValue - pointDelta

        return pointDelta
    }

    private func truncatedPointDelta(for value: Double) -> Double {
        Double(Int64(value.rounded(.towardZero)))
    }
}
