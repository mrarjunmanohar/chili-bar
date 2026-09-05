#!/usr/bin/env swift
//
// Builds Chili Bar's icons from the pixel-art chili logo.
//
// Two things make this more than a resize:
//
//   1. The source PNGs have no alpha channel — the chili sits on an opaque light background.
//      A menu bar icon must be transparent, so the background is keyed out.
//   2. It is pixel art. Smooth interpolation turns it to mush, so every resample uses
//      nearest-neighbour and integer scale factors.
//
// Usage: swift Scripts/make-icons.swift <source.png> <output-dir>

import AppKit
import Foundation

// MARK: - Arguments

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write("usage: make-icons.swift <source.png> <output-dir>\n".data(using: .utf8)!)
    exit(2)
}
let sourceURL = URL(fileURLWithPath: arguments[1])
let outputDirectory = URL(fileURLWithPath: arguments[2])

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("error: \(message)\n".data(using: .utf8)!)
    exit(1)
}

// MARK: - Load

guard let source = NSImage(contentsOf: sourceURL),
      let sourceCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fail("could not read \(sourceURL.path)")
}

let width = sourceCG.width
let height = sourceCG.height

/// Read the source into a plain RGBA byte buffer we can edit directly.
func readPixels(_ image: CGImage) -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    guard let context = CGContext(
        data: &pixels,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: image.width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fail("could not create bitmap context") }

    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return pixels
}

var pixels = readPixels(sourceCG)

// MARK: - Key out the background

// The corner pixel is the background by definition for this artwork.
let backgroundR = Int(pixels[0])
let backgroundG = Int(pixels[1])
let backgroundB = Int(pixels[2])

// Soft key rather than a hard threshold.
//
// ~5% of the source pixels are anti-aliasing along the chili's outline — part background,
// part chili. Clearing only exact matches would leave those as an opaque light halo, which
// is invisible on a white page but obvious against a dark menu bar.
//
// Below `opaqueBelow` a pixel is pure background and goes fully transparent; above
// `opaqueAbove` it is pure chili and stays. In between, alpha scales with distance.
let transparentBelow = 32
let opaqueAbove = 160

var clearedCount = 0
var softenedCount = 0

for index in stride(from: 0, to: pixels.count, by: 4) {
    let distance = abs(Int(pixels[index]) - backgroundR)
        + abs(Int(pixels[index + 1]) - backgroundG)
        + abs(Int(pixels[index + 2]) - backgroundB)

    let alpha: Double
    switch distance {
    case ...transparentBelow:
        alpha = 0
        clearedCount += 1
    case opaqueAbove...:
        alpha = 1
    default:
        alpha = Double(distance - transparentBelow) / Double(opaqueAbove - transparentBelow)
        softenedCount += 1
    }

    guard alpha < 1 else { continue }

    // The buffer is premultiplied, and a fringe pixel is `foreground × alpha + background ×
    // (1 - alpha)`. Subtracting the background's contribution leaves exactly the premultiplied
    // foreground — so the chili's own colour is recovered instead of staying tinted by the
    // background it was composited against.
    func unmix(_ value: UInt8, _ background: Int) -> UInt8 {
        let recovered = Double(value) - Double(background) * (1 - alpha)
        return UInt8(max(0, min(255, recovered.rounded())))
    }

    pixels[index] = unmix(pixels[index], backgroundR)
    pixels[index + 1] = unmix(pixels[index + 1], backgroundG)
    pixels[index + 2] = unmix(pixels[index + 2], backgroundB)
    pixels[index + 3] = UInt8((alpha * 255).rounded())
}

guard clearedCount > 0 else {
    fail("no background pixels matched — is \(sourceURL.lastPathComponent) already transparent?")
}

guard let cutoutContext = CGContext(
    data: &pixels,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: width * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
), let cutout = cutoutContext.makeImage() else {
    fail("could not build the transparent image")
}

// MARK: - Resample

/// Nearest-neighbour resize. `.none` interpolation is the whole point: it keeps hard pixel
/// edges instead of blurring them, which is what preserves the pixel-art look at every size.
func resize(_ image: CGImage, to size: Int) -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fail("could not create a \(size)px context") }

    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

    guard let resized = context.makeImage() else { fail("could not resample to \(size)px") }
    return resized
}

func writePNG(_ image: CGImage, to url: URL) {
    let representation = NSBitmapImageRep(cgImage: image)
    representation.size = NSSize(width: image.width, height: image.height)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        fail("could not encode \(url.lastPathComponent)")
    }
    do {
        try data.write(to: url)
    } catch {
        fail("could not write \(url.path): \(error.localizedDescription)")
    }
}

try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

// Menu bar: 16pt, so 16px @1x and 32px @2x.
writePNG(resize(cutout, to: 16), to: outputDirectory.appendingPathComponent("chili.png"))
writePNG(resize(cutout, to: 32), to: outputDirectory.appendingPathComponent("chili@2x.png"))

// App icon: an .iconset that `iconutil` turns into a .icns.
let iconset = outputDirectory.appendingPathComponent("ChiliBar.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let iconSizes: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for icon in iconSizes {
    writePNG(resize(cutout, to: icon.size), to: iconset.appendingPathComponent(icon.name))
}

print("icons written to \(outputDirectory.path) — \(clearedCount) px cleared, \(softenedCount) px feathered")
