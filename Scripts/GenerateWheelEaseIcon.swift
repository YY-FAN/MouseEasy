#!/usr/bin/env swift
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 WheelEase contributors
// The SVG is the sole editable geometry/color source. This renderer supports
// its rounded tile, filled and stroked paths; it does not reuse another app's art.

import AppKit
import Foundation

let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let branding = project.appendingPathComponent("Branding")
let output = branding.appendingPathComponent("Generated")
let iconset = output.appendingPathComponent("WheelEase.iconset")
let assetset = project.appendingPathComponent("LinearMouse/Assets.xcassets/WheelEase.appiconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: assetset, withIntermediateDirectories: true)
let previewOnly = CommandLine.arguments.count == 3
let svg = previewOnly ? URL(fileURLWithPath: CommandLine.arguments[1]) : branding.appendingPathComponent("WheelEase.svg")
let document = try XMLDocument(contentsOf: svg)
func elements(_ name: String) throws -> [XMLElement] {
    try document.nodes(forXPath: "//*[local-name()='\(name)']").compactMap { $0 as? XMLElement }
}
func attribute(_ node: XMLElement, _ name: String) -> String {
    node.attribute(forName: name)!.stringValue!
}
func number(_ node: XMLElement, _ name: String) -> CGFloat {
    CGFloat(Double(attribute(node, name))!)
}
func color(_ hex: String) -> CGColor {
    let n = UInt32(hex.dropFirst(), radix: 16)!
    return CGColor(red: CGFloat((n >> 16) & 255) / 255, green: CGFloat((n >> 8) & 255) / 255,
                   blue: CGFloat(n & 255) / 255, alpha: 1)
}
func path(_ data: String) -> CGPath {
    let expression = try! NSRegularExpression(pattern: "[MLCZ]|-?[0-9]+(?:\\.[0-9]+)?")
    let range = NSRange(data.startIndex..., in: data)
    let tokens = expression.matches(in: data, range: range).map { String(data[Range($0.range, in: data)!]) }
    let result = CGMutablePath()
    var index = 0
    func value(_ offset: Int) -> CGFloat { CGFloat(Double(tokens[index + offset])!) }
    while index < tokens.count {
        switch tokens[index] {
        case "Z":
            result.closeSubpath()
            index += 1
        case "M":
            result.move(to: CGPoint(x: value(1), y: value(2)))
            index += 3
        case "L":
            result.addLine(to: CGPoint(x: value(1), y: value(2)))
            index += 3
        case "C":
            result.addCurve(to: CGPoint(x: value(5), y: value(6)),
                            control1: CGPoint(x: value(1), y: value(2)),
                            control2: CGPoint(x: value(3), y: value(4)))
            index += 7
        default: fatalError("Unsupported SVG path command")
        }
    }
    return result
}
let tile = try elements("rect")[0]
let stops = try elements("stop")
let gradientSource = try elements("linearGradient")[0]
let shadowSource = try elements("feDropShadow")[0]
let tracks = try elements("path").map { node in
    (path(attribute(node, "d")), color(node.attribute(forName: "stroke")?.stringValue ?? attribute(node, "fill")),
     node.attribute(forName: "stroke-width") != nil ? number(node, "stroke-width") : 0)
}
let tileRect = CGRect(x: number(tile, "x"), y: number(tile, "y"),
                      width: number(tile, "width"), height: number(tile, "height"))
let tilePath = CGPath(roundedRect: tileRect, cornerWidth: number(tile, "rx"),
                      cornerHeight: number(tile, "rx"), transform: nil)

func drawMark(_ context: CGContext) {
    context.setLineCap(.round)
    context.setLineJoin(.round)
    for (track, stroke, width) in tracks {
        context.addPath(track)
        if width == 0 { context.setFillColor(stroke); context.fillPath(); continue }
        context.setStrokeColor(stroke)
        context.setLineWidth(width)
        context.strokePath()
    }

}

func drawApp(_ context: CGContext, size: CGFloat) {
    context.translateBy(x: 0, y: size)
    context.scaleBy(x: size / 1024, y: -size / 1024)
    context.saveGState()
    context.setShadow(offset: CGSize(width: number(shadowSource, "dx"), height: number(shadowSource, "dy")),
                      blur: number(shadowSource, "stdDeviation"),
                      color: color(attribute(shadowSource, "flood-color")).copy(alpha: number(shadowSource, "flood-opacity")))
    context.addPath(tilePath)
    context.setFillColor(color(attribute(stops[1], "stop-color")))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: stops.map { color(attribute($0, "stop-color")) } as CFArray,
                              locations: [0, 1])!
    context.drawLinearGradient(gradient,
                               start: CGPoint(x: number(gradientSource, "x1"), y: number(gradientSource, "y1")),
                               end: CGPoint(x: number(gradientSource, "x2"), y: number(gradientSource, "y2")), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()
    drawMark(context)
}

func drawMenu(_ context: CGContext, size: CGFloat) {
    context.translateBy(x: 0, y: size)
    let scale = size / 18
    context.scaleBy(x: scale, y: -scale)
    var markBounds = CGRect.null
    for (track, _, width) in tracks {
        markBounds = markBounds.union(track.boundingBoxOfPath.insetBy(dx: -width / 2, dy: -width / 2))
    }
    context.setFillColor(color(attribute(stops[1], "stop-color")))
    context.addPath(CGPath(roundedRect: CGRect(x: 0.5, y: 1, width: 17, height: 16), cornerWidth: 4, cornerHeight: 4, transform: nil))
    context.fillPath()
    let fit = min(13.6 / markBounds.width, 12.8 / markBounds.height)
    context.translateBy(x: (18 - markBounds.width * fit) / 2, y: (18 - markBounds.height * fit) / 2)
    context.scaleBy(x: fit, y: fit)
    context.translateBy(x: -markBounds.minX, y: -markBounds.minY)
    drawMark(context)
}

func png(_ size: Int, url: URL, draw: (CGContext, CGFloat) -> Void) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    draw(context, CGFloat(size))
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}

