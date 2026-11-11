import AppKit
import MusicCore
import SwiftUI
import Testing
@testable import DesignSystem

/// Renders components to PNG files for visual review. Runs only when SNAPSHOT_OUT names a folder:
/// `SNAPSHOT_OUT=/some/folder swift test --filter Snapshot`.
@Suite struct SnapshotTests {
    @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["SNAPSHOT_OUT"] != nil))
    func components() throws {
        Typography.registerFonts()
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SNAPSHOT_OUT"]!)

        try save(
            VStack(spacing: 0) {
                EmptyState(systemImage: "pianokeys", title: "Nothing to practice yet",
                           message: "Choose a song from the Library to start practicing.")
                KeyboardView(
                    range: .fortyNineKeys,
                    highlights: [Pitch(midiNumber: 60): Palette.handRight, Pitch(midiNumber: 64): Palette.handRight,
                                 Pitch(midiNumber: 66): Palette.handRight, Pitch(midiNumber: 43): Palette.handLeft],
                    naming: .solfege
                )
                .frame(height: 150)
                .padding(Spacing.m)
                .background(Palette.surface)
                .overlay(alignment: .top) { Palette.accent.frame(height: 2).filamentGlow() }
            }
            .frame(width: 1040, height: 620),
            to: folder.appendingPathComponent("practice.png")
        )
        try save(
            KeyboardView(range: .twentyFiveKeys, highlights: [Pitch(midiNumber: 61): Palette.handRight])
                .frame(width: 660, height: 150).padding(Spacing.m).background(Palette.surface),
            to: folder.appendingPathComponent("keyboard-25.png")
        )
    }

    @MainActor private func save(_ view: some View, to url: URL) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: url)
    }
}
