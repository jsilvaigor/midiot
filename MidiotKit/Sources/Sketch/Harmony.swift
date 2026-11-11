import MusicCore

/// A major or minor key.
public struct SketchKey: Hashable, Sendable {
    /// Pitch class of the tonic, 0 for C through 11 for B.
    public let tonic: Int
    public let isMinor: Bool

    public init(tonic: Int, isMinor: Bool) {
        self.tonic = ((tonic % 12) + 12) % 12
        self.isMinor = isMinor
    }

    /// Key signature: sharps positive, flats negative. F♯ major is written with six sharps.
    public var fifths: Int {
        let major = isMinor ? (tonic + 3) % 12 : tonic
        let steps = (major * 7) % 12
        return steps > 6 ? steps - 12 : steps
    }

    /// "D" or "B♭", spelled to suit the key signature.
    public var tonicName: String { Chord.name(ofPitchClass: tonic, fifths: fifths) }
}

/// A chord recognized from the keys held (requirement CO-3).
public struct Chord: Hashable, Sendable {
    public enum Quality: String, CaseIterable, Sendable {
        case major, minor, diminished, augmented, sus2, sus4, power
        case sixth, minorSixth, dominant7, major7, minor7, minorMajor7, halfDiminished, diminished7, dominant7sus4
        case add9, dominant9, major9, minor9

        /// Semitones above the root.
        public var intervals: [Int] {
            switch self {
            case .major: [0, 4, 7]
            case .minor: [0, 3, 7]
            case .diminished: [0, 3, 6]
            case .augmented: [0, 4, 8]
            case .sus2: [0, 2, 7]
            case .sus4: [0, 5, 7]
            case .power: [0, 7]
            case .sixth: [0, 4, 7, 9]
            case .minorSixth: [0, 3, 7, 9]
            case .dominant7: [0, 4, 7, 10]
            case .major7: [0, 4, 7, 11]
            case .minor7: [0, 3, 7, 10]
            case .minorMajor7: [0, 3, 7, 11]
            case .halfDiminished: [0, 3, 6, 10]
            case .diminished7: [0, 3, 6, 9]
            case .dominant7sus4: [0, 5, 7, 10]
            case .add9: [0, 2, 4, 7]
            case .dominant9: [0, 2, 4, 7, 10]
            case .major9: [0, 2, 4, 7, 11]
            case .minor9: [0, 2, 3, 7, 10]
            }
        }

        /// What follows the root in a chord symbol: "m7" in "Dm7".
        public var suffix: String {
            switch self {
            case .major: ""
            case .minor: "m"
            case .diminished: "dim"
            case .augmented: "aug"
            case .sus2: "sus2"
            case .sus4: "sus4"
            case .power: "5"
            case .sixth: "6"
            case .minorSixth: "m6"
            case .dominant7: "7"
            case .major7: "maj7"
            case .minor7: "m7"
            case .minorMajor7: "m(maj7)"
            case .halfDiminished: "m7♭5"
            case .diminished7: "dim7"
            case .dominant7sus4: "7sus4"
            case .add9: "add9"
            case .dominant9: "9"
            case .major9: "maj9"
            case .minor9: "m9"
            }
        }

        /// The MusicXML `kind` value for a chord symbol.
        public var musicXMLKind: String {
            switch self {
            case .major, .add9: "major"
            case .minor: "minor"
            case .diminished: "diminished"
            case .augmented: "augmented"
            case .sus2: "suspended-second"
            case .sus4, .dominant7sus4: "suspended-fourth"
            case .power: "power"
            case .sixth: "major-sixth"
            case .minorSixth: "minor-sixth"
            case .dominant7: "dominant"
            case .major7: "major-seventh"
            case .minor7: "minor-seventh"
            case .minorMajor7: "major-minor"
            case .halfDiminished: "half-diminished"
            case .diminished7: "diminished-seventh"
            case .dominant9: "dominant-ninth"
            case .major9: "major-ninth"
            case .minor9: "minor-ninth"
            }
        }

        var hasMinorThird: Bool { intervals.contains(3) }

        /// Scale degree of each tone, parallel to `intervals`: 1, 3, 5, 7, 9.
        public var degrees: [Int] {
            intervals.map { interval in
                switch interval {
                case 0: 1
                case 2: self == .sus2 ? 2 : 9
                case 3, 4: 3
                case 5: 4
                case 6, 7, 8: 5
                case 9: self == .diminished7 ? 7 : 6
                default: 7
                }
            }
        }

        /// The chord as altered degrees of the major scale: "1 ♭3 5 ♭7".
        public var formula: [String] {
            let major = [1: 0, 2: 2, 3: 4, 4: 5, 5: 7, 6: 9, 7: 11, 9: 2]
            return zip(intervals, degrees).map { interval, degree in
                let alter = interval - (major[degree] ?? 0)
                return (alter == -2 ? "𝄫" : alter == -1 ? "♭" : alter == 1 ? "♯" : "") + String(degree)
            }
        }
    }

