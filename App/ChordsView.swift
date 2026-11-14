import DesignSystem
import MusicCore
import Sketch
import SwiftUI

/// A chord cheat sheet: every chord the app knows on any root, with its keys, notes,
/// formula and fingering, and the chords that belong to the root's keys.
struct ChordsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(NoteNamingSetting.storageKey) private var naming = NoteNaming.letters
    @AppStorage("chordSheetRoot") private var root = 0
    @State private var inversion = 0

    /// Two octaves and a third from C3: room for a ninth chord on any root, or an inversion.
    private static let range = KeyboardRange(lowest: Pitch(midiNumber: 48), keyCount: 29)

    private static let groups: [(title: LocalizedStringKey, qualities: [Chord.Quality])] = [
        ("Triads", [.major, .minor, .diminished, .augmented]),
        ("Suspended and open", [.sus2, .sus4, .dominant7sus4, .power]),
        ("Sixths and sevenths", [.sixth, .minorSixth, .dominant7, .major7, .minor7, .minorMajor7, .halfDiminished, .diminished7]),
        ("Added notes and ninths", [.add9, .dominant9, .major9, .minor9]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                controls
                inKey
                ForEach(Array(Self.groups.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(group.title).font(.serif(26)).foregroundStyle(Palette.textPrimary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)], spacing: 12) {
                            ForEach(group.qualities, id: \.self) { quality in
                                card(Chord(root: root, quality: quality))
                            }
                        }
                    }
                }
                reading
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(FilamentBackground())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Chords").font(.display).foregroundStyle(Palette.textPrimary)
            (Platform.isPad ? Text("Pick a root. Every card shows the keys to press; tap one to hear it.")
                : Text("Pick a root. Every card shows the keys to press; click one to hear it."))
                .font(.bodyText).foregroundStyle(Palette.textSecondary)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            FlowLayout(spacing: 6) {
                ForEach(0..<12, id: \.self) { pitchClass in
                    let isOn = pitchClass == root
                    Button {
                        root = pitchClass
                    } label: {
                        Text(verbatim: rootName(pitchClass))
                            .font(.sans(14, weight: isOn ? .semibold : .regular))
                            .foregroundStyle(isOn ? Palette.accentInk : Palette.textPrimary)
                            .frame(minWidth: 26).padding(.horizontal, 10).frame(height: Platform.touch(40))
                            .background(isOn ? Palette.accent : Palette.surfaceRaised.opacity(0.7), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(isOn ? .clear : Palette.hairline))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            SegmentedControl(selection: $inversion, options: [
                .init(0, "Root position"), .init(1, "1st inversion"), .init(2, "2nd inversion"), .init(3, "3rd inversion"),
            ])
        }
    }

    // MARK: Chords of the key

    private var inKey: some View {
        VStack(alignment: .leading, spacing: 14) {
            keyRow(SketchKey(tonic: root, isMinor: false), numerals: ["I", "ii", "iii", "IV", "V", "vi", "vii°"])
            keyRow(SketchKey(tonic: root, isMinor: true), numerals: ["i", "ii°", "III", "iv", "V", "VI", "VII"])
            Text("Capital numerals are major chords, small ones minor, ° diminished. I, IV and V carry most songs.")
                .font(.sans(12)).foregroundStyle(Palette.textTertiary)
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface.opacity(0.8), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Palette.hairline))
    }

    private func keyRow(_ key: SketchKey, numerals: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if key.isMinor { Text("Chords in \(rootName(key.tonic, fifths: key.fifths)) minor") }
                else { Text("Chords in \(rootName(key.tonic, fifths: key.fifths)) major") }
            }
            .capsLabel()
            FlowLayout(spacing: 8) {
                ForEach(Array(zip(numerals, key.diatonicChords)), id: \.0) { numeral, chord in
                    Button {
                        model.audition(pitches(of: chord, inversion: 0))
                    } label: {
                        VStack(spacing: 2) {
                            Text(verbatim: numeral).font(.mono(11)).foregroundStyle(Palette.textTertiary)
                            Text(verbatim: symbol(chord, fifths: key.fifths)).font(.serif(20)).foregroundStyle(Palette.textPrimary)
                        }
                        .frame(minWidth: 56).padding(.horizontal, 8).frame(height: 56)
                        .background(Palette.surfaceRaised.opacity(0.7), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: One chord

    private func card(_ chord: Chord) -> some View {
        let count = chord.quality.intervals.count
        // An inversion the chord has too few notes for falls back to the highest it has.
        let turn = min(inversion, count - 1)
        let pitches = pitches(of: chord, inversion: turn)
        let names = Array(chord.spelledTones.dropFirst(turn) + chord.spelledTones.prefix(turn))
        let formula = Array(chord.quality.formula.dropFirst(turn) + chord.quality.formula.prefix(turn))
        return Button {
            model.audition(pitches)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: symbol(chord)).font(.serif(30)).foregroundStyle(Palette.accent)
                    Spacer()
                    Text(Self.name(chord.quality)).font(.sans(12)).foregroundStyle(Palette.textSecondary)
                }
                KeyboardView(
                    range: Self.range,
                    highlights: Dictionary(uniqueKeysWithValues: pitches.map { ($0, Palette.handRight) }),
                    naming: naming
                )
                .frame(height: 76)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                    GridRow {
                        Text("Notes").foregroundStyle(Palette.textTertiary)
                        Text(verbatim: names.map(spelled).joined(separator: "  ")).foregroundStyle(Palette.textPrimary)
                    }
                    GridRow {
                        Text("Formula").foregroundStyle(Palette.textTertiary)
                        Text(verbatim: formula.joined(separator: "  ")).font(.mono(12)).foregroundStyle(Palette.textPrimary)
                    }
                    GridRow {
                        Text("Fingers").foregroundStyle(Palette.textTertiary)
                        Text(verbatim: Self.fingering(count: count, inversion: turn).map(String.init).joined(separator: "  "))
                            .font(.mono(12)).foregroundStyle(Palette.textPrimary)
                    }
                }
                .font(.sans(12))
                Text(Self.character(chord.quality)).font(.sans(12)).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface.opacity(0.8), in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous).strokeBorder(Palette.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var reading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reading the cards").capsLabel()
            Text("Formula counts steps of the major scale from the root: ♭ lowers a step by a semitone, ♯ raises it. Fingers are for the right hand, thumb = 1; the left hand mirrors them, little finger on the lowest note.")
            Text("An inversion keeps the same notes and puts another one at the bottom. Inversions let the hand stay in one place while the chords change.")
        }
        .font(.sans(13)).foregroundStyle(Palette.textSecondary)
        .frame(maxWidth: 720, alignment: .leading)
    }

    // MARK: Names and keys

    /// The chord's keys on the card's keyboard, moved down an octave if an inversion runs off it.
    private func pitches(of chord: Chord, inversion: Int) -> [Pitch] {
        let tones = chord.tones(from: 48 + chord.root, inversion: inversion)
        guard let top = tones.last, top > Self.range.highest else { return tones }
        return tones.map { Pitch(midiNumber: $0.midiNumber - 12) }
    }

    /// "C" or "Dó", following the note-naming setting. Chord symbols themselves stay in letters.
    private func rootName(_ pitchClass: Int, fifths: Int? = nil) -> String {
        spelled(Chord.name(ofPitchClass: pitchClass, fifths: fifths))
    }

    private func symbol(_ chord: Chord, fifths: Int? = nil) -> String {
        chord.name(fifths: fifths)
    }

    /// A spelled note such as "E♭" in the chosen naming: "Mi♭".
    private func spelled(_ name: String) -> String {
        guard naming == .solfege, let letter = name.first,
              let index = ["C", "D", "E", "F", "G", "A", "B"].firstIndex(of: String(letter)) else { return name }
        return ["Dó", "Ré", "Mi", "Fá", "Sol", "Lá", "Si"][index] + name.dropFirst()
    }

    /// Right-hand fingers, lowest note first.
    private static func fingering(count: Int, inversion: Int) -> [Int] {
        switch (count, inversion) {
        case (2, _): [1, 5]
        case (3, 1): [1, 2, 5]
        case (3, _): [1, 3, 5]
        case (4, _): [1, 2, 3, 5]
        default: [1, 2, 3, 4, 5]
        }
    }

    private static func name(_ quality: Chord.Quality) -> LocalizedStringKey {
        switch quality {
        case .major: "Major"
        case .minor: "Minor"
        case .diminished: "Diminished"
        case .augmented: "Augmented"
        case .sus2: "Suspended second"
        case .sus4: "Suspended fourth"
        case .power: "Fifth (no third)"
        case .sixth: "Major sixth"
        case .minorSixth: "Minor sixth"
        case .dominant7: "Dominant seventh"
        case .major7: "Major seventh"
        case .minor7: "Minor seventh"
        case .minorMajor7: "Minor, major seventh"
        case .halfDiminished: "Half-diminished"
        case .diminished7: "Diminished seventh"
        case .dominant7sus4: "Seventh, suspended fourth"
        case .add9: "Added ninth"
        case .dominant9: "Dominant ninth"
        case .major9: "Major ninth"
        case .minor9: "Minor ninth"
        }
    }

    /// What the chord sounds like and where it is used.
    private static func character(_ quality: Chord.Quality) -> LocalizedStringKey {
        switch quality {
        case .major: "Bright and settled. The home chord of a major key."
        case .minor: "Darker, inward. The home chord of a minor key."
        case .diminished: "Tense and narrow; wants to move on, usually up a semitone."
        case .augmented: "Strange and unstable, like a question left open."
        case .sus2: "Open and airy; the third is replaced by the second."
        case .sus4: "Held back; the fourth wants to fall to the third."
        case .power: "Neither major nor minor. Strong in the low register."
        case .sixth: "Major with a sweet, old-fashioned ending."
        case .minorSixth: "Minor with a bittersweet edge."
        case .dominant7: "Pulls strongly home: play it on V before I."
        case .major7: "Soft and dreamy; a major chord that floats."
        case .minor7: "Smooth and mellow; the everyday minor of jazz and pop."
        case .minorMajor7: "Minor with a sharp sting; mystery and suspense."
        case .halfDiminished: "Uneasy; the ii chord of a minor key, leading to V."
        case .diminished7: "Pure tension, the classic melodrama chord. Every note is three semitones apart."
        case .dominant7sus4: "A dominant that waits before it pulls home."
        case .add9: "Major with a shimmer on top."
        case .dominant9: "A richer dominant; funk and blues."
        case .major9: "Lush and wide; calm, open scenes."
        case .minor9: "Deep and nocturnal."
        }
    }
}
