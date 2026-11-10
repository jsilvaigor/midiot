import SwiftUI

/// Design tokens for "Filament", the dark studio look (requirements DS-1, DS-2).
/// Every color, size and radius used by the app comes from here.
/// The full visual reference is described in docs/DESIGN.md.
public enum Palette {
    // Surfaces, darkest to lightest.
    public static let background = Color(hex: 0x0C0D10)
    public static let sidebar = Color(hex: 0x101114)
    public static let surface = Color(hex: 0x131418)
    public static let surfaceRaised = Color(hex: 0x1C1E23)
    /// Fill of the selected segment in a segmented control.
    public static let control = Color(hex: 0x26282E)
    public static let hairline = Color.white.opacity(0.07)
    public static let hairlineStrong = Color.white.opacity(0.12)
    /// Translucent fill for panels that float over moving content (falling notes).
    public static let glass = Color(hex: 0x18191E).opacity(0.78)

    // Text. All three pass 4.5:1 on `surface`.
    public static let textPrimary = Color(hex: 0xF3EFE7)
    public static let textSecondary = Color(hex: 0xA9A59D)
    public static let textTertiary = Color(hex: 0x85827B)

    /// The single warm accent. It means "now": hit line, playhead, current cue, primary action.
    public static let accent = Color(hex: 0xF2A649)
    /// Lighter accent for text on `accentSoft`.
    public static let accentHighlight = Color(hex: 0xF7C27E)
    /// Background of active toggles and selected rows.
    public static let accentSoft = Color(hex: 0xF2A649).opacity(0.12)
    /// Text and icons drawn on top of `accent`.
    public static let accentInk = Color(hex: 0x1A1206)

    // Hands (falling notes, keys, staff).
    public static let handRight = accent
    public static let handLeft = Color(hex: 0x86A0DD)

    // Note feedback (requirement FB-1). These replace the hand color once a key is played.
    public static let noteCorrect = Color(hex: 0x5FD39A)
    public static let noteWrong = Color(hex: 0xF0625D)
    public static let noteEarly = Color(hex: 0x5BB8F5)
    public static let noteLate = Color(hex: 0xB58CF5)

    // Piano keys.
    public static let keyWhite = Color(hex: 0xF4F1EA)
    public static let keyWhiteShade = Color(hex: 0xDAD5CB)
    public static let keyBlack = Color(hex: 0x121316)
}

public enum Spacing {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 16
    public static let l: CGFloat = 24
    public static let xl: CGFloat = 40
    public static let xxl: CGFloat = 64
}

public enum Radius {
    public static let control: CGFloat = 8
    public static let button: CGFloat = 12
    public static let panel: CGFloat = 18
    public static let card: CGFloat = 20
}

public extension Color {
    /// Opaque sRGB color from a 0xRRGGBB literal.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
