// swift-tools-version: 6.2
import PackageDescription

/// Modules and their dependency direction are described in docs/ARCHITECTURE.md.
let modules: [(name: String, dependencies: [Target.Dependency])] = [
    ("MusicCore", []),
    ("MidiIO", ["MusicCore"]),
    ("Sound", ["MusicCore"]),
    ("ScoreImport", ["MusicCore"]),
    ("Notation", ["MusicCore"]),
    ("Practice", ["MusicCore"]),
    ("Library", ["MusicCore"]),
    ("DesignSystem", ["MusicCore"]),
]

let package = Package(
    name: "MidiotKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: modules.map { .library(name: $0.name, targets: [$0.name]) },
    targets: modules.map { .target(name: $0.name, dependencies: $0.dependencies) } + [
        .testTarget(name: "MusicCoreTests", dependencies: ["MusicCore"]),
    ],
    swiftLanguageModes: [.v6]
)
