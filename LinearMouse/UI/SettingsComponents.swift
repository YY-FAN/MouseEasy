// SPDX-License-Identifier: MIT
// Copyright (c) 2026 WheelEase contributors

import SwiftUI

// Measure the settings themselves, then give longer pages a bounded scroll area.
struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var contentHeight: CGFloat = 100

    private var maximumHeight: CGFloat {
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 720
        return min(590, max(140, visibleHeight - 112))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .background(GeometryReader { geometry in
                Color.clear.preference(key: SettingsContentHeight.self, value: geometry.size.height)
            })
        }
        .frame(height: min(contentHeight, maximumHeight))
        .padding(.horizontal, 16)
        .onPreferenceChange(SettingsContentHeight.self) { height in
            if height > 0 { contentHeight = height.rounded(.up) }
        }
        .foregroundColor(SettingsTheme.text)
        .controlSize(.regular)
    }
}

private struct SettingsContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SettingsDetailKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isSettingsDetail: Bool {
        get { self[SettingsDetailKey.self] }
        set { self[SettingsDetailKey.self] = newValue }
    }
}

enum SettingsDetailAppearance {
    static let fontSize: CGFloat = 12
    static let font = Font.system(size: fontSize)
}

extension View {
    func settingsDetailAppearance() -> some View {
        font(SettingsDetailAppearance.font)
            .foregroundColor(SettingsTheme.detailText)
            .controlSize(.small)
            .environment(\.isSettingsDetail, true)
            .padding(.leading, 22)
    }
}

struct SettingsCard<Content: View>: View {
    @Environment(\.isSettingsDetail) private var isDetail
    let title: String?
    let subtitle: String?
    let symbol: String?
    let headerAccessory: AnyView?
    private let content: Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        symbol: String? = nil,
        headerAccessory: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.headerAccessory = headerAccessory
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if title != nil {
                HStack(alignment: .center, spacing: 8) {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.body.weight(.semibold))
                            .foregroundColor(isDetail ? SettingsTheme.detailText : SettingsControlColor.accent)
                            .frame(width: 17, height: 18)
                            .accessibility(hidden: true)
                    }
                    if let title {
                        Text(verbatim: title)
                            .font(isDetail ? SettingsDetailAppearance.font : .body.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                    }
                    if let subtitle {
                        Text(verbatim: subtitle)
                            .font(isDetail ? SettingsDetailAppearance.font : .body)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .help(subtitle)
                    }
                    Spacer(minLength: 0)
                    if let headerAccessory { headerAccessory }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isDetail ? SettingsTheme.detailText.opacity(0.07) : SettingsTheme.sectionHeader)
                Divider()
            }
            VStack(alignment: .leading, spacing: 6) {
                content
                    .font(isDetail ? SettingsDetailAppearance.font : .body)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsTheme.panel)
        .cornerRadius(11)
    }
}

struct SettingsDisclosure<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .frame(width: 12)
                        .accessibilityHidden(true)
                    Text(verbatim: title)
                        .font(SettingsDetailAppearance.font)
                    Spacer(minLength: 8)
                }
                .foregroundColor(SettingsTheme.detailText)
                .padding(.leading, 2)
                .frame(minHeight: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text(expanded ? NSLocalizedString("Expanded", comment: "") : NSLocalizedString("Collapsed", comment: "")))

            if expanded {
                VStack(alignment: .leading, spacing: 7) {
                    content()
                }
                .settingsDetailAppearance()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct SettingsToggleRow: View {
    @Environment(\.isSettingsDetail) private var isDetail
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    var fillsRow = false

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: title)
                .font(isDetail ? SettingsDetailAppearance.font : .body.weight(.medium))
                .frame(width: fillsRow ? nil : 180, alignment: .leading)
            if fillsRow { Spacer(minLength: 12) }
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()
        }
        .frame(minHeight: 24)
        .help(subtitle ?? title)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityHint(Text(verbatim: subtitle ?? ""))
    }
}

enum SettingsControlLayout {
    static let spacing: CGFloat = 12
    static let labelWidth: CGFloat = 120
    static let sliderWidth: CGFloat = 240
    static let numberWidth: CGFloat = 66
}

struct SettingsControlRow<Controls: View>: View {
    @Environment(\.isSettingsDetail) private var isDetail
    let title: String
    @ViewBuilder let controls: () -> Controls

    var body: some View {
        HStack(spacing: SettingsControlLayout.spacing) {
            Text(verbatim: title)
                .font(isDetail ? SettingsDetailAppearance.font : .body.weight(.medium))
                .frame(width: SettingsControlLayout.labelWidth, alignment: .leading)
            controls()
        }
        .frame(minHeight: 24)
    }
}

