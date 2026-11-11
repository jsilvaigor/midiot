import Foundation

/// A file of sampled instruments (SoundFont or DLS) the sampler can load.
public struct SoundBank: Hashable, Sendable {
    public let url: URL
    /// True for the General MIDI set that ships with macOS, used when no SoundFont is bundled.
    public let isSystemFallback: Bool

    public var name: String { url.deletingPathExtension().lastPathComponent }

    /// The piano to use: the first SoundFont bundled with the app, else the macOS built-in sounds.
    public static func piano(in bundle: Bundle = .main) -> SoundBank {
        let bundled = (bundle.urls(forResourcesWithExtension: "sf2", subdirectory: nil) ?? [])
            + (bundle.urls(forResourcesWithExtension: "sf2", subdirectory: "SoundFonts") ?? [])
        if let url = bundled.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first {
            return SoundBank(url: url, isSystemFallback: false)
        }
        return .system
    }

    public static let system = SoundBank(
        url: URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls"),
        isSystemFallback: true
    )
}
