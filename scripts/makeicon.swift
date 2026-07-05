import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

let S: CGFloat = 1024
let cs = CGColorSpaceCreateDeviceRGB()
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}
// noneSkipLast => opaque, no alpha channel (App Store icons must not have alpha).
guard let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("ctx")
}
// Draw in top-left origin coords (like UIKit).
ctx.translateBy(x: 0, y: S)
ctx.scaleBy(x: 1, y: -1)

// Background gradient: vivid mint top -> deep forest bottom, slight diagonal.
let bg = CGGradient(colorsSpace: cs, colors: [rgb(0.26, 0.94, 0.64), rgb(0.11, 0.74, 0.48), rgb(0.05, 0.52, 0.33)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: S*0.32, y: 0), end: CGPoint(x: S*0.68, y: S), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// Top gloss.
let gloss = CGGradient(colorsSpace: cs, colors: [rgb(1, 1, 1, 0.14), rgb(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(gloss, startCenter: CGPoint(x: S/2, y: S*0.18), startRadius: 0,
                       endCenter: CGPoint(x: S/2, y: S*0.18), endRadius: S*0.66, options: [])
// Very subtle corner depth only.
let vig = CGGradient(colorsSpace: cs, colors: [rgb(0, 0, 0, 0), rgb(0, 0, 0, 0.10)] as CFArray, locations: [0.7, 1])!
ctx.drawRadialGradient(vig, startCenter: CGPoint(x: S/2, y: S/2), startRadius: 0,
                       endCenter: CGPoint(x: S/2, y: S/2), endRadius: S*0.82, options: [])

// Viewfinder corner brackets.
let inset: CGFloat = 180, arm: CGFloat = 168, t: CGFloat = 34, r = t/2
ctx.setFillColor(rgb(1, 1, 1, 0.96))
func bracket(_ corner: CGPoint, _ sx: CGFloat, _ sy: CGFloat) {
    let hx = sx > 0 ? corner.x : corner.x - arm
    let hRect = CGRect(x: hx, y: corner.y - r, width: arm, height: t)
    let vy = sy > 0 ? corner.y : corner.y - arm
    let vRect = CGRect(x: corner.x - r, y: vy, width: t, height: arm)
    ctx.addPath(CGPath(roundedRect: hRect, cornerWidth: r, cornerHeight: r, transform: nil))
    ctx.addPath(CGPath(roundedRect: vRect, cornerWidth: r, cornerHeight: r, transform: nil))
}
bracket(CGPoint(x: inset, y: inset), 1, 1)
bracket(CGPoint(x: S - inset, y: inset), -1, 1)
bracket(CGPoint(x: inset, y: S - inset), 1, -1)
bracket(CGPoint(x: S - inset, y: S - inset), -1, -1)
ctx.fillPath()

// Leaf, tilted, with a soft white->mint gradient body + midrib + veins.
ctx.saveGState()
ctx.translateBy(x: S/2, y: S/2 + 6)
ctx.rotate(by: -16 * .pi / 180)
let topP = CGPoint(x: 0, y: -210)
let botP = CGPoint(x: 0, y: 210)
let leaf = CGMutablePath()
leaf.move(to: topP)
leaf.addCurve(to: botP, control1: CGPoint(x: 168, y: -70), control2: CGPoint(x: 150, y: 120))
leaf.addCurve(to: topP, control1: CGPoint(x: -150, y: 120), control2: CGPoint(x: -168, y: -70))
// Soft shadow so the leaf lifts off the background.
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: rgb(0, 0, 0, 0.28))
ctx.addPath(leaf)
ctx.setFillColor(rgb(1, 1, 1))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
// Gradient body over the (shadowed) white leaf.
ctx.addPath(leaf)
ctx.clip()
let leafGrad = CGGradient(colorsSpace: cs, colors: [rgb(1, 1, 1), rgb(0.83, 0.99, 0.92)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(leafGrad, start: CGPoint(x: -120, y: -210), end: CGPoint(x: 150, y: 210), options: [])
// Specular sheen.
let sheen = CGGradient(colorsSpace: cs, colors: [rgb(1, 1, 1, 0.55), rgb(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(sheen, startCenter: CGPoint(x: -60, y: -90), startRadius: 0,
                       endCenter: CGPoint(x: -60, y: -90), endRadius: 220, options: [])
ctx.restoreGState()

// Midrib + symmetric veins (drawn in the same rotated space).
ctx.saveGState()
ctx.translateBy(x: S/2, y: S/2 + 6)
ctx.rotate(by: -16 * .pi / 180)
ctx.setStrokeColor(rgb(0.05, 0.55, 0.35, 0.92))
ctx.setLineCap(.round)
ctx.setLineWidth(12)
ctx.move(to: CGPoint(x: 0, y: 195)); ctx.addLine(to: CGPoint(x: 0, y: -195)); ctx.strokePath()
ctx.setLineWidth(8)
for y: CGFloat in [-90, -20, 55] {
    for side: CGFloat in [-1, 1] {
        ctx.move(to: CGPoint(x: 0, y: y))
        ctx.addQuadCurve(to: CGPoint(x: side * 96, y: y - 66), control: CGPoint(x: side * 52, y: y - 16))
        ctx.strokePath()
    }
}
ctx.restoreGState()

guard let image = ctx.makeImage() else { fatalError("image") }
let url = URL(fileURLWithPath: "/tmp/AppIcon-1024.png")
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("dest") }
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(url.path)")
