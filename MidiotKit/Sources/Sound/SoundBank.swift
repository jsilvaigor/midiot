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
        let sorted = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
        if let match = sorted.first(where: { isGeneralMIDI($0) == isPalette }) {
            return SoundBank(url: match, isSystemFallback: false)
        }
        if hasSystemSounds { return .system }
        // The iPad has no built-in set and bundles one General MIDI SoundFont for everything.
        return sorted.first.map { SoundBank(url: $0, isSystemFallback: false) } ?? .system
    }

    /// The bank with the drum kit the metronome clicks on: the macOS built-in sounds, else
    /// the bundled General MIDI set.
    public static func clicks(in bundle: Bundle = .main) -> SoundBank {
        hasSystemSounds ? .system : palette(in: bundle)
    }

    /// False on the iPad, which has no General MIDI set of its own.
    static var hasSystemSounds: Bool { FileManager.default.fileExists(atPath: system.url.path) }

    private static func bundled(in bundle: Bundle) -> [URL] {
        // "SoundFontsPad" is the folder the iPad app carries instead of "SoundFonts".
        [nil, "SoundFonts", "SoundFontsPad"].flatMap {
            bundle.urls(forResourcesWithExtension: "sf2", subdirectory: $0) ?? []
        }
    }

    public static let system = SoundBank(
        url: URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls"),
        isSystemFallback: true
    )
}