if previewOnly {
    let destination = URL(fileURLWithPath: CommandLine.arguments[2])
    try png(256, url: destination, draw: drawApp)
    try png(36, url: destination.deletingPathExtension().appendingPathExtension("menu.png"), draw: drawMenu)
    exit(0)
}

var assetImages: [[String: String]] = []
for (points, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        let generatedPNG = iconset.appendingPathComponent(name)
        try png(points * scale, url: generatedPNG, draw: drawApp)
        try Data(contentsOf: generatedPNG).write(to: assetset.appendingPathComponent(name), options: .atomic)
        assetImages.append(["filename": name, "idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x"])
    }
}
let assetManifest: [String: Any] = ["images": assetImages, "info": ["author": "MouseEasy", "version": 1]]
try JSONSerialization.data(withJSONObject: assetManifest, options: [.prettyPrinted, .sortedKeys])
    .write(to: assetset.appendingPathComponent("Contents.json"), options: .atomic)
try png(1024, url: output.appendingPathComponent("WheelEase-1024.png"), draw: drawApp)
try png(18, url: output.appendingPathComponent("WheelEaseMenuIcon.png"), draw: drawMenu)
try png(36, url: output.appendingPathComponent("WheelEaseMenuIcon@2x.png"), draw: drawMenu)
try png(256, url: output.appendingPathComponent("MenuPreview.png")) { context, _ in
    context.setFillColor(CGColor(gray: 0.96, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
    context.translateBy(x: 64, y: 64)
    drawMenu(context, size: 128)
}

var bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
let consumer = CGDataConsumer(url: output.appendingPathComponent("WheelEaseMenuIcon.pdf") as CFURL)!
let pdf = CGContext(consumer: consumer, mediaBox: &bounds, nil)!
pdf.beginPDFPage(nil)
drawMenu(pdf, size: 18)
pdf.endPDFPage()
pdf.closePDF()
let menuAssets = assetset.deletingLastPathComponent().appendingPathComponent("WheelEaseMenuIcon.imageset")
try FileManager.default.createDirectory(at: menuAssets, withIntermediateDirectories: true)
let menuData = try Data(contentsOf: output.appendingPathComponent("WheelEaseMenuIcon.pdf"))
try menuData.write(to: menuAssets.appendingPathComponent("menu.pdf"), options: .atomic)
let menuManifest = #"{"images":[{"filename":"menu.pdf","idiom":"universal"}],"info":{"author":"MouseEasy","version":1},"properties":{"preserves-vector-representation":true,"template-rendering-intent":"original"}}"#
try Data(menuManifest.utf8).write(to: menuAssets.appendingPathComponent("Contents.json"), options: .atomic)

// ICNS is a length-prefixed icon family. Store the original PNGs directly in
// modern size/retina elements, avoiding an external image service at build time.
func bigEndian32(_ value: Int) -> Data {
    var n = UInt32(value).bigEndian
    return withUnsafeBytes(of: &n) { Data($0) }
}
let elements: [(String, String)] = [
    ("icp4", "icon_16x16.png"), ("ic11", "icon_16x16@2x.png"),
    ("icp5", "icon_32x32.png"), ("ic12", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"), ("ic13", "icon_128x128@2x.png"),
    ("ic08", "icon_256x256.png"), ("ic14", "icon_256x256@2x.png"),
    ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")
]
var body = Data()
for (type, filename) in elements {
    let data = try Data(contentsOf: iconset.appendingPathComponent(filename))
    body.append(Data(type.utf8))
    body.append(bigEndian32(data.count + 8))
    body.append(data)
}
var family = Data("icns".utf8)
family.append(bigEndian32(body.count + 8))
family.append(body)
try family.write(to: output.appendingPathComponent("WheelEase.icns"))
print("Generated original WheelEase app and color menu icons at \(output.path)")
