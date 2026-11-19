// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

/// Uses AppKit's slider tracking, keyboard and accessibility behavior with a thinner rail.
struct CompactSettingsSlider: NSViewRepresentable {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    @Environment(\.isEnabled) private var isEnabled

    init(title: String, value: Binding<Double>, range: ClosedRange<Double>) {
        self.title = title
        _value = value
        self.range = range
    }

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider()
        slider.cell = ThinRailSliderCell()
        slider.sliderType = .linear
        slider.isContinuous = true
        slider.controlSize = .small
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changeValue(_:))
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        slider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.value = $value
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.isEnabled = isEnabled
        slider.setAccessibilityLabel(title)
        let boundedValue = min(max(value, range.lowerBound), range.upperBound)
        if slider.doubleValue != boundedValue {
            slider.doubleValue = boundedValue
        }
    }

    final class Coordinator: NSObject {
        var value: Binding<Double>

        init(value: Binding<Double>) { self.value = value }

        @objc func changeValue(_ slider: NSSlider) {
            value.wrappedValue = slider.doubleValue
        }
    }
}

private final class ThinRailSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let rail = NSRect(x: rect.minX, y: rect.midY - 1, width: rect.width, height: 2)
        let outline = NSBezierPath(roundedRect: rail, xRadius: 1, yRadius: 1)
        NSColor.secondaryLabelColor.withAlphaComponent(0.22).setFill()
        outline.fill()

        guard isEnabled else { return }
        let knobCenter = min(max(knobRect(flipped: flipped).midX, rail.minX), rail.maxX)
        let isRightToLeft = controlView?.userInterfaceLayoutDirection == .rightToLeft
        let leading = isRightToLeft ? knobCenter : rail.minX
        let trailing = isRightToLeft ? rail.maxX : knobCenter
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        SettingsTheme.action.setFill()
        NSBezierPath.fill(NSRect(x: leading, y: rail.minY, width: trailing - leading, height: rail.height))
        NSGraphicsContext.restoreGraphicsState()
    }

    override func drawKnob(_ knobRect: NSRect) {
        super.drawKnob(knobRect.insetBy(dx: 1, dy: 1))
    }
}
