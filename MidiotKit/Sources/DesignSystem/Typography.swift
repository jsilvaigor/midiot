import CoreText
import SwiftUI

/// Bundled typefaces. All three are SIL Open Font License 1.1; see Resources/LICENSES.md.
///
/// - Instrument Serif: song titles, screen titles and large numbers.
/// - Geist: interface text.
/// - Geist Mono: readouts that change while you watch (bar, tempo, latency).
public enum Typography {
    /// Registers the fonts in `Fonts/` for this process. Call once at launch.
    public static func registerFonts() {
        guard let urls = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts"),
              !urls.isEmpty
        else { return }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }
}

public extension Font {
    static func serif(_ size: CGFloat, italic: Bool = false) -> Font {
        .custom(italic ? "InstrumentSerif-Italic" : "InstrumentSerif-Regular", size: size)
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Geist", size: size).weight(weight)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Geist Mono", size: size).weight(weight)
    }

    /// Big score on the after-run review.
    static let hero = serif(112)
    /// Screen titles: "Library", a song title on its own screen.
    static let display = serif(52)
    /// Titles inside a screen: empty states, cards, the song in the practice header.
    static let displayTitle = serif(28)
    static let sectionTitle = sans(17, weight: .semibold)
    static let bodyText = sans(14)
    static let control = sans(13, weight: .medium)
    static let caption = sans(12)
    /// Small caps label; use with `.capsLabel()` for tracking and case.
    static let label = sans(11, weight: .medium)
    static let readout = mono(20)
    static let readoutSmall = mono(13)
}

public extension View {
    /// Section label: 11 pt, uppercase, wide tracking, tertiary color.
    func capsLabel() -> some View {
        font(.label)
            .tracking(0.9)
            .textCase(.uppercase)
            .foregroundStyle(Palette.textTertiary)
    }
}
