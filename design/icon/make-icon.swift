// Writes BetterTab/AppIcon.icon, the app icon: a home-row keycap labelled A, the key that picks a
// window.
//
//     xcrun swift design/icon/make-icon.swift [output.icon]
//
// The icon is an Icon Composer document: icon.json plus one SVG per layer. Xcode's actool turns it
// into Assets.car and AppIcon.icns, with the light, dark, tinted and clear looks.
import Foundation

// On Icon Composer's 1024-point canvas: the keycap's base, its top face (set higher, so the base
// shows below it as the key's front), and the letter's size and line width, centred on the face.
let cap = (x: 252.0, y: 232.0, w: 520.0, h: 560.0, radius: 120.0)
let face = (x: 292.0, y: 252.0, w: 440.0, h: 440.0, radius: 90.0)
let letter = (height: 262.0, width: 244.0, stroke: 66.0, crossbar: 0.64)
let capOpacity = "0.6"
let brand = "extended-srgb:0.28000,0.36000,0.96000,1.00000" // indigo blue

func n(_ v: Double) -> String {
    let rounded = (v * 100).rounded() / 100
    return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
}

func roundedRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> String {
    let arc = { (x: Double, y: Double) in "A\(n(r)),\(n(r)) 0 0 1 \(n(x)),\(n(y))" }
    return [
        "M\(n(x + r)),\(n(y)) H\(n(x + w - r))", arc(x + w, y + r),
        "V\(n(y + h - r))", arc(x + w - r, y + h),
        "H\(n(x + r))", arc(x, y + h - r),
        "V\(n(y + r))", arc(x + r, y), "Z",
    ].joined(separator: " ")
}

// A geometric A as three filled capsules: two legs meeting at the top, and a crossbar part of the
// way down. Filled shapes, not a stroke: actool fills the layer's paths, and a stroked path would
// lose its counter.
func capsule(_ a: (Double, Double), _ b: (Double, Double), radius r: Double) -> String {
    let length = hypot(b.0 - a.0, b.1 - a.1)
    let normal = (-(b.1 - a.1) / length * r, (b.0 - a.0) / length * r)
    let point = { (p: (Double, Double), sign: Double) in "\(n(p.0 + sign * normal.0)),\(n(p.1 + sign * normal.1))" }
    let arc = "A\(n(r)),\(n(r)) 0 0 0"
    return "M\(point(a, 1)) L\(point(b, 1)) \(arc) \(point(b, -1)) L\(point(a, -1)) \(arc) \(point(a, 1)) Z"
}

func letterA() -> [String] {
    let cx = face.x + face.w / 2, cy = face.y + face.h / 2
    let top = cy - letter.height / 2, bottom = cy + letter.height / 2
    let barY = top + letter.height * letter.crossbar
    let half = letter.width / 2 * letter.crossbar
    let r = letter.stroke / 2
    return [
        capsule((cx - letter.width / 2, bottom), (cx, top), radius: r),
        capsule((cx, top), (cx + letter.width / 2, bottom), radius: r),
        capsule((cx - half, barY), (cx + half, barY), radius: r),
    ]
}

func svg(_ element: String) -> String {
    """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
      \(element)
    </svg>

    """
}

let svgs = [
    "cap": svg("<path fill=\"#FFFFFF\" d=\"\(roundedRect(cap.x, cap.y, cap.w, cap.h, cap.radius))\"/>"),
    "face": svg("<path fill=\"#FFFFFF\" d=\"\(roundedRect(face.x, face.y, face.w, face.h, face.radius))\"/>"),
    // One path per capsule, so where they overlap they add up whatever the fill rule.
    "letter": svg(letterA().map { "<path fill=\"#FFFFFF\" d=\"\($0)\"/>" }.joined(separator: "\n  ")),
]

func solid(_ light: String, dark: String) -> [[String: Any]] {
    [["value": ["solid": light]], ["appearance": "dark", "value": ["solid": dark]]]
}

func layer(_ name: String, glass: Bool, fill: [[String: Any]], opacity: String? = nil) -> [String: Any] {
    var layer: [String: Any] = ["name": name, "image-name": "\(name).svg", "glass": glass, "fill-specializations": fill]
    if let opacity { layer["opacity"] = NSDecimalNumber(string: opacity) }
    return layer
}

func group(_ name: String, _ layers: [[String: Any]], shadow: String) -> [String: Any] {
    ["name": name, "layers": layers, "shadow": ["kind": shadow, "opacity": 0.5], "translucency": ["enabled": false, "value": 0.5]]
}

// Light: a white key with an indigo A on an indigo gradient. Dark: a grey key with a white A on the
// system's dark background. The first group is drawn on top. The system derives the tinted and
// clear looks.
let white = "extended-srgb:1.00000,1.00000,1.00000,1.00000"
let icon: [String: Any] = [
    "fill-specializations": [
        ["value": ["automatic-gradient": brand]],
        ["appearance": "dark", "value": "automatic"],
    ],
    "groups": [
        group("Letter", [layer("letter", glass: false, fill: solid(brand, dark: white))], shadow: "none"),
        group("Key", [
            layer("face", glass: true, fill: solid(white, dark: "extended-gray:0.32000,1.00000")),
            layer("cap", glass: true, fill: solid(white, dark: "extended-gray:0.22000,1.00000"), opacity: capOpacity),
        ], shadow: "neutral"),
    ],
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
for (name, body) in svgs {
    try body.write(to: assets.appendingPathComponent("\(name).svg"), atomically: true, encoding: .utf8)
}
let json = try JSONSerialization.data(withJSONObject: icon, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
try (json + Data("\n".utf8)).write(to: output.appendingPathComponent("icon.json"))
print("wrote \(output.path)")
