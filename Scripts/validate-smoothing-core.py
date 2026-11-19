#!/usr/bin/env python3
"""Run pure scrolling-model tests with Command Line Tools, without input access.

The production model/engine and existing XCTest test bodies are compiled unchanged.
A tiny assertion harness supplies the XCTest functions used by these pure tests;
it never initializes an application, a device manager, or an event tap.
"""

from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
BUILD = Path(tempfile.mkdtemp(prefix="mouse-smoothing-checks-"))
SDK = Path("/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk")
if not SDK.exists():
    SDK = Path(subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip())

support = r'''
import Foundation
import CoreGraphics
struct Scheme { struct Scrolling {} }
extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(range.lowerBound, self), range.upperBound) }
}
extension Decimal { var asTruncatedDouble: Double { Double(truncating: self as NSNumber) } }
class XCTestCase {}
struct TestFailure: Error {}
func require(_ condition: Bool, _ message: String, file: StaticString, line: UInt) {
    precondition(condition, message, file: file, line: line)
}
func XCTAssertTrue(_ value: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    require(value, "Expected true: \(message)", file: file, line: line)
}
func XCTAssertFalse(_ value: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    require(!value, "Expected false: \(message)", file: file, line: line)
}
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    require(a == b, "Expected \(a) == \(b): \(message)", file: file, line: line)
}
func XCTAssertEqual(_ a: Double, _ b: Double, accuracy: Double, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    require(abs(a - b) <= accuracy, "Expected \(a) == \(b), accuracy \(accuracy): \(message)", file: file, line: line)
}
func XCTAssertGreaterThan<T: Comparable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    require(a > b, "Expected \(a) > \(b): \(message)", file: file, line: line)
}
func XCTAssertLessThan<T: Comparable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    require(a < b, "Expected \(a) < \(b): \(message)", file: file, line: line)
}
func XCTAssertLessThanOrEqual<T: Comparable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    require(a <= b, "Expected \(a) <= \(b): \(message)", file: file, line: line)
}
func XCTAssertNotNil<T>(_ value: T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    require(value != nil, "Expected non-nil: \(message)", file: file, line: line)
}
func XCTUnwrap<T>(_ value: T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) throws -> T {
    require(value != nil, "Expected non-nil: \(message)", file: file, line: line)
    guard let value else { throw TestFailure() }
    return value
}
'''
(BUILD / "Support.swift").write_text(support)

production = [
    "LinearMouse/Utilities/Codable/ImplicitOptional.swift",
    "LinearMouse/Model/Configuration/Scheme/Scrolling/Bidirectional.swift",
    "LinearMouse/Model/Configuration/Scheme/Scrolling/Smoothed.swift",
    "LinearMouse/Model/Configuration/Scheme/Scrolling/Modifiers.swift",
    "LinearMouse/Model/Configuration/Scheme/Scrolling/Modifiers+Kind.swift",
    "LinearMouse/EventTransformer/SmoothedScrollingEngine.swift",
]
sources = [BUILD / "Support.swift"]
for index, relative in enumerate(production):
    target = BUILD / f"Production{index}.swift"
    shutil.copy2(ROOT / relative, target)
    sources.append(target)

tests = [
    ("SmoothedScrollingEngineTests", "LinearMouseUnitTests/EventTransformer/SmoothedScrollingEngineTests.swift"),
    ("ModifiersKindTests", "LinearMouseUnitTests/Model/Scheme/Scrolling/ModifiersKindTests.swift"),
]
calls = []
for class_name, relative in tests:
    source = (ROOT / relative).read_text()
    methods = re.findall(r"^    func (test\w+)\(", source, re.MULTILINE)
    source = source.replace("@testable import LinearMouse\n", "").replace("import XCTest\n", "")
    target = BUILD / f"{class_name}.swift"
    target.write_text("import Foundation\n" + source)
    sources.append(target)
    for method in methods:
        calls.append(f'    ("{class_name}.{method}", {class_name}().{method})')

main = "let tests: [(String, () throws -> Void)] = [\n" + ",\n".join(calls) + "\n]\n"
main += r'''
for (name, test) in tests {
    try test()
    print("PASS \(name)")
}
print("PASS: \(tests.count) pure scrolling checks; no device writes or input events")
'''
(BUILD / "main.swift").write_text(main)
sources.append(BUILD / "main.swift")

executable = BUILD / "validate-smoothing"
command = [
    "swiftc", "-swift-version", "5", "-Onone", "-sdk", str(SDK),
    "-target", f"{platform.machine()}-apple-macosx{'11.0' if platform.machine() == 'arm64' else '10.15'}",
    "-module-cache-path", str(BUILD / "cache"),
    *map(str, sources), "-o", str(executable),
]
print(f"Building pure scrolling checks in {BUILD}", flush=True)
subprocess.run(command, check=True, cwd=ROOT)
subprocess.run([str(executable)], check=True, cwd=ROOT)