    /// Pitch class of the root.
    public let root: Int
    public let quality: Quality
    /// Pitch class of the lowest note when it is not the root.
    public let bass: Int?

    public init(root: Int, quality: Quality, bass: Int? = nil) {
        let rootClass = ((root % 12) + 12) % 12
        let bassClass = bass.map { (($0 % 12) + 12) % 12 }
        self.root = rootClass
        self.quality = quality
        self.bass = bassClass == rootClass ? nil : bassClass
    }

    /// The chord symbol: "Dm9", "B♭maj7", "C/E".
    /// - Parameter fifths: key signature that decides between sharps and flats; nil uses the
    ///   most common spelling of each black key.
    public func name(fifths: Int? = nil) -> String {
        Self.name(ofPitchClass: root, fifths: fifths) + quality.suffix
            + (bass.map { "/" + Self.name(ofPitchClass: $0, fifths: fifths) } ?? "")
    }

    /// Chord symbols are written with letters in every language, so this ignores the note-naming setting.
    public static func name(ofPitchClass pitchClass: Int, fifths: Int? = nil) -> String {
        let sharps = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        let flats = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]
        let common = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
        let index = ((pitchClass % 12) + 12) % 12
        guard let fifths, fifths != 0 else { return common[index] }
        return (fifths > 0 ? sharps : flats)[index]
    }

    /// The chord as keys to play: the root low, the chord around middle C.
    public var voicing: [Pitch] {
        let placed = voicing(in: .fortyNineKeys)
        return (placed.bass.map { [$0] } ?? []) + placed.tones
    }

    /// The chord placed on a keyboard: the right hand's keys in close position as near the
    /// middle of the keyboard as they fit, and a bass note for the left hand when there is
    /// room below them.
    public func voicing(in range: KeyboardRange) -> (bass: Pitch?, tones: [Pitch]) {
        let top = quality.intervals.max() ?? 0
        let middle = Double(range.lowest.midiNumber + range.highest.midiNumber) / 2
        let roots = range.pitches.map(\.midiNumber).filter { ((($0 - root) % 12) + 12) % 12 == 0 && $0 + top <= range.highest.midiNumber }
        // On a keyboard too short for the chord, start from its lowest root anyway.
        let base = roots.min { abs(Double($0) + Double(top) / 2 - middle) < abs(Double($1) + Double(top) / 2 - middle) }
            ?? (range.lowest.midiNumber + ((root - range.lowest.midiNumber) % 12 + 12) % 12)
        let tones = quality.intervals.map { Pitch(midiNumber: base + $0) }
        // The nearest key below the chord with the bass note's name.
        let bassClass = bass ?? root
        let below = base - (((base - bassClass) % 12 + 12) % 12 == 0 ? 12 : ((base - bassClass) % 12 + 12) % 12)
        return (below >= range.lowest.midiNumber ? Pitch(midiNumber: below) : nil, tones)
    }

    /// The chord's tones from `base` (the root's MIDI number) upward, with the lowest
    /// `inversion` tones moved up an octave: 1 puts the third in the bass, and so on.
    public func tones(from base: Int, inversion: Int = 0) -> [Pitch] {
        let intervals = quality.intervals
        let turns = min(max(inversion, 0), intervals.count - 1)
        return (intervals.dropFirst(turns) + intervals.prefix(turns).map { $0 + 12 }).map { Pitch(midiNumber: base + $0) }
    }

    /// The chord's notes spelled as theory writes them, each on its own letter: C dim7 is
    /// C, E♭, G♭, B𝄫. The root is spelled the common way.
    public var spelledTones: [String] {
        let letters = ["C", "D", "E", "F", "G", "A", "B"]
        let naturals = [0, 2, 4, 5, 7, 9, 11]
        let rootName = Self.name(ofPitchClass: root)
        guard let rootLetter = letters.firstIndex(of: String(rootName.prefix(1))) else { return [] }
        return zip(quality.intervals, quality.degrees).map { interval, degree in
            let letter = (rootLetter + degree - 1) % 7
            // Distance from the letter's natural pitch to the sounding one, as −2…2.
            var alter = (root + interval - naturals[letter]) % 12
            if alter > 6 { alter -= 12 }
            if alter < -6 { alter += 12 }
            let sign = switch alter {
            case 1: "♯"
            case 2: "𝄪"
            case -1: "♭"
            case -2: "𝄫"
            default: ""
            }
            return letters[letter] + sign
        }
    }

    /// Names the chord formed by the given keys, or nil when they form none the app knows.
    /// One stray note is tolerated, and the fifth may be left out of four-note chords.
    public static func detect(_ pitches: some Collection<Pitch>) -> Chord? {
        guard let lowest = pitches.min() else { return nil }
        let classes = Set(pitches.map(\.pitchClass))
        guard classes.count >= 2 else { return nil }
        let bass = lowest.pitchClass

        var best: (chord: Chord, score: Double)?
        for root in classes.sorted() {
            let played = Set(classes.map { ($0 - root + 12) % 12 })
            for quality in Quality.allCases {
                let template = Set(quality.intervals)
                if quality == .power, classes.count != 2 { continue }
                if quality != .power, classes.count < 3 { continue }
                let missing = template.subtracting(played)
                let extra = played.subtracting(template)
                // Only the fifth of a larger chord may be absent.
                guard missing.isEmpty || (missing == [7] && template.count >= 4) else { continue }
                guard extra.count <= (template.count >= 3 ? 1 : 0) else { continue }
                var score = Double(template.intersection(played).count) * 2
                score -= Double(extra.count) * 2.5 + Double(missing.count) * 0.5
                if root == bass { score += 1.2 }
                // Among equals, the plainer chord is the likelier reading.
                score -= Double(template.count) * 0.01
                if score > (best?.score ?? -.infinity) {
                    best = (Chord(root: root, quality: quality, bass: bass), score)
                }
            }
        }
        return best?.chord
    }
}

