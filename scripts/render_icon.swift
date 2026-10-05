#!/usr/bin/env swift
// Generates the app icon as an Icon Composer document (Resources/AppIcon.icon), which macOS 26
// and later render with Liquid Glass. The build script compiles it with actool, which also
// produces a classic .icns for older systems.
//
// Usage: swift scripts/render_icon.swift
// Afterwards the document can be refined in Icon Composer (Xcode → Open Developer Tool).

import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()

// Geometry on the full 1024 pt icon canvas; the system applies the icon shape.
let canvas = 1024.0
let center = (x: 512.0, y: 512.0)
let ringRadius = 240.0
let ringWidth = 76.0
let startAngle = 100.0     // degrees, counterclockwise from 3 o'clock, y pointing up
let sweep = 294.0          // drawn clockwise
let headLength = 138.0
let headHalfWidth = 108.0
let headCorner = 26.0
let dotRadius = 66.0

let topColor = "srgb:0.33333,0.81176,0.74510,1.00000"
let bottomColor = "srgb:0.03922,0.54902,0.59608,1.00000"

typealias Point = (x: Double, y: Double)

func rad(_ degrees: Double) -> Double { degrees * .pi / 180 }

/// Point on a circle around the center, converted to SVG's top-left origin.
func polar(_ angle: Double, _ radius: Double) -> Point {
    (center.x + radius * cos(rad(angle)), canvas - (center.y + radius * sin(rad(angle))))
}

func f(_ p: Point) -> String { String(format: "%.1f %.1f", p.x, p.y) }

/// The ring as a filled shape: outer arc clockwise, inner arc back, round cap at the start.
func ringPath() -> String {
    let end = startAngle - sweep
    let outer = ringRadius + ringWidth / 2
    let inner = ringRadius - ringWidth / 2
    let large = sweep > 180 ? 1 : 0
    // In SVG coordinates (y down) a clockwise turn on screen uses sweep-flag 1.
    return "M\(f(polar(startAngle, outer))) "
        + "A\(outer) \(outer) 0 \(large) 1 \(f(polar(end, outer))) "
        + "L\(f(polar(end, inner))) "
        + "A\(inner) \(inner) 0 \(large) 0 \(f(polar(startAngle, inner))) "
        + "A\(ringWidth / 2) \(ringWidth / 2) 0 0 1 \(f(polar(startAngle, outer))) Z"
}

/// A triangle with rounded corners, pointing along the ring in the clockwise direction.
func arrowheadPath() -> String {
    let end = startAngle - sweep
    let base = polar(end, ringRadius)
    let a = rad(end)
    // Clockwise tangent and outward normal, in SVG coordinates.
    let tangent: Point = (sin(a), cos(a))
    let normal: Point = (cos(a), -sin(a))
    let back = 6.0
    let corners: [Point] = [
        (base.x + tangent.x * headLength, base.y + tangent.y * headLength),
        (base.x + normal.x * headHalfWidth - tangent.x * back, base.y + normal.y * headHalfWidth - tangent.y * back),
        (base.x - normal.x * headHalfWidth - tangent.x * back, base.y - normal.y * headHalfWidth - tangent.y * back),
    ]
    func toward(_ from: Point, _ to: Point, _ distance: Double) -> Point {
        let dx = to.x - from.x, dy = to.y - from.y
        let length = (dx * dx + dy * dy).squareRoot()
        return (from.x + dx / length * distance, from.y + dy / length * distance)
    }
    var path = ""
    for i in 0..<3 {
        let corner = corners[i]
        let previous = corners[(i + 2) % 3]
        let next = corners[(i + 1) % 3]
        let entry = toward(corner, previous, headCorner)
        let exit = toward(corner, next, headCorner)
        path += (i == 0 ? "M" : "L") + f(entry) + " Q" + f(corner) + " " + f(exit) + " "
    }
    return path + "Z"
}

func svg(_ body: String) -> String {
    """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\(body)</svg>

    """
}

let arrow = svg("<path d=\"\(ringPath())\" fill=\"#FFFFFF\"/><path d=\"\(arrowheadPath())\" fill=\"#FFFFFF\"/>")
let dot = svg("<circle cx=\"\(center.x)\" cy=\"\(center.y)\" r=\"\(dotRadius)\" fill=\"#FFFFFF\"/>")

let iconJSON = """
{
  "fill" : {
    "linear-gradient" : [
      "\(topColor)",
      "\(bottomColor)"
    ]
  },
  "groups" : [
    {
      "layers" : [
        {
          "glass" : true,
          "image-name" : "dot.svg",
          "name" : "dot"
        }
      ],
      "shadow" : {
        "kind" : "neutral",
        "opacity" : 0.5
      },
      "translucency" : {
        "enabled" : true,
        "value" : 0.3
      }
    },
    {
      "layers" : [
        {
          "glass" : true,
          "image-name" : "arrow.svg",
          "name" : "arrow"
        }
      ],
      "shadow" : {
        "kind" : "neutral",
        "opacity" : 0.5
      },
      "translucency" : {
        "enabled" : true,
        "value" : 0.4
      }
    }
  ],
  "supported-platforms" : {
    "squares" : [
      "macOS"
    ]
  }
}

"""

let fileManager = FileManager.default
let document = root.appendingPathComponent("Resources/AppIcon.icon")
let assets = document.appendingPathComponent("Assets")
try? fileManager.removeItem(at: document)
try fileManager.createDirectory(at: assets, withIntermediateDirectories: true)
try iconJSON.write(to: document.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
try arrow.write(to: assets.appendingPathComponent("arrow.svg"), atomically: true, encoding: .utf8)
try dot.write(to: assets.appendingPathComponent("dot.svg"), atomically: true, encoding: .utf8)

// Preview for the README, rendered by Icon Composer's own tool.
let ictool = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
if fileManager.isExecutableFile(atPath: ictool) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: ictool)
    process.arguments = [
        document.path, "--export-image",
        "--output-file", root.appendingPathComponent("Design/icon.png").path,
        "--platform", "macOS", "--rendition", "Default",
        "--width", "512", "--height", "512", "--scale", "2",
    ]
    try process.run()
    process.waitUntilExit()
}
print("Wrote Resources/AppIcon.icon and Design/icon.png")
