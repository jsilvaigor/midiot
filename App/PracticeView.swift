import DesignSystem
import MusicCore
import SwiftUI

/// Practice screen. Until songs arrive in phase 3 it shows the live keyboard only.
struct PracticeView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(NoteNamingSetting.storageKey) private var naming = NoteNaming.letters

    /// White keys wider than this look toy-like on a 25-key keyboard in a wide window.
    private let maxWhiteKeyWidth: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            EmptyState(
                systemImage: "pianokeys",
                title: "Nothing to practice yet",
                message: "Choose a song from the Library to start practicing."
            )
            keyboard
        }
    }

    private var keyboard: some View {
        let whiteKeys = model.range.pitches.count { !$0.isBlackKey }
        return KeyboardView(
            range: model.range,
            highlights: Dictionary(uniqueKeysWithValues: model.pressed.map { ($0, Palette.handRight) }),
            naming: naming,
            onPress: model.mouseDown(on:),
            onRelease: model.mouseUp(on:)
        )
        .frame(maxWidth: CGFloat(whiteKeys) * maxWhiteKeyWidth)
        .frame(height: 150)
        .padding(.horizontal, Spacing.m)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.m)
        .frame(maxWidth: .infinity)
        .background(Palette.surface)
        // The filament: the amber line where falling notes will meet the keys.
        .overlay(alignment: .top) {
            Palette.accent.frame(height: 2).filamentGlow()
        }
    }
}

enum NoteNamingSetting {
    static let storageKey = "noteNaming"
}
