// Writes the disk image's background: design/dmg/background.png and background@2x.png.
//
//     xcrun swift design/dmg/make-background.swift
//
// dmgbuild merges the pair into one HiDPI TIFF (scripts/dmg-settings.py). Finder pins the picture
// to the top left of the window's content, which is the window minus its 32 pt title bar, so the
// last 32 pt of the canvas are bleed and stay empty. Coordinates are points from the top left,
// like dmgbuild's icon_locations: change a position here and there together.
import AppKit

let canvas = CGSize(width: 640, height: 400)
let appIcon = CGPoint(x: 180, y: 196) // icon centres, as in scripts/dmg-settings.py
let applications = CGPoint(x: 460, y: 196)
let headlineY = 68.0

// The keycap from design/icon/make-icon.swift, on its 1024-point canvas.
let cap = (x: 252.0, y: 232.0, w: 520.0, h: 560.0, radius: 120.0)
let face = (x: 292.0, y: 252.0, w: 440.0, h: 440.0, radius: 90.0)
let brand = NSColor(srgbRed: 0.28, green: 0.36, blue: 0.96, alpha: 1)
let ink = NSColor(srgbRed: 0.11, green: 0.12, blue: 0.22, alpha: 1)

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    return font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? font
}

// A keycap `height` tall with its top left at `origin`: a light indigo base whose lower part shows
// as the key's front, a white face, and the legend in indigo.
func keycapWidth(height: CGFloat) -> CGFloat { height * cap.w / cap.h }

func drawKeycap(_ legend: String, origin: CGPoint, height: CGFloat, in ctx: CGContext) {
    let k = height / cap.h
    let base = CGRect(x: origin.x, y: origin.y, width: cap.w * k, height: cap.h * k)
    let top = CGRect(x: origin.x + (face.x - cap.x) * k, y: origin.y + (face.y - cap.y) * k,
                     width: face.w * k, height: face.h * k)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: height * 0.10), blur: height * 0.30,
                  color: brand.withAlphaComponent(0.30).cgColor)
    ctx.addPath(CGPath(roundedRect: base, cornerWidth: cap.radius * k, cornerHeight: cap.radius * k, transform: nil))
    ctx.setFillColor(brand.blended(withFraction: 0.55, of: .white)!.cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(CGPath(roundedRect: top, cornerWidth: face.radius * k, cornerHeight: face.radius * k, transform: nil))
    ctx.setFillColor(.white)
    ctx.fillPath()
    let text = NSAttributedString(string: legend, attributes: [
        .font: rounded(face.h * k * 0.56, .bold), .foregroundColor: brand,
    ])
    let size = text.size()
    text.draw(at: CGPoint(x: top.midX - size.width / 2, y: top.midY - size.height / 2))
}

// The window-picking letters, drifting at the edges at different depths: (centre, height, degrees
// of tilt, opacity).
let drifting: [(String, CGPoint, CGFloat, CGFloat, CGFloat)] = [
    ("A", CGPoint(x: 64, y: 72), 46, -12, 0.55),
    ("S", CGPoint(x: 34, y: 196), 24, 16, 0.30),
    ("D", CGPoint(x: 92, y: 318), 32, 8, 0.40),
    ("F", CGPoint(x: 580, y: 64), 38, 14, 0.50),
    ("J", CGPoint(x: 610, y: 186), 22, -18, 0.28),
    ("K", CGPoint(x: 560, y: 314), 30, -8, 0.38),
]

