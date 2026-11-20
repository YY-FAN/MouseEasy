#!/usr/bin/env python3
"""Compile the production configuration and recognizer with inert device adapters."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
work = Path(tempfile.mkdtemp(prefix="wheelease-portable-defaults-"))
modules = root / "build/local/modules"
sdk = Path("/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk")
if not sdk.exists():
    sdk = Path(subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip())

support = r'''
import AppKit
import Foundation
import CoreGraphics
struct AppIdentity { static let configurationSchemaURL = "test://configuration" }
struct ReceiverLogicalDeviceIdentity { var productID: Int?; var serialNumber: String?; var name: String? }
final class Device {
    enum Category { case mouse, trackpad }
    var vendorID: Int?; var productID: Int?; var productName: String?; var serialNumber: String?
    var category: Category = .mouse
    var activeLogicalDeviceIdentity: ReceiverLogicalDeviceIdentity? { nil }
}
final class DeviceManager {
    static let shared = DeviceManager()
    var devices: [Device] { [] }
    func pairedReceiverDevices(for device: Device) -> [ReceiverLogicalDeviceIdentity] { [] }
}
enum LogitechHIDPPDeviceMetadataProvider {
    enum Constants { static let vendorID = 1133 }
    enum ReprogControlsV4 { static let reservedVirtualButtonNumber = 256 }
}
final class ProcessIdentity {
    var bundleIdentifier: String?; var parent: ProcessIdentity?; var group: ProcessIdentity?
    var processName: String?; var processPath: String?
}
extension pid_t { var processIdentity: ProcessIdentity? { nil } }
extension Comparable { func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) } }
extension Decimal { var asTruncatedDouble: Double { Double(truncating: self as NSNumber) } }
extension CGMouseButton: Codable {}
extension CGMouseButton {
    static let back = CGMouseButton(rawValue: 3)!
    static let forward = CGMouseButton(rawValue: 4)!
}
enum ModifierState {
    static func generic(from flags: CGEventFlags) -> CGEventFlags { flags.intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate]) }
}
'''
(work / "Support.swift").write_text(support)
# Identity encoding is production code; only the unrelated CGEvent helpers are excluded.
identity = (root / "LinearMouse/Utilities/CGEvent+LinearMouseSynthetic.swift").read_text().split("extension CGEvent {")[0]
(work / "Identity.swift").write_text(identity)
paths = [
    "LinearMouse/Utilities/Codable/ImplicitOptional.swift",
    "LinearMouse/Utilities/Codable/SingleValueOrArray.swift",
    "LinearMouse/Utilities/Codable/HexRepresentation.swift",
    "LinearMouse/Utilities/Codable/Clamp.swift",
    "LinearMouse/Utilities/Codable/Unsettable.swift",
    "LinearMouse/Utilities/CustomDecodingError.swift",
    "LinearMouse/Utilities/JSONCommentSanitizer.swift",
    "LinearMouse/Model/Configuration/Configuration.swift",
    "LinearMouse/Model/AppTarget.swift",
    "LinearMouse/Model/Actions/CommonActionCatalog.swift",
    "LinearMouse/UI/ButtonsSettings/ButtonMappingsSection/ButtonMappingAction/KeyboardShortcutPresets.swift",
    "LinearMouse/Model/Configuration/Configuration+PortableMouseDefaults.swift",
    "LinearMouse/Model/Configuration/DeviceMatcher.swift",
    "LinearMouse/Model/Configuration/Scheme/Scheme.swift",
    "LinearMouse/Model/Configuration/Scheme/If/If.swift",
    "LinearMouse/Model/Configuration/Scheme/Pointer.swift",
    "LinearMouse/Model/Configuration/Scheme/Logitech.swift",
    "LinearMouse/Model/Configuration/Scheme/Trigger.swift",
    "LinearMouse/Model/Configuration/Scheme/Scrolling/Scrolling.swift",
    "LinearMouse/Model/Configuration/Scheme/Scrolling/Bidirectional.swift",
    "LinearMouse/Model/Configuration/Scheme/Scrolling/Distance.swift",
    "LinearMouse/Model/Configuration/Scheme/Scrolling/Smoothed.swift",
    "LinearMouse/Model/Configuration/Scheme/Scrolling/Modifiers.swift",
    "LinearMouse/Model/Configuration/Scheme/Scrolling/ScrollHotkeys.swift",
    "LinearMouse/Model/Configuration/Scheme/Buttons/Buttons.swift",
    "LinearMouse/Model/Configuration/Scheme/Buttons/Swipe.swift",
    "LinearMouse/Model/Configuration/Scheme/Buttons/KeyboardMapping.swift",
    "LinearMouse/Model/Configuration/Scheme/Buttons/AutoScroll/AutoScroll.swift",
    "LinearMouse/Model/Configuration/Scheme/Buttons/ClickDebouncing/ClickDebouncing.swift",
    "LinearMouse/Model/Configuration/Scheme/Buttons/Gesture/Gesture.swift",
    "LinearMouse/Model/Configuration/Scheme/Buttons/Mapping/Mapping.swift",
    "LinearMouse/Model/Configuration/Scheme/Buttons/Mapping/StructuredMapping.swift",
    "LinearMouse/Model/Configuration/Scheme/Buttons/Mapping/Action.swift",
    "LinearMouse/Model/Configuration/Scheme/Buttons/Mapping/Action+Codable.swift",
    "LinearMouse/Model/Configuration/Scheme/Buttons/Mapping/OpenTarget.swift",
    "LinearMouse/EventTransformer/ButtonMappingEngine.swift",
]
sources = [work / "Support.swift", work / "Identity.swift"]
for index, relative in enumerate(paths):
    destination = work / f"Production{index}.swift"
    destination.write_text("import Foundation\nimport CoreGraphics\n" + (root / relative).read_text())
    sources.append(destination)
test_source = work / "PortableMouseDefaultsTests.swift"
test_source.write_text((root / "LocalTests/PortableMouseDefaultsTests.swift").read_text())
sources.append(test_source)
command = ["swiftc", "-swift-version", "5", "-parse-as-library", "-sdk", str(sdk),
           "-module-cache-path", str(work / "cache"), "-I", str(modules), "-I", str(modules / "KeyKitC"),
           "-L", str(modules), "-lKeyKit", "-lDefaults", "-Xlinker", "-rpath", "-Xlinker", str(modules),
           *map(str, sources), "-o", str(work / "validate")]
subprocess.run(command, check=True, cwd=root)
subprocess.run([str(work / "validate")], check=True, cwd=root)
