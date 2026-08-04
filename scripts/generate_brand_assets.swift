// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import AppKit
import Foundation

private let background = NSColor(
    calibratedRed: 47 / 255,
    green: 107 / 255,
    blue: 1,
    alpha: 1
)

private func generate(size: Int, output: URL) throws {
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    let scale = CGFloat(size) / 1024
    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, radius: CGFloat) -> CGPath {
        CGPath(
            roundedRect: CGRect(
                x: x * scale,
                y: y * scale,
                width: width * scale,
                height: height * scale
            ),
            cornerWidth: radius * scale,
            cornerHeight: radius * scale,
            transform: nil
        )
    }

    context.setFillColor(background.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))

    context.setFillColor(NSColor.white.cgColor)
    context.addPath(rect(202, 690, 620, 140, radius: 44))
    context.fillPath()
    context.addPath(rect(437, 230, 150, 520, radius: 44))
    context.fillPath()

    // Two flat cut-outs turn the stem into three ledger/installment entries.
    context.setFillColor(background.cgColor)
    context.fill(CGRect(x: 437 * scale, y: 385 * scale, width: 150 * scale, height: 28 * scale))
    context.fill(CGRect(x: 437 * scale, y: 515 * scale, width: 150 * scale, height: 28 * scale))

    guard let image = context.makeImage(),
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: output, options: .atomic)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
try generate(
    size: 1024,
    output: root.appendingPathComponent("app/Tutar/Resources/Assets.xcassets/AppIcon.appiconset/TutarIcon.png")
)
try generate(
    size: 256,
    output: root.appendingPathComponent("app/Tutar/Resources/Assets.xcassets/BrandMark.imageset/BrandMark.png")
)
