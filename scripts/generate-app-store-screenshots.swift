#!/usr/bin/env swift
// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import AppKit
import Foundation

_ = NSApplication.shared

struct Slide {
    let title: String
    let subtitle: String?
}

enum Device: String {
    case iphone, ipad

    var size: NSSize {
        switch self {
        case .iphone: NSSize(width: 1320, height: 2868)
        case .ipad: NSSize(width: 2064, height: 2752)
        }
    }
}

let arguments = CommandLine.arguments
func value(_ flag: String) -> String {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
        fputs("Missing \(flag)\n", stderr)
        exit(2)
    }
    return arguments[index + 1]
}

let inputs: [(locale: String, suffix: String, device: Device, result: String)] = [
    ("tr", "tr", .iphone, value("--tr-iphone")),
    ("en-US", "en", .iphone, value("--en-iphone")),
    ("tr", "tr", .ipad, value("--tr-ipad")),
    ("en-US", "en", .ipad, value("--en-ipad"))
]
let output = URL(fileURLWithPath: value("--output"), isDirectory: true)
let repository = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let brandMark = NSImage(contentsOf: repository.appendingPathComponent("app/Tutar/Resources/Assets.xcassets/BrandMark.imageset/BrandMark.png"))!

let slides: [String: [Slide]] = [
    "tr": [
        Slide(title: "Gelir ve giderin,\ntek bakışta.", subtitle: "Ücretsiz, reklamsız ve açık kaynak."),
        Slide(title: "Saniyeler içinde\nkayıt ekle.", subtitle: nil),
        Slide(title: "Harcamalarının\nritmini gör.", subtitle: nil),
        Slide(title: "Bütçeni\nhedefte tut.", subtitle: nil),
        Slide(title: "Taksitleri tek\nişlemden planla.", subtitle: nil),
        Slide(title: "Altın, gümüş ve\ndövizi izle.", subtitle: "Seçtiğin para biriminde.")
    ],
    "en": [
        Slide(title: "Income and expenses,\nat a glance.", subtitle: "Free, ad-free, and open source."),
        Slide(title: "Add an entry\nin seconds.", subtitle: nil),
        Slide(title: "See where your\nmoney goes.", subtitle: nil),
        Slide(title: "Keep every budget\non track.", subtitle: nil),
        Slide(title: "Plan installments\nfrom one entry.", subtitle: nil),
        Slide(title: "Track gold, silver,\nand currencies.", subtitle: "In your chosen currency.")
    ]
]

func run(_ executable: String, _ args: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = args
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CocoaError(.executableLoad) }
}

func attachments(in result: String, suffix: String) throws -> [NSImage] {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("tutar-store-\(UUID().uuidString)", isDirectory: true)
    try run("/usr/bin/xcrun", ["xcresulttool", "export", "attachments", "--path", result, "--output-path", folder.path])
    defer { try? FileManager.default.removeItem(at: folder) }

    let data = try Data(contentsOf: folder.appendingPathComponent("manifest.json"))
    let groups = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
    let records = groups.flatMap { $0["attachments"] as? [[String: Any]] ?? [] }
    return try (1 ... 6).map { index in
        let prefix = String(format: "store-%02d-", index)
        guard let item = records.first(where: {
            (($0["suggestedHumanReadableName"] as? String) ?? "").hasPrefix(prefix)
                && (($0["suggestedHumanReadableName"] as? String) ?? "").contains("-\(suffix)_")
        }), let file = item["exportedFileName"] as? String,
              let image = NSImage(data: try Data(contentsOf: folder.appendingPathComponent(file))) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return image
    }
}

func rectFromTop(x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat, canvas: NSSize) -> NSRect {
    NSRect(x: x, y: canvas.height - top - height, width: width, height: height)
}

func drawText(_ text: String, rect: NSRect, font: NSFont, color: NSColor, lineHeight: CGFloat? = nil) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left
    if let lineHeight {
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
    }
    (text as NSString).draw(
        in: rect,
        withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    )
}

