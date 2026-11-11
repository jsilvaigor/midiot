import MusicCore

/// A major or minor key.
public struct MusicKey: Hashable, Sendable, Codable {
    /// Pitch class of the tonic: 0 for C through 11 for B.
    public let tonic: Int
    public let isMinor: Bool

    public init(tonic: Int, isMinor: Bool = false) {
        self.tonic = tonic
        self.isMinor = isMinor
    }

    /// Sharps (positive) or flats (negative) in the key signature.
    public var fifths: Int {
        let major = [0, -5, 2, -3, 4, -1, 6, 1, -4, 3, -2, 5]
        return major[isMinor ? (tonic + 3) % 12 : tonic]
    }

    /// Semitones above the tonic of each scale degree. Minor keys use the harmonic form,
    /// the one keyboard methods teach first.
    public var scaleSteps: [Int] {
        isMinor ? [0, 2, 3, 5, 7, 8, 11] : [0, 2, 4, 5, 7, 9, 11]
    }

    /// Letter name of the tonic, such as "B♭".
    public var tonicName: String {
        let sharp = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        let flat = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]
        return (fifths < 0 ? flat : sharp)[tonic]
    }

    public static let c = MusicKey(tonic: 0), g = MusicKey(tonic: 7), d = MusicKey(tonic: 2), a = MusicKey(tonic: 9)
    public static let e = MusicKey(tonic: 4), f = MusicKey(tonic: 5), bFlat = MusicKey(tonic: 10)
    public static let aMinor = MusicKey(tonic: 9, isMinor: true), eMinor = MusicKey(tonic: 4, isMinor: true)
    public static let dMinor = MusicKey(tonic: 2, isMinor: true)

    /// Keys the drills are offered in, easiest first.
    public static let drillKeys: [MusicKey] = [.c, .g, .d, .a, .e, .f, .bFlat, .aMinor, .eMinor, .dMinor]
}

/// A generated exercise (requirements CU-2 to CU-5). Each drill turns into a `Song`, so it is
/// practiced with the same tools as a piece.
public enum Drill: Hashable, Sendable, Codable {
    /// One octave up and down, both hands an octave apart, with standard fingering.
    case scale(MusicKey)
    /// The key's triad broken over one octave, up and down.
    case arpeggio(MusicKey)
    /// Root position, first and second inversion of the key's triad, as block chords.
    case inversions(MusicKey)
    /// I–IV–V–I with the smoothest voice leading, right hand chords over left hand roots.
    case cadence(MusicKey)
    /// Left-hand notes to read from the bass staff. Level 1 stays on the staff, 2 adds ledger
    /// lines below, 3 adds ledger lines above.
    case bassReading(level: Int)
    /// A rhythm tapped on one key against a steady left hand. Higher levels add eighth notes,
    /// dotted notes and syncopation.
    case rhythm(level: Int)
    /// Five-finger patterns for hand independence: 1 parallel motion, 2 contrary motion,
    /// 3 a moving right hand over a held left hand.
    case fiveFinger(MusicKey, pattern: Int)

    /// Stable identifier, used to keep the drill's practice history.
    public var id: String {
        func name(_ key: MusicKey) -> String { "\(key.tonic)\(key.isMinor ? "m" : "")" }
        switch self {
        case let .scale(key): return "scale-\(name(key))"
        case let .arpeggio(key): return "arpeggio-\(name(key))"
        case let .inversions(key): return "inversions-\(name(key))"
        case let .cadence(key): return "cadence-\(name(key))"
        case let .bassReading(level): return "bass-\(level)"
        case let .rhythm(level): return "rhythm-\(level)"
        case let .fiveFinger(key, pattern): return "five-\(name(key))-\(pattern)"
        }
    }

    public var key: MusicKey {
        switch self {
        case let .scale(key), let .arpeggio(key), let .inversions(key), let .cadence(key), let .fiveFinger(key, _): key
        case .bassReading, .rhythm: .c
        }
    }

    /// Every drill on offer, grouped as the path presents them.
    public static var catalog: [Drill] {
        MusicKey.drillKeys.map(Drill.scale)
            + MusicKey.drillKeys.map(Drill.arpeggio)
            + MusicKey.drillKeys.prefix(7).map(Drill.inversions)
            + MusicKey.drillKeys.prefix(7).map(Drill.cadence)
            + (1...3).map { Drill.bassReading(level: $0) }
            + (1...3).map { Drill.rhythm(level: $0) }
            + (1...3).map { Drill.fiveFinger(.c, pattern: $0) }
    }

