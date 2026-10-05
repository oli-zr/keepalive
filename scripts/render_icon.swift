#!/usr/bin/env swift
// Renders the app icon. Writes Design/icon.svg and Resources/AppIcon.icns.
// Usage: swift scripts/render_icon.swift

import AppKit
import CoreGraphics

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()

// Geometry on the 1024 pt macOS icon grid.
let canvas: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let center = CGPoint(x: 512, y: 512)
let ringRadius: CGFloat = 220
let ringWidth: CGFloat = 62
let startAngle: CGFloat = 100      // degrees, measured counterclockwise from 3 o'clock
let sweep: CGFloat = 300           // drawn clockwise
let headLength: CGFloat = 118
let headWidth: CGFloat = 92        // half the base of the arrowhead
let headCorner: CGFloat = 22       // rounds the arrowhead's corners
let dotRadius: CGFloat = 58

let topColor = (r: 0.33, g: 0.80, b: 0.74)
let bottomColor = (r: 0.05, g: 0.56, b: 0.60)

func radians(_ degrees: CGFloat) -> CGFloat { degrees * .pi / 180 }

/// Apple's icon shape is close to a superellipse; 4.2 matches the macOS corner curvature.
func squirclePath(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let n: CGFloat = 4.2
    let a = rect.width / 2, b = rect.height / 2
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

var endAngle: CGFloat { startAngle - sweep }

func point(at angle: CGFloat, radius: CGFloat) -> CGPoint {
    CGPoint(x: center.x + radius * cos(radians(angle)), y: center.y + radius * sin(radians(angle)))
}

func arrowheadPoints() -> [CGPoint] {
    let angle = radians(endAngle)
    let base = point(at: endAngle, radius: ringRadius)
    let tangent = CGPoint(x: sin(angle), y: -cos(angle))   // clockwise direction
    let normal = CGPoint(x: cos(angle), y: sin(angle))
    let length = headLength - headCorner * 2
    let width = headWidth - headCorner * 1.4
    let back = headCorner * 0.6
    return [
        CGPoint(x: base.x + tangent.x * length, y: base.y + tangent.y * length),
        CGPoint(x: base.x + normal.x * width - tangent.x * back, y: base.y + normal.y * width - tangent.y * back),
        CGPoint(x: base.x - normal.x * width - tangent.x * back, y: base.y - normal.y * width - tangent.y * back),
    ]
}

func drawIcon(in context: CGContext, size: CGFloat) {
    let scale = size / canvas
    context.scaleBy(x: scale, y: scale)

    // Body with the standard macOS icon shadow.
    let shape = squirclePath(in: body)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.3))
    context.addPath(shape)
    context.setFillColor(CGColor(red: bottomColor.r, green: bottomColor.g, blue: bottomColor.b, alpha: 1))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [
            CGColor(red: topColor.r, green: topColor.g, blue: topColor.b, alpha: 1),
            CGColor(red: bottomColor.r, green: bottomColor.g, blue: bottomColor.b, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])

    // Glyph: an open ring that closes on itself with an arrowhead, around a dot.
    context.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: CGColor(gray: 0, alpha: 0.18))
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.setFillColor(.white)
    context.setStrokeColor(.white)

    context.setLineWidth(ringWidth)
    context.setLineCap(.round)
    let start = point(at: startAngle, radius: ringRadius)
    context.move(to: start)
    context.addArc(center: center, radius: ringRadius, startAngle: radians(startAngle), endAngle: radians(endAngle + 6), clockwise: true)
    context.strokePath()

    let head = arrowheadPoints()
    context.setLineWidth(headCorner * 2)
    context.setLineJoin(.round)
    context.move(to: head[0])
    context.addLine(to: head[1])
    context.addLine(to: head[2])
    context.closePath()
    context.drawPath(using: .fillStroke)

    context.fillEllipse(in: CGRect(x: center.x - dotRadius, y: center.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
    context.endTransparencyLayer()
    context.restoreGState()
}

func png(size: Int) -> Data {
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    drawIcon(in: context, size: CGFloat(size))
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

func svg() -> String {
    // SVG has a top-left origin, so flip y.
    func f(_ p: CGPoint) -> String { String(format: "%.1f %.1f", p.x, canvas - p.y) }
    let start = point(at: startAngle, radius: ringRadius)
    let end = point(at: endAngle + 6, radius: ringRadius)
    let head = arrowheadPoints()
    let largeArc = sweep > 180 ? 1 : 0
    func hex(_ c: (r: Double, g: Double, b: Double)) -> String {
        String(format: "#%02X%02X%02X", Int(c.r * 255), Int(c.g * 255), Int(c.b * 255))
    }
    var squircle = ""
    let path = squirclePath(in: body)
    path.applyWithBlock { element in
        let p = element.pointee.points[0]
        squircle += (squircle.isEmpty ? "M" : "L") + f(p) + " "
    }
    return """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
      <defs>
        <linearGradient id="body" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="\(hex(topColor))"/>
          <stop offset="1" stop-color="\(hex(bottomColor))"/>
        </linearGradient>
      </defs>
      <path d="\(squircle)Z" fill="url(#body)"/>
      <g fill="#FFFFFF" stroke="#FFFFFF">
        <path d="M\(f(start)) A\(ringRadius) \(ringRadius) 0 \(largeArc) 1 \(f(end))" fill="none" stroke-width="\(ringWidth)" stroke-linecap="round"/>
        <path d="M\(f(head[0])) L\(f(head[1])) L\(f(head[2])) Z" stroke-width="\(headCorner * 2)" stroke-linejoin="round"/>
        <circle cx="\(center.x)" cy="\(canvas - center.y)" r="\(dotRadius)" stroke="none"/>
      </g>
    </svg>

    """
}

let fileManager = FileManager.default
let iconset = fileManager.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? fileManager.removeItem(at: iconset)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

try fileManager.createDirectory(at: root.appendingPathComponent("Design"), withIntermediateDirectories: true)
try svg().write(to: root.appendingPathComponent("Design/icon.svg"), atomically: true, encoding: .utf8)
try png(size: 1024).write(to: root.appendingPathComponent("Design/icon-1024.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns and Design/icon.svg" : "iconutil failed")