func compose(source: NSImage, slide: Slide, device: Device) throws -> Data {
    let canvas = device.size
    guard let bitmap = CGContext(
        data: nil,
        width: Int(canvas.width),
        height: Int(canvas.height),
        bitsPerComponent: 8,
        bytesPerRow: Int(canvas.width) * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { throw CocoaError(.coderInvalidValue) }

    NSGraphicsContext.saveGraphicsState()
    let graphicsContext = NSGraphicsContext(cgContext: bitmap, flipped: false)
    NSGraphicsContext.current = graphicsContext
    NSColor.white.setFill()
    NSRect(origin: .zero, size: canvas).fill()

    let scale = device == .iphone ? CGFloat(1) : 1.18
    let logoSize = 78 * scale
    let logoRect = rectFromTop(x: 86 * scale, top: 78 * scale, width: logoSize, height: logoSize, canvas: canvas)
    brandMark.draw(in: logoRect)
    drawText(
        "TUTAR",
        rect: rectFromTop(x: 184 * scale, top: 94 * scale, width: 380 * scale, height: 70 * scale, canvas: canvas),
        font: .systemFont(ofSize: 38 * scale, weight: .semibold),
        color: .black
    )

    let titleTop: CGFloat = device == .iphone ? 235 : 220
    let titleX: CGFloat = device == .iphone ? 88 : 102
    let titleSize: CGFloat = device == .iphone ? 86 : 80
    drawText(
        slide.title,
        rect: rectFromTop(x: titleX, top: titleTop, width: canvas.width - titleX * 2, height: 245, canvas: canvas),
        font: .systemFont(ofSize: titleSize, weight: .bold),
        color: .black,
        lineHeight: titleSize * 1.03
    )
    if let subtitle = slide.subtitle {
        drawText(
            subtitle,
            rect: rectFromTop(x: titleX, top: titleTop + 205, width: canvas.width - titleX * 2, height: 80, canvas: canvas),
            font: .systemFont(ofSize: device == .iphone ? 34 : 32, weight: .regular),
            color: NSColor(white: 0.34, alpha: 1)
        )
    }

    let screenshotWidth: CGFloat = device == .iphone ? 1010 : 1630
    let screenshotHeight = screenshotWidth * source.size.height / source.size.width
    let screenshotTop: CGFloat = device == .iphone ? 690 : 560
    let screenshotRect = rectFromTop(
        x: (canvas.width - screenshotWidth) / 2,
        top: screenshotTop,
        width: screenshotWidth,
        height: screenshotHeight,
        canvas: canvas
    )
    let radius: CGFloat = device == .iphone ? 62 : 48
    let path = NSBezierPath(roundedRect: screenshotRect, xRadius: radius, yRadius: radius)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = device == .iphone ? 34 : 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    source.draw(in: screenshotRect, from: NSRect(origin: .zero, size: source.size), operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    guard let image = bitmap.makeImage(),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return png
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var generated = 0
for input in inputs {
    fputs("Extracting \(input.locale) \(input.device.rawValue)\n", stderr)
    let sources = try attachments(in: input.result, suffix: input.suffix)
    let localeFolder = output.appendingPathComponent(input.locale, isDirectory: true)
    try FileManager.default.createDirectory(at: localeFolder, withIntermediateDirectories: true)
    for (offset, source) in sources.enumerated() {
        fputs("Rendering \(input.locale) \(input.device.rawValue) \(offset + 1)\n", stderr)
        let data = try compose(source: source, slide: slides[input.suffix]![offset], device: input.device)
        let file = localeFolder.appendingPathComponent(String(format: "%02d-%@.png", offset + 1, input.device.rawValue))
        try data.write(to: file, options: .atomic)
        guard let check = NSBitmapImageRep(data: data),
              check.pixelsWide == Int(input.device.size.width),
              check.pixelsHigh == Int(input.device.size.height),
              !check.hasAlpha else { throw CocoaError(.coderInvalidValue) }
        generated += 1
    }
}
precondition(generated == 24)
print("Generated \(generated) App Store screenshots in \(output.path)")
