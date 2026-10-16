import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO

private func argument(named name: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: name), index + 1 < CommandLine.arguments.count else {
        return nil
    }
    return CommandLine.arguments[index + 1]
}

private func cgColor(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: red, green: green, blue: blue, alpha: alpha)
}

private func drawText(
    _ text: String,
    in context: CGContext,
    at point: CGPoint,
    size: CGFloat,
    color: CGColor,
    weight: String = "SFProDisplay-Regular"
) {
    let font = CTFontCreateWithName(weight as CFString, size, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        kCTFontAttributeName as NSAttributedString.Key: font,
        kCTForegroundColorAttributeName as NSAttributedString.Key: color
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    context.textPosition = point
    CTLineDraw(line, context)
}

private func drawArrow(in context: CGContext, from start: CGPoint, to end: CGPoint, color: CGColor) {
    context.saveGState()
    context.setStrokeColor(color)
    context.setLineWidth(3)
    context.setLineCap(.round)
    context.move(to: start)
    context.addLine(to: end)
    context.move(to: CGPoint(x: end.x - 12, y: end.y + 10))
    context.addLine(to: end)
    context.addLine(to: CGPoint(x: end.x - 12, y: end.y - 10))
    context.strokePath()
    context.restoreGState()
}

guard let outputPath = argument(named: "--output"),
      let iconPath = argument(named: "--icon") else {
    fputs("Usage: create-dmg-background.swift --output PATH --icon PATH\n", stderr)
    exit(2)
}

let width = 960
let height = 600
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
guard let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: width * 4,
    space: colorSpace,
    bitmapInfo: bitmapInfo
) else {
    fputs("Could not create bitmap context\n", stderr)
    exit(1)
}

let top = cgColor(0.97, 0.97, 0.985)
let bottom = cgColor(0.91, 0.90, 0.98)
let gradient = CGGradient(colorsSpace: colorSpace, colors: [top, bottom] as CFArray, locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: 0, y: 0), options: [])

let charcoal = cgColor(0.122, 0.137, 0.161)
let muted = cgColor(0.33, 0.34, 0.40)
let lavender = cgColor(0.56, 0.50, 0.90, 0.82)
let hairline = cgColor(0.12, 0.13, 0.16, 0.10)

context.saveGState()
context.setFillColor(charcoal)
context.addPath(CGPath(roundedRect: CGRect(x: 72, y: 441, width: 88, height: 88), cornerWidth: 21, cornerHeight: 21, transform: nil))
context.fillPath()

let iconURL = URL(fileURLWithPath: iconPath) as CFURL
if let source = CGImageSourceCreateWithURL(iconURL, nil), let icon = CGImageSourceCreateImageAtIndex(source, 0, nil) {
    context.draw(icon, in: CGRect(x: 78, y: 447, width: 76, height: 76))
}

drawText("Codex Usage Status", in: context, at: CGPoint(x: 188, y: 489), size: 28, color: charcoal, weight: "SFProDisplay-Semibold")
drawText("A quiet, at-a-glance 5H / 7D monitor", in: context, at: CGPoint(x: 190, y: 458), size: 15, color: muted)

context.setStrokeColor(hairline)
context.setLineWidth(1)
context.move(to: CGPoint(x: 72, y: 408))
context.addLine(to: CGPoint(x: 888, y: 408))
context.strokePath()

drawArrow(in: context, from: CGPoint(x: 418, y: 252), to: CGPoint(x: 542, y: 252), color: lavender)
drawText("Drag to Applications to install", in: context, at: CGPoint(x: 331, y: 72), size: 17, color: muted, weight: "SFProDisplay-Medium")
drawText("Keep both usage windows visible in your menu bar.", in: context, at: CGPoint(x: 282, y: 44), size: 12, color: muted)
context.restoreGState()

guard let image = context.makeImage() else {
    fputs("Could not create background image\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: outputPath) as CFURL
guard let destination = CGImageDestinationCreateWithURL(outputURL, "public.png" as CFString, 1, nil) else {
    fputs("Could not create PNG destination\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("Could not write PNG background\n", stderr)
    exit(1)
}
