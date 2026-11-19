// SPDX-License-Identifier: MIT

import CoreImage
import SwiftUI

struct ProjectLinks: Decodable {
    private let repositoryAddress: String
    private let koFi: String
    private let afdian: String

    enum CodingKeys: String, CodingKey {
        case repositoryAddress = "repository", koFi, afdian
    }

    static let shared: Self = {
        guard let resource = Bundle.main.url(forResource: "ProjectLinks", withExtension: "plist"),
              let data = try? Data(contentsOf: resource),
              let links = try? PropertyListDecoder().decode(Self.self, from: data) else {
            return Self(repositoryAddress: "", koFi: "", afdian: "")
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

    func url(for method: TipMethod) -> URL? {
        switch method {
        case .koFi: return Self.webURL(koFi, host: "ko-fi.com")
        case .afdian: return Self.webURL(afdian, host: "afdian.com")
        }
    }

    private static func webURL(_ address: String, host: String) -> URL? {
        guard let url = URL(string: address), url.scheme == "https", url.host?.lowercased() == host,
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil, url.path.count > 1 else { return nil }
        return url
    }
}

enum TipMethod: CaseIterable {
    case koFi, afdian

    var title: LocalizedStringKey {
        switch self {
        case .koFi: return "Ko-fi"
        case .afdian: return "Afdian"
        }
    }
}

struct TipButton: View {
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            Text("Tip")
                .font(.body.weight(.medium))
                .foregroundColor(SettingsControlColor.accent)
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
    @State private var method = TipMethod.allCases.first { ProjectLinks.shared.url(for: $0) != nil } ?? .koFi

    var body: some View {
        VStack(spacing: 12) {
            Picker("Tip method", selection: $method) {
                ForEach(TipMethod.allCases, id: \.self) { method in
                    Text(method.title).tag(method)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            if let url = ProjectLinks.shared.url(for: method) {
                if let image = qrCode(for: url) {
                    Image(decorative: image, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: CGFloat(image.width) * 4, height: CGFloat(image.height) * 4)
                        .padding(16)
                        .background(Color.white)
                        .accessibilityLabel(Text("Tip QR code"))
                }
                Link("Open tip page", destination: url)
            } else {
                Text("This method is not available yet.")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 12)
            }
            Text("Thank you for supporting MouseEasy!")
        }
        .padding(16)
        .frame(minWidth: 238)
    }

    private func qrCode(for url: URL) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(url.absoluteString.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
