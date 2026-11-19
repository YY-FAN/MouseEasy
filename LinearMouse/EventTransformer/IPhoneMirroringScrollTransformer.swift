// MIT License
// Independently implemented for this build. No Mos implementation is included.

import CoreGraphics

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
