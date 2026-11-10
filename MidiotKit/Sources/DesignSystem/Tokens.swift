import SwiftUI

/// Design tokens for the dark studio look (requirement DS-1).
/// Every color, size and radius used by the app comes from here.
public enum Palette {
    // Surfaces, darkest to lightest.
    public static let background = Color(hex: 0x0E0F12)
    public static let surface = Color(hex: 0x16171B)
    public static let surfaceRaised = Color(hex: 0x1E2025)
    public static let hairline = Color.white.opacity(0.08)

    // Text.
    public static let textPrimary = Color(hex: 0xF2F0EC)
    public static let textSecondary = Color(hex: 0xF2F0EC).opacity(0.62)
    public static let textTertiary = Color(hex: 0xF2F0EC).opacity(0.38)

    /// The single warm accent.
    public static let accent = Color(hex: 0xE8A857)

    // Note feedback (requirement FB-1).
    public static let noteCorrect = Color(hex: 0x5FD39A)
    public static let noteWrong = Color(hex: 0xF0625D)
    public static let noteEarly = Color(hex: 0x5BB8F5)
    public static let noteLate = Color(hex: 0xB58CF5)

    // On-screen piano keys.
    public static let keyWhite = Color(hex: 0xF4F1EA)
    public static let keyWhiteShade = Color(hex: 0xD9D5CC)
    public static let keyBlack = Color(hex: 0x0B0B0D)
    public static let keyBlackShade = Color(hex: 0x2A2B30)
    public static let keyLabel = Color(hex: 0x8A867D)
}

public enum Spacing {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 16
    public static let l: CGFloat = 24
    public static let xl: CGFloat = 40
}

public enum Radius {
    public static let control: CGFloat = 8
    public static let panel: CGFloat = 14
}

public extension Font {
    static let displayTitle = Font.system(size: 28, weight: semiboldWeight, design: .rounded)
    static let sectionTitle = Font.system(size: 17, weight: semiboldWeight)
    static let bodyText = Font.system(size: 14)
    static let captionText = Font.system(size: 12)

    private static let semiboldWeight = Font.Weight.semibold
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