func draw(in ctx: CGContext) {
    let rgb = CGColorSpace(name: CGColorSpace.sRGB)!

    // A cool white, deepening a little towards the bottom, with an indigo glow behind the icons.
    let wash = CGGradient(colorsSpace: rgb, colors: [
        CGColor(srgbRed: 0.988, green: 0.988, blue: 1.0, alpha: 1),
        CGColor(srgbRed: 0.925, green: 0.935, blue: 1.0, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(wash, start: .zero, end: CGPoint(x: 0, y: canvas.height), options: [])
    let glow = CGGradient(colorsSpace: rgb, colors: [
        brand.withAlphaComponent(0.13).cgColor, brand.withAlphaComponent(0).cgColor,
    ] as CFArray, locations: [0, 1])!
    let middle = CGPoint(x: canvas.width / 2, y: appIcon.y)
    ctx.drawRadialGradient(glow, startCenter: middle, startRadius: 0, endCenter: middle, endRadius: 300, options: [])

    // A faint dot grid that fades out towards the middle, so the icons sit on a clean field.
    ctx.saveGState()
    for x in stride(from: 8.0, to: canvas.width, by: 16) {
        for y in stride(from: 8.0, to: canvas.height, by: 16) {
            let d = hypot((x - middle.x) / 320, (y - middle.y) / 200)
            let alpha = max(0, min(1, (d - 0.55) / 0.6)) * 0.16
            guard alpha > 0.005 else { continue }
            ctx.setFillColor(brand.withAlphaComponent(alpha).cgColor)
            ctx.fillEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
        }
    }
    ctx.restoreGState()

    for (legend, centre, height, tilt, opacity) in drifting {
        ctx.saveGState()
        ctx.setAlpha(opacity)
        ctx.translateBy(x: centre.x, y: centre.y)
        ctx.rotate(by: tilt * .pi / 180)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        drawKeycap(legend, origin: CGPoint(x: -keycapWidth(height: height) / 2, y: -height / 2), height: height, in: ctx)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    // The headline: "Drag. Drop." and then the shortcut itself, as two keys.
    let words = NSAttributedString(string: "Drag. Drop.", attributes: [
        .font: rounded(30, .bold), .foregroundColor: ink, .kern: -0.3,
    ])
    let keyHeight = 40.0, keyGap = 6.0, wordGap = 14.0
    let width = words.size().width + wordGap + 2 * keycapWidth(height: keyHeight) + keyGap
    var x = (canvas.width - width) / 2
    words.draw(at: CGPoint(x: x, y: headlineY - words.size().height / 2))
    x += words.size().width + wordGap
    for legend in ["⌘", "§"] {
        // The face sits above the key's middle, so lift the key until the face lines up with the words.
        drawKeycap(legend, origin: CGPoint(x: x, y: headlineY - keyHeight * 0.44), height: keyHeight, in: ctx)
        x += keycapWidth(height: keyHeight) + keyGap
    }

    // The arrow: a hop from the app that lands level at Applications, dots growing into a chevron.
    let from = CGPoint(x: appIcon.x + 84, y: appIcon.y), to = CGPoint(x: applications.x - 80, y: applications.y)
    let rise = CGPoint(x: from.x + 36, y: from.y - 36), land = CGPoint(x: to.x - 46, y: to.y)
    func point(_ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * from.x + b * rise.x + c * land.x + d * to.x,
                       y: a * from.y + b * rise.y + c * land.y + d * to.y)
    }
    let dots = 10
    for i in 0..<dots {
        let t = 0.84 * CGFloat(i) / CGFloat(dots - 1)
        let p = point(t), r = 1.5 + 1.8 * t
        ctx.setFillColor(brand.withAlphaComponent(0.22 + 0.78 * t).cgColor)
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
    }
    ctx.move(to: CGPoint(x: to.x - 9, y: to.y - 10))
    ctx.addLine(to: to)
    ctx.addLine(to: CGPoint(x: to.x - 9, y: to.y + 10))
    ctx.setStrokeColor(brand.cgColor)
    ctx.setLineWidth(4.5)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
}

func render(scale: CGFloat, to url: URL) throws {
    let ctx = CGContext(data: nil, width: Int(canvas.width * scale), height: Int(canvas.height * scale),
                        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Flip to top-left points, like Finder's.
    ctx.translateBy(x: 0, y: canvas.height * scale)
    ctx.scaleBy(x: scale, y: -scale)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    draw(in: ctx)
    NSGraphicsContext.current = nil
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    rep.size = canvas // 72 dpi at 1x, 144 at 2x, which tiffutil needs to pair them
    try rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote \(url.path)")
}

let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
try render(scale: 1, to: folder.appendingPathComponent("background.png"))
try render(scale: 2, to: folder.appendingPathComponent("background@2x.png"))
