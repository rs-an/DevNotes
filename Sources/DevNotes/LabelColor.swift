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
}
