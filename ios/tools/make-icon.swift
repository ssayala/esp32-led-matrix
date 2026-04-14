#!/usr/bin/env swift

// Generates ios/LEDTicker/Assets.xcassets/AppIcon.appiconset/icon-1024.png
//
// Design: 8x8 LED dot matrix rendered in white on a diagonal iOS-blue
// gradient. Represents the actual hardware (a single 8x8 MAX7219 module)
// and reads clearly at every icon size.
//
// Run: `swift ios/tools/make-icon.swift <out.png>`

import AppKit
import CoreGraphics
import Foundation

let size: CGFloat = 1024
let cs = CGColorSpaceCreateDeviceRGB()

guard let ctx = CGContext(
    data: nil,
    width: Int(size), height: Int(size),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write("failed to create CGContext\n".data(using: .utf8)!)
    exit(1)
}

// Background: diagonal iOS-blue gradient
let gradientColors = [
    CGColor(red: 0.04, green: 0.52, blue: 1.00, alpha: 1), // top-left
    CGColor(red: 0.00, green: 0.26, blue: 0.82, alpha: 1), // bottom-right
] as CFArray
guard let gradient = CGGradient(colorsSpace: cs, colors: gradientColors, locations: [0, 1]) else {
    exit(1)
}
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0,    y: size),
    end:   CGPoint(x: size, y: 0),
    options: []
)

// 8x8 grid of white dots
let cols = 8
let rows = 8
let margin = size * 0.17
let gridSize = size - margin * 2
let cellSize = gridSize / CGFloat(cols)
let dotRadius = cellSize * 0.34

// Soft white glow under the dots for a subtle LED-lit feel
ctx.saveGState()
ctx.setShadow(
    offset: .zero,
    blur: 22,
    color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.45)
)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
for row in 0..<rows {
    for col in 0..<cols {
        let cx = margin + (CGFloat(col) + 0.5) * cellSize
        let cy = margin + (CGFloat(row) + 0.5) * cellSize
        let rect = CGRect(
            x: cx - dotRadius, y: cy - dotRadius,
            width: dotRadius * 2, height: dotRadius * 2
        )
        ctx.fillEllipse(in: rect)
    }
}
ctx.restoreGState()

guard let image = ctx.makeImage() else {
    exit(1)
}

let rep = NSBitmapImageRep(cgImage: image)
guard let data = rep.representation(using: .png, properties: [:]) else {
    exit(1)
}

let outPath: String
if CommandLine.arguments.count > 1 {
    outPath = CommandLine.arguments[1]
} else {
    outPath = "icon-1024.png"
}

do {
    try data.write(to: URL(fileURLWithPath: outPath))
    print("Wrote \(outPath) (\(Int(size))x\(Int(size)))")
} catch {
    FileHandle.standardError.write("write failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}
