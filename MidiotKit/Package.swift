// swift-tools-version: 6.2
import PackageDescription

/// Modules and their dependency direction are described in docs/ARCHITECTURE.md.
let modules: [(name: String, dependencies: [Target.Dependency])] = [
    ("MusicCore", []),
    ("MidiIO", ["MusicCore", .product(name: "SwiftMIDIIO", package: "swift-midi-io")]),
    ("Sound", ["MusicCore"]),
    ("ScoreImport", ["MusicCore"]),
    ("Notation", ["MusicCore", .product(name: "VerovioToolkit", package: "verovio")]),
    ("Practice", ["MusicCore"]),
    ("Library", ["MusicCore", "ScoreImport", "Notation"]),
    ("DesignSystem", ["MusicCore"]),
    ("Sketch", ["MusicCore"]),
]

let package = Package(
    name: "MidiotKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: modules.map { .library(name: $0.name, targets: [$0.name]) },
    dependencies: [
        .package(url: "https://github.com/orchetect/swift-midi-io", from: "1.1.0"),
        // Verovio tags are not semantic versions (version-6.4.1), so the release is pinned by commit.
        .package(url: "https://github.com/rism-digital/verovio", revision: "fbe8f4695ab0a123cb096e0cf92354b44f7a2fb8"),
    ],
    targets: modules.map { module in
        .target(
            name: module.name,
            dependencies: module.dependencies,
            // Bundled typefaces, registered at launch by `Typography.registerFonts()`.
            resources: module.name == "DesignSystem" ? [.copy("Fonts")] : nil
        )
    } + [
        .testTarget(name: "MusicCoreTests", dependencies: ["MusicCore"]),
        .testTarget(name: "MidiIOTests", dependencies: ["MidiIO"]),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
        .testTarget(name: "SoundTests", dependencies: ["Sound"]),
        .testTarget(name: "ScoreImportTests", dependencies: ["ScoreImport"]),
        .testTarget(name: "LibraryTests", dependencies: ["Library", "Practice"], resources: [.copy("Fixtures")]),
        .testTarget(name: "PracticeTests", dependencies: ["Practice"]),
        .testTarget(name: "SketchTests", dependencies: ["Sketch"]),
        .testTarget(name: "NotationTests", dependencies: ["Notation", "ScoreImport"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v6]
)
