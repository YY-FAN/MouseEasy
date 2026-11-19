// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct AccessibilityPermissionView: View {
    var eventTapFailed = false
    var permissionNaming = AccessibilityPermission.Naming.current

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .accessibility(hidden: true)
                .padding(.bottom, 14)

            Text(verbatim: LinearMouse.appName)
                .font(.system(size: 26, weight: .bold))
                .padding(.bottom, 16)

            explanation
                .font(.system(size: 14))
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if permissionNaming.formerNameKey != nil, !eventTapFailed {
                permissionFootnote
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }

            primaryButton
                .padding(.top, 24)
            if !eventTapFailed {
                Text("Find MouseEasy in System Settings and turn on its switch.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
            helpLink
                .font(.system(size: 15))
                .padding(.top, 16)
        }
        .padding(.horizontal, 32)
        .padding(.top, 40)
        .padding(.bottom, 28)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var explanation: Text {
        if eventTapFailed {
            return Text(verbatim: brandedLocalization(
                "LinearMouse could not start mouse input processing. Restart LinearMouse. If the problem persists, get more help."
            ))
        }
        // Keep the sentence in one localization so each language controls its word order.
        let parts = brandedLocalization(
            "LinearMouse needs %@ permission to customize scrolling, pointer movement, and mouse buttons."
        ).components(separatedBy: "%@")
        let permission = Text(NSLocalizedString(permissionNaming.settingsPaneKey, comment: "")).bold()
        var marker = Text(verbatim: "")
        if permissionNaming.formerNameKey != nil {
            marker = Text(verbatim: "1").font(.system(size: 10)).baselineOffset(5)
        }
        return Text(parts[0]) + permission + marker + Text(parts.dropFirst().joined(separator: "%@"))
    }

    private var permissionFootnote: Text {
        let parts = NSLocalizedString(
            "Called %@ in earlier versions of macOS.",
            comment: "Footnote explaining the system permission name in earlier macOS versions."
        ).components(separatedBy: "%@")
        let formerName = NSLocalizedString(permissionNaming.formerNameKey ?? "Accessibility", comment: "")
        return Text("¹ " + parts[0]) + Text(formerName).bold()
            + Text(parts.dropFirst().joined(separator: "%@"))
    }

    private var actionButton: some View {
        Button(action: {
            if eventTapFailed {
                Application.restart()
            } else {
                AccessibilityPermissionWindow.shared.beginAuthorization()
            }
        }) {
            Label(eventTapFailed ? NSLocalizedString("Restart MouseEasy", comment: "") : NSLocalizedString("Open System Settings", comment: ""), systemImage: "lock.shield")
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var primaryButton: some View {
        actionButton
            .buttonStyle(SettingsPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
    }

    private var helpLink: some View {
        HyperLink(URL(string: "https://go.linearmouse.app/accessibility-permission")!) {
            Text("Get more help")
        }
    }

    /// Reuse upstream translations while showing this app's product name.
    private func brandedLocalization(_ key: String) -> String {
        LinearMouse.brandedLocalization(key)
    }
}

struct AccessibilityPermissionView_Previews: PreviewProvider {
    static var previews: some View {
        AccessibilityPermissionView()
    }
}
