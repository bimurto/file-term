#!/usr/bin/env swift
// Renders FileTerm's app icon into the asset catalog. Run from anywhere:
//   swift scripts/generate-app-icon.swift
// Coordinates use the macOS 1024-pt icon grid with the origin at the bottom left.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
  CGColor(
    srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func fill(_ context: CGContext, _ path: CGPath, top: UInt32, bottom: UInt32) {
  let box = path.boundingBox
  let gradient = CGGradient(
    colorsSpace: space, colors: [color(bottom), color(top)] as CFArray, locations: [0, 1])!
  context.saveGState()
  context.addPath(path)
  context.clip()
  context.drawLinearGradient(
    gradient, start: CGPoint(x: box.midX, y: box.minY), end: CGPoint(x: box.midX, y: box.maxY),
    options: [])
  context.restoreGState()
}

// Core Graphics shadows ignore the context transform, so they scale by hand.
func drawIcon(in context: CGContext, shadowScale: CGFloat) {
  // Background tile with its drop shadow.
  let tile = CGPath(
    roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185,
    cornerHeight: 185, transform: nil)
  context.saveGState()
  context.setShadow(
    offset: CGSize(width: 0, height: -12 * shadowScale), blur: 28 * shadowScale,
    color: color(0x000000, 0.45))
  context.addPath(tile)
  context.setFillColor(color(0x5B2BC9))
  context.fillPath()
  context.restoreGState()
  fill(context, tile, top: 0xFF7A6B, bottom: 0x5B2BC9)

  // Folder back, with the tab on the top left.
  let back = CGMutablePath()
  back.move(to: CGPoint(x: 212, y: 400))
  back.addArc(
    tangent1End: CGPoint(x: 212, y: 756), tangent2End: CGPoint(x: 450, y: 756), radius: 44)
  back.addArc(
    tangent1End: CGPoint(x: 450, y: 756), tangent2End: CGPoint(x: 512, y: 690), radius: 32)
  back.addArc(
    tangent1End: CGPoint(x: 512, y: 690), tangent2End: CGPoint(x: 812, y: 690), radius: 32)
  back.addArc(
    tangent1End: CGPoint(x: 812, y: 690), tangent2End: CGPoint(x: 812, y: 400), radius: 44)
  back.addLine(to: CGPoint(x: 812, y: 400))
  back.closeSubpath()
  fill(context, back, top: 0xA58AE1, bottom: 0xA58AE1)

  // Folder front, lifted off the back by a soft shadow.
  let front = CGPath(
    roundedRect: CGRect(x: 212, y: 262, width: 600, height: 382), cornerWidth: 44,
    cornerHeight: 44, transform: nil)
  context.saveGState()
  context.setShadow(
    offset: CGSize(width: 0, height: 8 * shadowScale), blur: 22 * shadowScale,
    color: color(0x2A0F6B, 0.5))
  context.addPath(front)
  context.setFillColor(color(0xFFFFFF))
  context.fillPath()
  context.restoreGState()

  // Terminal prompt: ">_".
  let prompt = CGMutablePath()
  prompt.move(to: CGPoint(x: 345, y: 543))
  prompt.addLine(to: CGPoint(x: 465, y: 453))
  prompt.addLine(to: CGPoint(x: 345, y: 363))
  prompt.move(to: CGPoint(x: 515, y: 363))
  prompt.addLine(to: CGPoint(x: 679, y: 363))
  context.addPath(prompt)
  context.setLineWidth(54)
  context.setLineCap(.round)
  context.setLineJoin(.round)
  context.setStrokeColor(color(0x5B2BC9))
  context.strokePath()
}

func writePNG(pixels: Int, to url: URL) {
  let context = CGContext(
    data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  context.interpolationQuality = .high
  context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
  drawIcon(in: context, shadowScale: CGFloat(pixels) / 1024)
  let destination = CGImageDestinationCreateWithURL(
    url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, context.makeImage()!, nil)
  guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(url.path)") }
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let catalog = root.appendingPathComponent("FileTerm/Resources/Assets.xcassets")
let iconSet = catalog.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

var images: [String] = []
for points in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    writePNG(pixels: points * scale, to: iconSet.appendingPathComponent(name))
    images.append(
      """
          { "filename" : "\(name)", "idiom" : "mac", "scale" : "\(scale)x", "size" : "\(points)x\(points)" }
      """)
  }
}

let info = "\"info\" : { \"author\" : \"xcode\", \"version\" : 1 }"
try "{\n  \"images\" : [\n\(images.joined(separator: ",\n"))\n  ],\n  \(info)\n}\n"
  .write(to: iconSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try "{\n  \(info)\n}\n"
  .write(to: catalog.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
