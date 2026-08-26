#!/usr/bin/env swift

import AppKit
import Foundation

struct Slide {
    let source: String
    let destination: String
    let headline: String
}

let slides = [
    Slide(source: "01-agenda.png", destination: "01-persistent-reminders.png", headline: "Persistent reminders. Free."),
    Slide(source: "02-quick-capture.png", destination: "02-quick-capture.png", headline: "Add tasks in seconds"),
    Slide(source: "03-notes-and-links.png", destination: "03-notes-and-links.png", headline: "Keep notes and links together"),
    Slide(source: "04-location-reminders.png", destination: "04-location-reminders.png", headline: "Arrive. Leave. Get reminded."),
    Slide(source: "05-repeat-rules.png", destination: "05-repeat-rules.png", headline: "Repeat on your schedule"),
    Slide(source: "06-settings.png", destination: "06-settings.png", headline: "Set timing and accent"),
    Slide(source: "08-dark-agenda.png", destination: "07-dark-mode.png", headline: "Dark mode included")
]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 3 else {
    fail("usage: render_store_screenshots.swift RAW_DIRECTORY OUTPUT_DIRECTORY")
}

let fileManager = FileManager.default
let rawDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for slide in slides {
    let sourceURL = rawDirectory.appendingPathComponent(slide.source)
    guard let source = NSImage(contentsOf: sourceURL),
          let sourceRepresentation = NSBitmapImageRep(data: source.tiffRepresentation ?? Data()) else {
        fail("could not read \(sourceURL.path)")
    }

    let width = sourceRepresentation.pixelsWide
    let height = sourceRepresentation.pixelsHigh
    let isPhone = width < 1600
    let insetWidth = isPhone ? 1080.0 : 1780.0
    let bottomInset = isPhone ? 52.0 : 58.0
    let cornerRadius = isPhone ? 62.0 : 50.0
    let headlineSize = isPhone ? 78.0 : 82.0
    let scale = insetWidth / CGFloat(width)
    let insetHeight = CGFloat(height) * scale
    let leftInset = (CGFloat(width) - insetWidth) / 2
    let imageRect = NSRect(x: leftInset, y: bottomInset, width: insetWidth, height: insetHeight)

    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: NSColorSpaceName.deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fail("could not create output bitmap")
    }

    bitmap.size = NSSize(width: width, height: height)
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fail("could not create graphics context")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    let canvas = NSRect(x: 0, y: 0, width: width, height: height)
    let gradient = NSGradient(
        starting: NSColor(srgbRed: 0.77, green: 0.91, blue: 0.97, alpha: 1),
        ending: NSColor(srgbRed: 0.95, green: 0.98, blue: 0.99, alpha: 1)
    )!
    gradient.draw(in: canvas, angle: -90)

    let headlineStyle = NSMutableParagraphStyle()
    headlineStyle.alignment = .center
    headlineStyle.lineBreakMode = .byWordWrapping
    let headlineAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: headlineSize, weight: .bold),
        .foregroundColor: NSColor(srgbRed: 0.05, green: 0.10, blue: 0.16, alpha: 1),
        .paragraphStyle: headlineStyle,
        .kern: -1.2
    ]
    let headlineHeight: CGFloat = isPhone ? 190 : 170
    let headlineHorizontalInset: CGFloat = isPhone ? 70 : 120
    let headlineTopInset: CGFloat = isPhone ? 45 : 76
    let headlineRect = NSRect(
        x: headlineHorizontalInset,
        y: CGFloat(height) - headlineHeight - headlineTopInset,
        width: CGFloat(width) - (headlineHorizontalInset * 2),
        height: headlineHeight
    )
    (slide.headline as NSString).draw(in: headlineRect, withAttributes: headlineAttributes)

    let framePath = NSBezierPath(roundedRect: imageRect, xRadius: cornerRadius, yRadius: cornerRadius)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = isPhone ? 28 : 22
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()
    NSColor.white.setFill()
    framePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    framePath.addClip()
    source.draw(in: imageRect, from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.65).setStroke()
    framePath.lineWidth = isPhone ? 4 : 3
    framePath.stroke()

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
        fail("could not encode \(slide.destination)")
    }
    let destinationURL = outputDirectory.appendingPathComponent(slide.destination)
    try data.write(to: destinationURL, options: Data.WritingOptions.atomic)
    print(destinationURL.path)
}