struct SettingsSlider: View {
    let title: String
    var detail: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    let formatter: NumberFormatter

    var body: some View {
        SettingsControlRow(title: title) {
            CompactSettingsSlider(title: title, value: $value, range: range)
                .frame(minWidth: 120, maxWidth: SettingsControlLayout.sliderWidth)
                .frame(height: 18)
            DeferredNumberField(value: $value, formatter: formatter, range: range)
                .frame(width: SettingsControlLayout.numberWidth, height: 22)
                .accessibilityLabel(Text(verbatim: title + NSLocalizedString(" value", comment: "")))
        }
        .help(detail ?? title)
    }
}

struct SettingsPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isSettingsDetail) private var isDetail
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(isDetail ? SettingsDetailAppearance.font : .body.weight(.semibold))
            .foregroundColor(enabled ? SettingsControlColor.onAccent : .secondary)
            .padding(.horizontal, 11)
            .frame(minHeight: 27)
            .background(enabled ? SettingsControlColor.accent.opacity(configuration.isPressed ? 0.78 : 1) : Color.secondary.opacity(0.12))
            .cornerRadius(7)
            .contentShape(Rectangle())
    }
}

struct SettingsSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isSettingsDetail) private var isDetail
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(isDetail ? SettingsDetailAppearance.font : .body.weight(.semibold))
            .foregroundColor(enabled ? SettingsControlColor.accent : .secondary)
            .padding(.horizontal, 9)
            .frame(minHeight: 27)
            .background(enabled ? SettingsControlColor.accent.opacity(configuration.isPressed ? 0.23 : 0.11) : Color.secondary.opacity(0.06))
            .cornerRadius(7)
            .contentShape(Rectangle())
    }
}

struct SettingsScopeButtonStyle: ButtonStyle {
    var isSpecific = false

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        HStack(spacing: 5) {
            configuration.label
                .font(.system(size: 12, weight: isSpecific ? .semibold : .regular))
                .lineLimit(1)
                .frame(maxWidth: 108)
                .fixedSize(horizontal: true, vertical: false)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .medium))
                .accessibilityHidden(true)
        }
        .foregroundColor(isSpecific ? SettingsControlColor.accent : .secondary)
        .padding(.horizontal, 8)
        .frame(minHeight: 24)
        .background(
            isSpecific
                ? SettingsControlColor.accent.opacity(configuration.isPressed ? 0.18 : 0.10)
                : Color.primary.opacity(configuration.isPressed ? 0.10 : 0.045)
        )
        .cornerRadius(5)
        .contentShape(Rectangle())
    }
}

struct SettingsDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isSettingsDetail) private var isDetail
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(isDetail ? SettingsDetailAppearance.font : .body.weight(.semibold))
            .foregroundColor(enabled ? .red : .secondary)
            .padding(.horizontal, 8)
            .frame(minHeight: 27)
            .background(enabled ? Color.red.opacity(configuration.isPressed ? 0.18 : 0.08) : Color.secondary.opacity(0.06))
            .cornerRadius(7)
            .contentShape(Rectangle())
    }
}

enum SettingsControlColor {
    static let accent = Color(SettingsTheme.action)
    static let onAccent = Color(SettingsTheme.actionText)
}

enum SettingsTheme {
    private static func dynamic(_ name: String, light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> NSColor {
        NSColor(name: NSColor.Name("WheelEase." + name)) { appearance in
            let values = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: values.0, green: values.1, blue: values.2, alpha: 1)
        }
    }
    static let action = dynamic("Action", light: (0.188, 0.412, 0.322), dark: (0.580, 0.855, 0.722))
    static let actionText = dynamic("ActionText", light: (1.000, 1.000, 1.000), dark: (0.078, 0.173, 0.125))
    static let windowBackground = dynamic("Canvas", light: (0.957, 0.965, 0.957), dark: (0.102, 0.125, 0.110))
    static let canvas = Color(windowBackground)
    static let panel = Color(dynamic("Panel", light: (0.988, 0.992, 0.976), dark: (0.125, 0.173, 0.149)))
    static let sectionHeader = Color(dynamic("SectionHeader", light: (0.925, 0.954, 0.933), dark: (0.163, 0.232, 0.188)))
    static let text = Color(dynamic("Text", light: (0.145, 0.227, 0.184), dark: (0.910, 0.941, 0.910)))
    static let detailText = Color(dynamic("DetailText", light: (0.330, 0.396, 0.363), dark: (0.722, 0.776, 0.733)))
}
