import AppKit
import SwiftUI

struct LabelColor: Codable {
    struct RGB: Codable {
        let red: Double
        let green: Double
        let blue: Double

        var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
        init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = red; self.green = green; self.blue = blue
        }
        init(_ color: NSColor) {
            let rgb = color.usingColorSpace(.sRGB) ?? .systemOrange
            self.init(Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent))
        }
    }

    let light: RGB
    let dark: RGB

    var color: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? dark.nsColor : light.nsColor
        })
    }

    init(_ color: Color) {
        let rgb = RGB(NSColor(color))
        light = rgb
        dark = rgb
    }

    private init(light: RGB, dark: RGB) {
        self.light = light; self.dark = dark
    }

    static func random() -> LabelColor {
        harmonious(hue: Double.random(in: 0..<1))
    }

    static func preview(for label: String) -> LabelColor {
        let hash = label.lowercased().unicodeScalars.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1.value) }
        return harmonious(hue: Double(hash % 100_000) / 100_000)
    }

    private static func harmonious(hue: Double) -> LabelColor {
        LabelColor(
            light: RGB(NSColor(calibratedHue: hue, saturation: 0.52, brightness: 0.66, alpha: 1)),
            dark: RGB(NSColor(calibratedHue: hue, saturation: 0.38, brightness: 0.87, alpha: 1))
        )
    }
    #if DEVNOTES_DEMO
    static func demoPalette(_ index: Int) -> LabelColor {
        let pairs: [(RGB, RGB)] = [
            (RGB(0.74, 0.31, 0.20), RGB(0.95, 0.49, 0.35)),
            (RGB(0.28, 0.43, 0.61), RGB(0.47, 0.64, 0.82)),
            (RGB(0.34, 0.49, 0.36), RGB(0.51, 0.68, 0.51)),
            (RGB(0.43, 0.37, 0.57), RGB(0.66, 0.58, 0.79)),
            (RGB(0.25, 0.48, 0.47), RGB(0.43, 0.68, 0.66)),
            (RGB(0.61, 0.35, 0.42), RGB(0.80, 0.52, 0.59)),
            (RGB(0.55, 0.43, 0.23), RGB(0.75, 0.62, 0.39)),
            (RGB(0.34, 0.43, 0.49), RGB(0.56, 0.66, 0.72))
        ]
        let pair = pairs[((index % pairs.count) + pairs.count) % pairs.count]
        return LabelColor(light: pair.0, dark: pair.1)
    }
    #endif
}