    /// Builds the exercise. `seed` varies the reading and rhythm drills from day to day;
    /// the same seed always gives the same notes.
    public func song(title: String, seed: UInt64 = 0) -> Song {
        var builder = Builder()
        switch self {
        case let .scale(key): Self.scale(key, into: &builder)
        case let .arpeggio(key): Self.arpeggio(key, into: &builder)
        case let .inversions(key): Self.inversions(key, into: &builder)
        case let .cadence(key): Self.cadence(key, into: &builder)
        case let .bassReading(level): Self.bassReading(level: level, seed: seed, into: &builder)
        case let .rhythm(level): Self.rhythm(level: level, seed: seed, into: &builder)
        case let .fiveFinger(key, pattern): Self.fiveFinger(key, pattern: pattern, into: &builder)
        }
        let length = (builder.end / 4).rounded(.up) * 4
        return Song(
            title: title, notes: builder.notes, tempoMap: TempoMap(bpm: tempo),
            measures: Song.evenMeasures(beatsPerMeasure: 4, covering: length)
        )
    }

    /// Starting tempo; adaptive practice takes it from there.
    public var tempo: Double {
        switch self {
        case .scale, .arpeggio, .fiveFinger: 72
        case .inversions, .cadence: 60
        case .bassReading: 56
        case .rhythm: 80
        }
    }

    // MARK: Generators

    private struct Builder {
        var notes: [Note] = []
        var end = 0.0

        mutating func add(_ pitch: Int, at start: Double, length: Double, hand: Hand, finger: Int? = nil) {
            notes.append(Note(id: 0, pitch: Pitch(midiNumber: pitch), start: start, duration: length, hand: hand, finger: finger))
            end = max(end, start + length)
        }
    }

    /// Tonic of the key in the octave starting at `base`, so every key sits in a similar register.
    private static func tonic(_ key: MusicKey, from base: Int) -> Int {
        base + (key.tonic + 12 - base % 12) % 12
    }

    /// Right- and left-hand fingering for one octave up, by key.
    private static func scaleFingering(_ key: MusicKey) -> (right: [Int], left: [Int]) {
        switch (key.tonic, key.isMinor) {
        case (5, false): ([1, 2, 3, 4, 1, 2, 3, 4], [5, 4, 3, 2, 1, 3, 2, 1]) // F
        case (10, false): ([2, 1, 2, 3, 1, 2, 3, 4], [3, 2, 1, 4, 3, 2, 1, 3]) // B♭
        default: ([1, 2, 3, 1, 2, 3, 4, 5], [5, 4, 3, 2, 1, 3, 2, 1])
        }
    }

    private static func scale(_ key: MusicKey, into builder: inout Builder) {
        let degrees = key.scaleSteps + [12]
        let up = Array(degrees.indices), order = up + up.dropLast().reversed()
        let fingering = scaleFingering(key)
        let right = tonic(key, from: 60), left = tonic(key, from: 48)
        for (step, degree) in order.enumerated() {
            // The last note is held to fill the bar.
            let length = step == order.count - 1 ? 2.0 : 1.0
            builder.add(right + degrees[degree], at: Double(step), length: length, hand: .right, finger: fingering.right[degree])
            builder.add(left + degrees[degree], at: Double(step), length: length, hand: .left, finger: fingering.left[degree])
        }
    }

    private static func arpeggio(_ key: MusicKey, into builder: inout Builder) {
        let third = key.scaleSteps[2]
        let tones = [0, third, 7, 12]
        let order = [0, 1, 2, 3, 2, 1, 0]
        let rightFingers = [1, 2, 3, 5], leftFingers = [5, third == 4 ? 4 : 3, 2, 1]
        let right = tonic(key, from: 60), left = tonic(key, from: 48)
        for (step, tone) in order.enumerated() {
            let length = step == order.count - 1 ? 2.0 : 1.0
            builder.add(right + tones[tone], at: Double(step), length: length, hand: .right, finger: rightFingers[tone])
            builder.add(left + tones[tone], at: Double(step), length: length, hand: .left, finger: leftFingers[tone])
        }
    }

    private static func inversions(_ key: MusicKey, into builder: inout Builder) {
        let third = key.scaleSteps[2]
        let root = tonic(key, from: 60)
        let shapes: [(notes: [Int], fingers: [Int])] = [
            ([0, third, 7], [1, 3, 5]), ([third, 7, 12], [1, 2, 5]), ([7, 12, 12 + third], [1, 3, 5]), ([12, 12 + third, 19], [1, 3, 5]),
        ]
        // Up through the inversions and back, two beats each, right hand; the left holds the root.
        let order = [0, 1, 2, 3, 2, 1, 0]
        for (step, shape) in order.enumerated() {
            let length = step == order.count - 1 ? 4.0 : 2.0
            for (note, finger) in zip(shapes[shape].notes, shapes[shape].fingers) {
                builder.add(root + note, at: Double(step) * 2, length: length, hand: .right, finger: finger)
            }
        }
        for bar in 0..<4 { builder.add(tonic(key, from: 36), at: Double(bar) * 4, length: 4, hand: .left, finger: 5) }
    }

