import Foundation

/// A file of sampled instruments (SoundFont or DLS) the sampler can load.
public struct SoundBank: Hashable, Sendable {
    public let url: URL
    /// True for the General MIDI set that ships with macOS, used when no SoundFont is bundled.
    public let isSystemFallback: Bool

    public var name: String { url.deletingPathExtension().lastPathComponent }

    /// The piano to use: a bundled piano SoundFont, else the macOS built-in sounds.
    public static func piano(in bundle: Bundle = .main) -> SoundBank {
        choose(from: bundled(in: bundle), isPalette: false)
    }

    /// The bank for the wider palette of sounds (requirement SN-2): a bundled General MIDI
    /// SoundFont, else the macOS built-in sounds, which cover the same instruments.
    public static func palette(in bundle: Bundle = .main) -> SoundBank {
        choose(from: bundled(in: bundle), isPalette: true)
    }

    /// Picks among SoundFont files by name: General MIDI sets are named "GeneralUser" or "GM";
    /// anything else is taken to be a piano.
    static func choose(from urls: [URL], isPalette: Bool) -> SoundBank {
        func isGeneralMIDI(_ url: URL) -> Bool {
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            return name.contains("generaluser") || name.hasPrefix("gm") || name.contains("general midi")
        }
        let match = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.first { isGeneralMIDI($0) == isPalette }
        return match.map { SoundBank(url: $0, isSystemFallback: false) } ?? .system
    }

    private static func bundled(in bundle: Bundle) -> [URL] {
        (bundle.urls(forResourcesWithExtension: "sf2", subdirectory: nil) ?? [])
            + (bundle.urls(forResourcesWithExtension: "sf2", subdirectory: "SoundFonts") ?? [])
    }

    public static let system = SoundBank(
        url: URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls"),
        isSystemFallback: true
    )
}
