// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import SwiftUI

extension ScrollingSettings.ModifierKeysSection {
    struct ModifierKeyActionPicker: View {
        var label: String
        @Binding var action: Scheme.Scrolling.Modifiers.Action?

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(label)
                        .font(.body.weight(.medium))
                    Spacer(minLength: 12)
                    Picker(label, selection: $action.kind) {
                        ForEach(ActionType.allCases) { type in
                            type.label.tag(type)
                            if type == .defaultAction || type == .noAction { Divider() }
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 210)
                    .accessibilityLabel(Text(verbatim: label))
                }
                .frame(minHeight: 26)
                if case .some(.changeSpeed) = action {
                    HStack(spacing: 10) {
                        Text("Speed multiplier").foregroundColor(.secondary)
                        Spacer(minLength: 12)
                        CompactSettingsSlider(title: String(format: NSLocalizedString("%@ speed multiplier", comment: ""), label), value: $action.speedFactor, range: 0.05 ... 10)
                            .frame(width: 110, height: 18)
                        Text(verbatim: String(format: "%0.2f ×", $action.speedFactor.wrappedValue))
                            .monospacedDigit()
                            .frame(width: 65, alignment: .trailing)
                    }
                }
            }
            .help(String(format: NSLocalizedString("Hold %@ while scrolling to perform the selected action.", comment: ""), label))
        }
    }
}

extension ScrollingSettings.ModifierKeysSection.ModifierKeyActionPicker {
    typealias ActionType = Scheme.Scrolling.Modifiers.Action.Kind
}
