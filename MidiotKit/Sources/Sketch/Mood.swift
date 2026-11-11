/// A scale offered as a starting point by a mood palette.
public enum SketchScale: String, CaseIterable, Sendable {
    case major, aeolian, harmonicMinor, dorian, phrygian, lydian, mixolydian
    case majorPentatonic, wholeTone, octatonic, chromatic

    /// Semitones above the tonic, one octave.
    public var intervals: [Int] {
        switch self {
        case .major: [0, 2, 4, 5, 7, 9, 11]
        case .aeolian: [0, 2, 3, 5, 7, 8, 10]
        case .harmonicMinor: [0, 2, 3, 5, 7, 8, 11]
        case .dorian: [0, 2, 3, 5, 7, 9, 10]
        case .phrygian: [0, 1, 3, 5, 7, 8, 10]
        case .lydian: [0, 2, 4, 6, 7, 9, 11]
        case .mixolydian: [0, 2, 4, 5, 7, 9, 10]
        case .majorPentatonic: [0, 2, 4, 7, 9]
        case .wholeTone: [0, 2, 4, 6, 8, 10]
        case .octatonic: [0, 1, 3, 4, 6, 7, 9, 10]
        case .chromatic: Array(0..<12)
        }
    }
}

/// A sound the Sketchpad can play (requirement SN-2).
public struct SketchSound: Hashable, Sendable, Identifiable {
    public enum Group: String, CaseIterable, Sendable {
        case piano, orchestra, keys, pads, percussion
    }

    /// General MIDI program number, 0-based; nil is the sampled grand piano.
    public let program: Int?
    public let group: Group

    public var id: Int { program ?? -1 }

    public static let grandPiano = SketchSound(program: nil, group: .piano)

    /// Every sound offered, grouped as in the sound menu.
    public static let catalog: [SketchSound] = [grandPiano]
        + [48, 44, 45, 42, 43, 46, 73, 70, 60, 52].map { SketchSound(program: $0, group: .orchestra) }
        + [4, 6, 8, 19, 16, 21].map { SketchSound(program: $0, group: .keys) }
        + [88, 89, 91, 94, 95].map { SketchSound(program: $0, group: .pads) }
        + [47, 13, 11, 14, 116, 119, 122].map { SketchSound(program: $0, group: .percussion) }

    public static func sound(program: Int?) -> SketchSound {
        catalog.first { $0.program == program } ?? SketchSound(program: program, group: .orchestra)
    }
}

/// Starting points for a dramatic intent: scales, chord moves, tempo and sounds (requirement CO-4).
public struct MoodPalette: Hashable, Sendable, Identifiable {
    public enum Mood: String, CaseIterable, Codable, Sendable {
        case tension, melancholy, comic, pastoral, mystery, ritual
    }

    public let id: Mood
    public let scales: [SketchScale]
    /// Chord moves in roman numerals, the same in every language.
    public let moves: String
    /// Quarter notes per minute.
    public let tempo: ClosedRange<Int>
    public let sounds: [SketchSound]

    public static let all: [MoodPalette] = [
        MoodPalette(id: .tension, scales: [.phrygian, .octatonic], moves: "i – ♭II – i", tempo: 72...96,
                    sounds: [44, 43, 47].map(SketchSound.sound)),
        MoodPalette(id: .melancholy, scales: [.aeolian, .harmonicMinor], moves: "i – VI – III – VII", tempo: 56...70,
                    sounds: [nil, 42, 89].map(SketchSound.sound)),
        MoodPalette(id: .comic, scales: [.major, .chromatic], moves: "I – vi – ii – V", tempo: 120...150,
                    sounds: [45, 70, 13].map(SketchSound.sound)),
        MoodPalette(id: .pastoral, scales: [.majorPentatonic, .lydian], moves: "I – IV/I – I", tempo: 66...84,
                    sounds: [73, 46, 48].map(SketchSound.sound)),
        MoodPalette(id: .mystery, scales: [.dorian, .wholeTone], moves: "i9 – IV13 – i9", tempo: 56...66,
                    sounds: [88, 8, 43].map(SketchSound.sound)),
        MoodPalette(id: .ritual, scales: [.mixolydian], moves: "I – ♭VII – I", tempo: 60...80,
                    sounds: [91, 116, 14].map(SketchSound.sound)),
    ]

    public static func palette(for mood: Mood) -> MoodPalette {
        all.first { $0.id == mood } ?? all[0]
    }
}
