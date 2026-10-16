// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Draws Courier's app icon and writes Resources/AppIcon.icns. Original artwork, drawn here with CoreGraphics:
// a speech bubble carrying a forward arrow, on a blue-to-teal tile. No other app's name, icon or asset.
//
//   swift apps/desktop/courier/app/scripts/make-icon.swift apps/desktop/courier/app/Resources/AppIcon.icns
//
// The .icns is checked in; run this again only to change the artwork.

import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift OUT.icns\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])

/// The icon at `size` pixels square.
func draw(size: Int) -> Data {
    let s = CGFloat(size)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: s / 1024, y: s / 1024)

    // The tile: macOS's icon grid leaves a margin of 100 of 1024 around a rounded square.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.3))
    context.addPath(tilePath)
    context.setFillColor(CGColor(srgbRed: 0.13, green: 0.32, blue: 0.85, alpha: 1))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [
        CGColor(srgbRed: 0.16, green: 0.36, blue: 0.93, alpha: 1),
        CGColor(srgbRed: 0.05, green: 0.66, blue: 0.68, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])
    context.restoreGState()

    // The bubble: a rounded body with a tail at its lower left.
    let bubble = CGMutablePath()
    bubble.addRoundedRect(in: CGRect(x: 240, y: 330, width: 544, height: 400), cornerWidth: 150, cornerHeight: 150)
    bubble.move(to: CGPoint(x: 300, y: 380))
    bubble.addLine(to: CGPoint(x: 250, y: 250))
    bubble.addLine(to: CGPoint(x: 420, y: 340))
    bubble.closeSubpath()
    context.addPath(bubble)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fillPath()

    // The arrow inside it: a shaft and a head, pointing right.
    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: 370, y: 530))
    arrow.addLine(to: CGPoint(x: 610, y: 530))
    arrow.move(to: CGPoint(x: 540, y: 610))
    arrow.addLine(to: CGPoint(x: 630, y: 530))
    arrow.addLine(to: CGPoint(x: 540, y: 450))
    context.addPath(arrow)
    context.setStrokeColor(CGColor(srgbRed: 0.10, green: 0.45, blue: 0.82, alpha: 1))
    context.setLineWidth(56)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()

    let image = context.makeImage()!
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Courier-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }
for points in [16, 32, 128, 256, 512] {
    try draw(size: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try draw(size: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed (\(iconutil.terminationStatus))\n".utf8))
    exit(1)
}
print("wrote \(output.path)")
