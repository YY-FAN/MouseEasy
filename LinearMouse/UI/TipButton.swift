// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

struct ProjectLinks: Decodable {
    private let repositoryAddress: String
    private let paypalAddress: String
    let paypalAccount: String

    enum CodingKeys: String, CodingKey {
        case repositoryAddress = "repository"
        case paypalAddress = "paypal"
        case paypalAccount
    }

    static let shared: Self = {
        guard let resource = Bundle.main.url(forResource: "ProjectLinks", withExtension: "plist"),
              let data = try? Data(contentsOf: resource),
              let links = try? PropertyListDecoder().decode(Self.self, from: data) else {
            return Self(repositoryAddress: "", paypalAddress: "", paypalAccount: "")
        }
        return links
    }()

    static let upstream = URL(string: "https://github.com/linearmouse/linearmouse")!
    static var license: URL? {
        Bundle.main.url(forResource: "LinearMouse-LICENSE", withExtension: "txt", subdirectory: "ThirdPartyLicenses")
            ?? Bundle.main.url(forResource: "LICENSE", withExtension: nil)
    }

    var repository: URL? {
        guard let url = Self.webURL(repositoryAddress, host: "github.com"),
              url.pathComponents.count == 3,
              url.path.lowercased() != Self.upstream.path else { return nil }
        return url
    }

    var paypal: URL? {
        guard let url = Self.webURL(paypalAddress, host: "paypal.me"),
              url.pathComponents.count == 2 else { return nil }
        return url
    }

    private static func webURL(_ address: String, host: String) -> URL? {
        guard let url = URL(string: address), url.scheme == "https", url.host?.lowercased() == host,
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil, url.path.count > 1 else { return nil }
        return url
    }
}

struct TipButton: View {
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            Text("Tip")
                .font(.body.weight(.medium))
                .foregroundColor(SettingsTheme.tipText)
                .padding(.horizontal, 5)
                .frame(minHeight: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            TipPopover()
        }
    }
}

private struct TipPopover: View {
    @State private var copied = false
    private let account = ProjectLinks.shared.paypalAccount
    private let paypalURL = ProjectLinks.shared.paypal

    var body: some View {
        VStack(spacing: 10) {
            Text(verbatim: "PayPal")
                .font(.headline)
            Text(verbatim: account)
                .font(.system(.body, design: .monospaced))
                .accessibilityLabel(Text("PayPal account"))
                .accessibilityValue(Text(verbatim: account))
            HStack(spacing: 8) {
                if let url = paypalURL {
                    Link("Open PayPal", destination: url)
                        .buttonStyle(SettingsPrimaryButtonStyle())
                }
                Button {
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(account, forType: .string)
                } label: {
                    Label {
                        if copied {
                            Text("Copied")
                        } else {
                            Text("Copy account")
                        }
                    } icon: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                }
                .buttonStyle(SettingsSecondaryButtonStyle())
                .disabled(account.isEmpty)
            }
            Text("Thank you for supporting MouseEasy!")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(minWidth: 238)
    }
}
