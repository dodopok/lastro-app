import Foundation

/// Cor em OKLCH, o espaço que o design usa (`oklch(.55 .21 262)`).
/// Converte para Display P3, que é como o Safari renderiza oklch num iPhone,
/// então o app bate com o protótipo mesmo nos azuis saturados fora do sRGB.
public struct OKLCH: Hashable, Sendable {
    public var l: Double  // 0...1
    public var c: Double  // croma, ~0...0.37
    public var h: Double  // graus
    public var alpha: Double

    public init(_ l: Double, _ c: Double, _ h: Double, alpha: Double = 1) {
        self.l = l
        self.c = c
        self.h = h
        self.alpha = alpha
    }

    public struct RGB: Hashable, Sendable {
        public var r: Double, g: Double, b: Double
    }

    /// Componentes gamma-encoded em Display P3, 0...1.
    public var displayP3: RGB {
        let lin = linearSRGB
        // sRGB linear → Display P3 linear (mesmo branco D65)
        let r = 0.8224621 * lin.r + 0.1775380 * lin.g + 0.0000000 * lin.b
        let g = 0.0331941 * lin.r + 0.9668058 * lin.g + 0.0000000 * lin.b
        let b = 0.0170827 * lin.r + 0.0723974 * lin.g + 0.9105199 * lin.b
        return RGB(r: Self.encode(r), g: Self.encode(g), b: Self.encode(b))
    }

    /// Componentes gamma-encoded em sRGB, 0...1 (fora da gama é recortado).
    public var sRGB: RGB {
        let lin = linearSRGB
        return RGB(r: Self.encode(lin.r), g: Self.encode(lin.g), b: Self.encode(lin.b))
    }

    var linearSRGB: RGB {
        let hr = h * .pi / 180
        let a = c * cos(hr), bb = c * sin(hr)
        let l_ = l + 0.3963377774 * a + 0.2158037573 * bb
        let m_ = l - 0.1055613458 * a - 0.0638541728 * bb
        let s_ = l - 0.0894841775 * a - 1.2914855480 * bb
        let L = l_ * l_ * l_, M = m_ * m_ * m_, S = s_ * s_ * s_
        return RGB(
            r: +4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S,
            g: -1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S,
            b: -0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S
        )
    }

    static func encode(_ x: Double) -> Double {
        let v = min(max(x, 0), 1)
        return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
    }
}

/// A paleta do design. Uma cor só de ação; cor de categoria só em ícone e barra.
public enum Palette {
    public static let accent = OKLCH(0.55, 0.21, 262)       // azul cobalto
    public static let accentTop = OKLCH(0.63, 0.20, 262)    // gradiente do botão +
    public static let accentBottom = OKLCH(0.50, 0.22, 264)
    public static let green = OKLCH(0.56, 0.14, 155)
    public static let red = OKLCH(0.57, 0.20, 25)
    public static let amber = OKLCH(0.64, 0.15, 62)

    /// Ícone e barra de uma categoria: `oklch(.54 .15 h)`.
    public static func category(_ hue: Double) -> OKLCH { OKLCH(0.54, 0.15, hue) }

    /// Fundo do ícone: `oklch(.6 .15 h / .16)`.
    public static func categoryTint(_ hue: Double, alpha: Double = 0.16) -> OKLCH {
        OKLCH(0.6, 0.15, hue, alpha: alpha)
    }

    /// Cartão de crédito: gradiente de `oklch(.62 .16 h)` a `oklch(.42 .15 h+25)`.
    public static func card(_ hue: Double) -> (top: OKLCH, bottom: OKLCH) {
        (OKLCH(0.62, 0.16, hue), OKLCH(0.42, 0.15, hue + 25))
    }
}
