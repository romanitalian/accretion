// Renders the 1024×1024 app icon. Usage: swift scripts/make-icon.swift <output.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let side = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

func glow(at center: CGPoint, core: CGFloat, halo: CGFloat, r: Double, g: Double, b: Double) {
    let colors = [color(r, g, b, 1), color(r, g, b, 0.95), color(r, g, b, 0.25), color(r, g, b, 0)] as CFArray
    let coreStop = core / halo
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, coreStop * 0.85, coreStop, 1])!
    ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: halo, options: [])
}

// Deep space background with a soft vignette toward the centre.
let bg = CGGradient(colorsSpace: space, colors: [color(0.06, 0.08, 0.22), color(0.01, 0.02, 0.07)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(bg, startCenter: CGPoint(x: 512, y: 560), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 512), endRadius: 760, options: [.drawsAfterEndLocation])

// Faint background stars (fixed pseudo-random positions).
var seed: UInt64 = 7
func rand() -> Double {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return Double(seed >> 11) / Double(1 << 53)
}
for _ in 0..<70 {
    let s = 2 + rand() * 4
    ctx.setFillColor(color(1, 1, 1, 0.15 + rand() * 0.35))
    ctx.fillEllipse(in: CGRect(x: rand() * 1024, y: rand() * 1024, width: s, height: s))
}

// Matter streaming into the player star.
for i in 0..<14 {
    let t = Double(i) / 13
    let x = 300 + (470 - 300) * t
    let y = 330 + (460 - 330) * t + sin(t * .pi) * 30
    glow(at: CGPoint(x: x, y: y), core: CGFloat(10 - 6 * t), halo: CGFloat(22 - 10 * t), r: 0.43, g: 0.78, b: 1)
}

glow(at: CGPoint(x: 280, y: 320), core: 42, halo: 80, r: 0.43, g: 0.78, b: 1)       // prey
glow(at: CGPoint(x: 800, y: 790), core: 34, halo: 64, r: 1, g: 0.42, b: 0.42)       // threat
glow(at: CGPoint(x: 820, y: 260), core: 16, halo: 32, r: 0.43, g: 0.78, b: 1)
glow(at: CGPoint(x: 210, y: 780), core: 12, halo: 26, r: 0.43, g: 0.78, b: 1)
glow(at: CGPoint(x: 540, y: 530), core: 170, halo: 300, r: 1, g: 0.83, b: 0.43)     // player

let image = ctx.makeImage()!
let url = URL(fileURLWithPath: output)
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
precondition(CGImageDestinationFinalize(dest), "failed to write \(output)")
print("wrote \(output)")