public extension SketchKey {
    /// The key that best fits how long each pitch class sounded, or nil when there is too
    /// little to go on. Uses the Krumhansl–Kessler key profiles.
    /// - Parameter weights: twelve values, C through B; any unit.
    static func detect(weights: [Double]) -> SketchKey? {
        guard weights.count == 12, weights.count(where: { $0 > 0 }) >= 4 else { return nil }
        let major = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
        let minor = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

        func correlation(_ profile: [Double], tonic: Int) -> Double {
            let rotated = (0..<12).map { profile[($0 - tonic + 12) % 12] }
            let meanA = weights.reduce(0, +) / 12, meanB = rotated.reduce(0, +) / 12
            var top = 0.0, a = 0.0, b = 0.0
            for index in 0..<12 {
                top += (weights[index] - meanA) * (rotated[index] - meanB)
                a += (weights[index] - meanA) * (weights[index] - meanA)
                b += (rotated[index] - meanB) * (rotated[index] - meanB)
            }
            return a > 0 && b > 0 ? top / (a * b).squareRoot() : 0
        }

        var best: (key: SketchKey, score: Double)?
        for tonic in 0..<12 {
            for (profile, isMinor) in [(major, false), (minor, true)] {
                let score = correlation(profile, tonic: tonic)
                if score > (best?.score ?? 0.5) { best = (SketchKey(tonic: tonic, isMinor: isMinor), score) }
            }
        }
        return best?.key
    }

    /// The key of a stretch of notes, weighting each pitch by how long it sounded.
    static func detect(notes: some Sequence<(pitch: Int, duration: Double)>) -> SketchKey? {
        var weights = Array(repeating: 0.0, count: 12)
        for note in notes { weights[((note.pitch % 12) + 12) % 12] += max(note.duration, 0.05) }
        return detect(weights: weights)
    }

    /// The chord built on each step of the scale, with the major V in minor keys.
    var diatonicChords: [Chord] {
        let steps: [(Int, Chord.Quality)] = isMinor
            ? [(0, .minor), (2, .diminished), (3, .major), (5, .minor), (7, .major), (8, .major), (10, .major)]
            : [(0, .major), (2, .minor), (4, .minor), (5, .major), (7, .major), (9, .minor), (11, .diminished)]
        return steps.map { Chord(root: tonic + $0.0, quality: $0.1) }
    }
}

/// A chord worth trying after the current one, and what it does (requirement CO-3).
public struct ChordSuggestion: Hashable, Sendable {
    public enum Effect: String, Sendable {
        case home, leadsOn, gentle, opens, tension, darker, brighter, unsettled, surprise
    }

    public let chord: Chord
    public let effect: Effect

    /// Three chords that commonly follow `chord` in `key`. Without a key, the chord is taken
    /// as the home chord of its own key.
    public static func next(after chord: Chord, in key: SketchKey?) -> [ChordSuggestion] {
        let key = key ?? SketchKey(tonic: chord.root, isMinor: chord.quality.hasMinorThird)
        let diatonic = key.diatonicChords
        // Scale step (0-based) the chord is built on; chords from outside the key lead home.
        let step = diatonic.firstIndex { $0.root == chord.root }

        let moves: [[Int]] = key.isMinor
            ? [[3, 5, 4], [4, 0, 2], [5, 6, 3], [4, 0, 6], [0, 5, 3], [6, 3, 4], [2, 0, 5]]
            : [[3, 4, 5], [4, 3, 5], [5, 3, 1], [4, 0, 1], [0, 5, 3], [3, 1, 4], [0, 2, 5]]
        let effects: [Effect] = key.isMinor
            ? [.home, .unsettled, .brighter, .darker, .tension, .brighter, .opens]
            : [.home, .leadsOn, .gentle, .opens, .tension, .darker, .unsettled]

        let targets = step.map { moves[$0] } ?? [0, 3, 4]
        return targets.map { target in
            var effect = effects[target]
            // V moving to VI instead of home is the classic surprise.
            if step == 4, target == 5 { effect = .surprise }
            var next = diatonic[target]
            // The dominant is more itself with its seventh.
            if target == 4 { next = Chord(root: next.root, quality: .dominant7) }
            return ChordSuggestion(chord: next, effect: effect)
        }
    }
}