    private static func cadence(_ key: MusicKey, into builder: inout Builder) {
        let steps = key.scaleSteps
        let root = tonic(key, from: 60), bass = tonic(key, from: 48)
        let third = steps[2], sixth = steps[5]
        // Right hand: I (root position), IV (second inversion), V (first inversion), I.
        // The fifth degree's chord uses the raised seventh in minor, as the harmonic scale gives it.
        let chords: [(notes: [Int], fingers: [Int], bass: Int)] = [
            ([0, third, 7], [1, 3, 5], 0),
            ([0, 5, sixth], [1, 3, 5], 5),
            ([-1, 2, 7], [1, 2, 5], -5),
            ([0, third, 7], [1, 3, 5], 0),
        ]
        for round in 0..<2 {
            for (index, chord) in chords.enumerated() {
                let start = Double(round * 4 + index) * 2
                for (note, finger) in zip(chord.notes, chord.fingers) {
                    builder.add(root + note, at: start, length: 2, hand: .right, finger: finger)
                }
                builder.add(bass + chord.bass, at: start, length: 2, hand: .left)
            }
        }
    }

    private static func bassReading(level: Int, seed: UInt64, into builder: inout Builder) {
        // White keys only: reading is the point, not accidentals.
        let ranges: [ClosedRange<Int>] = [43...57, 36...48, 50...64]
        let range = ranges[min(max(level, 1), 3) - 1]
        let pool = range.filter { !Pitch(midiNumber: $0).isBlackKey }
        var random = SeededRandom(seed: seed &+ UInt64(level) &* 7919)
        var previous = pool[pool.count / 2]
        for beat in stride(from: 0.0, to: 32, by: 2) {
            // Mostly steps and small leaps, as real bass lines move; never the same note twice.
            let near = pool.filter { $0 != previous && abs($0 - previous) <= 7 }
            previous = near[Int(random.next() % UInt64(near.count))]
            builder.add(previous, at: beat, length: 2, hand: .left)
        }
    }

    private static func rhythm(level: Int, seed: UInt64, into builder: inout Builder) {
        // One-bar rhythms as note lengths in beats; negative numbers are rests.
        let bank: [[[Double]]] = [
            [[1, 1, 1, 1], [2, 1, 1], [1, 1, 2], [2, 2], [1, 2, 1]],
            [[0.5, 0.5, 1, 1, 1], [1, 0.5, 0.5, 2], [0.5, 0.5, 0.5, 0.5, 2], [1, 1, 0.5, 0.5, 1], [-1, 1, 1, 1]],
            [[1.5, 0.5, 2], [1.5, 0.5, 1, 1], [0.5, 1, 0.5, 2], [-0.5, 0.5, 1, 1.5, 0.5], [0.5, 1, 1, 1, 0.5]],
        ]
        let level = min(max(level, 1), 3)
        // Higher levels still use the easier bars, so the hard ones come as contrast.
        let pool = bank.prefix(level).flatMap { $0 }
        var random = SeededRandom(seed: seed &+ UInt64(level) &* 104_729)
        for bar in 0..<8 {
            let pattern = bar == 7 ? [4.0] : pool[Int(random.next() % UInt64(pool.count))]
            var beat = Double(bar) * 4
            for length in pattern {
                if length > 0 { builder.add(67, at: beat, length: length, hand: .right, finger: 3) }
                beat += abs(length)
            }
            // The left hand keeps the pulse.
            for pulse in 0..<4 { builder.add(48, at: Double(bar * 4 + pulse), length: 1, hand: .left, finger: 3) }
        }
    }

    private static func fiveFinger(_ key: MusicKey, pattern: Int, into builder: inout Builder) {
        let steps = Array(key.scaleSteps.prefix(5))
        let right = tonic(key, from: 60), left = tonic(key, from: 48)
        let line = [0, 1, 2, 3, 4, 3, 2, 1]
        for round in 0..<2 {
            for (index, degree) in line.enumerated() {
                let start = Double(round * 8 + index)
                builder.add(right + steps[degree], at: start, length: 1, hand: .right, finger: degree + 1)
                switch pattern {
                case 2: // Contrary motion: the left hand mirrors, thumbs starting together.
                    builder.add(left + steps[4 - degree], at: start, length: 1, hand: .left, finger: degree + 1)
                case 3: // The left hand holds while the right moves.
                    if index % 4 == 0 { builder.add(left + (index == 0 ? steps[0] : steps[4]), at: start, length: 4, hand: .left, finger: index == 0 ? 5 : 1) }
                default: // Parallel motion.
                    builder.add(left + steps[degree], at: start, length: 1, hand: .left, finger: 5 - degree)
                }
            }
        }
        builder.add(right + steps[0], at: 16, length: 4, hand: .right, finger: 1)
        builder.add(left + steps[0], at: 16, length: 4, hand: .left, finger: 5)
    }
}

/// Small deterministic generator (SplitMix64), so a seed always yields the same drill.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
