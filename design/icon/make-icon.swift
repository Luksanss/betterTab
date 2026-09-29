// Writes BetterTab/AppIcon.icon, the app icon, from the menu-bar glyph in StatusIcon.swift.
//
//     xcrun swift design/icon/make-icon.swift [output.icon]
//
// The icon is an Icon Composer document: icon.json plus one SVG per layer. Xcode's actool turns it
// into Assets.car and AppIcon.icns, with the light, dark, tinted and clear looks.
import Foundation

// The glyph, in the menu-bar points StatusIcon.swift draws it in: an 18 × 14 box, the back window
// 12 × 9 at (6, 0), the front window 13 × 10 at (0, 4), corner radius 2.5, a 1.5 pt gap around the
// front window. `scale` blows that up onto Icon Composer's 1024-point canvas.
let scale = 38.0
let backOpacity = "0.55"
let brand = "extended-srgb:0.28000,0.36000,0.96000,1.00000" // indigo blue

let canvas = 1024.0
let origin = ((canvas - 18 * scale) / 2, (canvas - 14 * scale) / 2)

struct Box {
    var x, y, w, h: Double
    init(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        (self.x, self.y, self.w, self.h) = (origin.0 + x * scale, origin.1 + y * scale, w * scale, h * scale)
    }
    var maxX: Double { x + w }
    var maxY: Double { y + h }
}
let back = Box(6, 0, 12, 9)
let front = Box(0, 4, 13, 10)
let r = 2.5 * scale
let gap = 1.5 * scale

func n(_ v: Double) -> String {
    let rounded = (v * 100).rounded() / 100
    return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
}

func arc(_ radius: Double, _ x: Double, _ y: Double, clockwise: Bool = true) -> String {
    "A\(n(radius)),\(n(radius)) 0 0 \(clockwise ? 1 : 0) \(n(x)),\(n(y))"
}

// The front window: a rounded rectangle.
let frontPath = [
    "M\(n(front.x + r)),\(n(front.y)) H\(n(front.maxX - r))", arc(r, front.maxX, front.y + r),
    "V\(n(front.maxY - r))", arc(r, front.maxX - r, front.maxY),
    "H\(n(front.x + r))", arc(r, front.x, front.maxY - r),
    "V\(n(front.y + r))", arc(r, front.x + r, front.y), "Z",
].joined(separator: " ")

// The back window, less the front window grown by the gap. The cut's corner has the grown radius.
// In the glyph the cut's top edge lands exactly where the back window's top-left arc ends.
let cutTop = front.y - gap, cutRight = front.maxX + gap, cutRadius = r + gap
precondition(
    cutTop >= back.y + r && cutTop + cutRadius <= back.maxY && cutRight - cutRadius >= back.x
        && cutRight <= back.maxX - r,
    "the front window must cut only into the back one's lower left, as in the glyph"
)
let backPath = [
    "M\(n(back.x)),\(n(back.y + r))", arc(r, back.x + r, back.y),
    "H\(n(back.maxX - r))", arc(r, back.maxX, back.y + r),
    "V\(n(back.maxY - r))", arc(r, back.maxX - r, back.maxY),
    "H\(n(cutRight)) V\(n(cutTop + cutRadius))", arc(cutRadius, cutRight - cutRadius, cutTop, clockwise: false),
    "H\(n(back.x)) Z",
].joined(separator: " ")

func svg(_ d: String) -> String {
    """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
      <path fill="#FFFFFF" d="\(d)"/>
    </svg>

    """
}

// Light: white windows on an indigo gradient. Dark: indigo windows on the system's dark background.
// The first group is drawn on top; each window is its own group so the front one casts a shadow on
// the back one. The system derives the tinted and clear looks.
func windowGroup(_ name: String, opacity: String? = nil) -> [String: Any] {
    var layer: [String: Any] = [
        "name": name,
        "image-name": "\(name).svg",
        "glass": true,
        "fill-specializations": [
            ["value": ["solid": "extended-srgb:1.00000,1.00000,1.00000,1.00000"]],
            ["appearance": "dark", "value": ["automatic-gradient": brand]],
        ],
    ]
    if let opacity { layer["opacity"] = NSDecimalNumber(string: opacity) }
    return [
        "name": name.capitalized,
        "layers": [layer],
        "shadow": ["kind": "neutral", "opacity": 0.5],
        "translucency": ["enabled": false, "value": 0.5],
    ]
}

let icon: [String: Any] = [
    "fill-specializations": [
        ["value": ["automatic-gradient": brand]],
        ["appearance": "dark", "value": "automatic"],
    ],
    "groups": [windowGroup("front"), windowGroup("back", opacity: backOpacity)],
    "supported-platforms": ["squares": ["macOS"]],
]

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : repo.appendingPathComponent("BetterTab/AppIcon.icon")
precondition(output.pathExtension == "icon", "the output must be a .icon bundle, since it is replaced")
let assets = output.appendingPathComponent("Assets")
try? FileManager.default.removeItem(at: output)
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
try svg(frontPath).write(to: assets.appendingPathComponent("front.svg"), atomically: true, encoding: .utf8)
try svg(backPath).write(to: assets.appendingPathComponent("back.svg"), atomically: true, encoding: .utf8)
let json = try JSONSerialization.data(withJSONObject: icon, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
try (json + Data("\n".utf8)).write(to: output.appendingPathComponent("icon.json"))
print("wrote \(output.path)")
