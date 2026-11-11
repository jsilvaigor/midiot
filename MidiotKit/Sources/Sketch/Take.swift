import Foundation
import MusicCore

/// One recorded note of a sketch, timed in beats (one beat is a quarter note).
public struct SketchNote: Codable, Hashable, Sendable {
    /// MIDI note number.
    public var pitch: Int
    public var start: Double
    public var duration: Double
    /// Loudness 1...127.
    public var velocity: Int

    public init(pitch: Int, start: Double, duration: Double, velocity: Int = 80) {
        self.pitch = pitch
        self.start = start
        self.duration = duration
        self.velocity = velocity
    }

    public var end: Double { start + duration }
}

/// One pass of playing inside a take. Overdubbing adds a layer (requirement CO-2).
public struct Layer: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var notes: [SketchNote]
    /// General MIDI program the layer was played with; nil is the grand piano.
    public var program: Int?

    public init(id: UUID = UUID(), notes: [SketchNote], program: Int? = nil) {
        self.id = id
        self.notes = notes
        self.program = program
    }
}

/// A note's place in a take: which layer, and where in that layer's `notes`.
public struct NoteRef: Hashable, Sendable {
    public let layer: Int
    public let index: Int

    public init(layer: Int, index: Int) {
        self.layer = layer
        self.index = index
    }
}

/// A kept piece of playing: one or more layers at one tempo.
public struct Take: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    /// 1-based, in the order takes were kept in their cue.
    public var number: Int
    public var createdAt: Date
    /// Quarter notes per minute the beats are measured at.
    public var bpm: Double
    public var layers: [Layer]
    /// The take chosen as the one to use.
    public var isKeeper: Bool

    public init(
        id: UUID = UUID(), number: Int, createdAt: Date = Date(), bpm: Double,
        layers: [Layer], isKeeper: Bool = false
    ) {
        self.id = id
        self.number = number
        self.createdAt = createdAt
        self.bpm = bpm
        self.layers = layers
        self.isKeeper = isKeeper
    }

    /// Beat at which the last note ends.
    public var length: Double { layers.flatMap(\.notes).map(\.end).max() ?? 0 }

    public var seconds: Double { length * 60 / max(bpm, 1) }

    public var noteCount: Int { layers.reduce(0) { $0 + $1.notes.count } }

    /// Lowest and highest MIDI pitch used, or nil for an empty take.
    public var pitchSpan: ClosedRange<Int>? {
        let pitches = layers.flatMap(\.notes).map(\.pitch)
        guard let low = pitches.min(), let high = pitches.max() else { return nil }
        return low...high
    }
}

// MARK: Editing (requirement CO-2)

public extension Take {
    /// Shifts everything so the first note starts at beat 0.
    func trimmed() -> Take {
        guard let first = layers.flatMap(\.notes).map(\.start).min(), first != 0 else { return self }
        return mapNotes { note in
            var note = note
            note.start -= first
            return note
        }
    }

    /// Keeps only what sounds inside `range` (beats), moved to start at beat 0. Notes that
    /// cross an edge are cut at it.
    func trimmed(to range: ClosedRange<Double>) -> Take {
        var copy = self
        for index in copy.layers.indices {
            copy.layers[index].notes = copy.layers[index].notes.compactMap { note in
                let start = max(note.start, range.lowerBound)
                let end = min(note.end, range.upperBound)
                guard end - start > 1e-6 else { return nil }
                return SketchNote(pitch: note.pitch, start: start - range.lowerBound, duration: end - start, velocity: note.velocity)
            }
        }
        return copy
    }

    /// Moves every note start to the nearest multiple of `grid` beats (0.5 is an eighth note)
    /// and rounds lengths to the grid, never shorter than one step.
    func quantized(grid: Double) -> Take {
        guard grid > 0 else { return self }
        return mapNotes { note in
            SketchNote(
                pitch: note.pitch,
                start: max((note.start / grid).rounded() * grid, 0),
                duration: max((note.duration / grid).rounded() * grid, grid),
                velocity: note.velocity
            )
        }
    }

    /// Moves every note by `semitones`, by octaves less if that would leave the MIDI range.
    func transposed(by semitones: Int) -> Take {
        guard let span = pitchSpan else { return self }
        var shift = semitones
        while span.upperBound + shift > 127 { shift -= 12 }
        while span.lowerBound + shift < 0 { shift += 12 }
        return mapNotes { note in
            var note = note
            note.pitch += shift
            return note
        }
    }

    /// Removes the given notes. Layers left empty are removed too, except the last one.
    func deleting(_ refs: Set<NoteRef>) -> Take {
        var copy = self
        for layer in copy.layers.indices {
            copy.layers[layer].notes = copy.layers[layer].notes.enumerated()
                .filter { !refs.contains(NoteRef(layer: layer, index: $0.offset)) }
                .map(\.element)
        }
        let kept = copy.layers.filter { !$0.notes.isEmpty }
        copy.layers = kept.isEmpty ? Array(copy.layers.prefix(1)) : kept
        return copy
    }

    /// Adds a layer recorded over this take.
    func adding(_ layer: Layer) -> Take {
        var copy = self
        copy.layers.append(layer)
        return copy
    }

    private func mapNotes(_ transform: (SketchNote) -> SketchNote) -> Take {
        var copy = self
        for index in copy.layers.indices {
            copy.layers[index].notes = copy.layers[index].notes.map(transform)
        }
        return copy
    }
}

// MARK: As a song

public extension Take {
    /// Pitches below this go to the left hand when a take is shown or written as a score.
    static let handSplit = 60

    /// The take as a song the player and the score writers understand: 4/4 bars, notes below
    /// middle C in the left hand.
    /// - Returns: the song, and for each of its notes the index of the layer it came from.
    func song(title: String) -> (song: Song, layerOfNote: [Int]) {
        var notes: [Note] = []
        // Layers of the notes at each (start, pitch), so each song note can be traced back.
        var origins: [[Double]: [Int]] = [:]
        for (layerIndex, layer) in layers.enumerated() {
            for note in layer.notes where note.duration > 0 {
                notes.append(Note(
                    id: 0, pitch: Pitch(midiNumber: note.pitch), start: max(note.start, 0), duration: note.duration,
                    hand: note.pitch < Self.handSplit ? .left : .right, velocity: note.velocity
                ))
                origins[[max(note.start, 0), Double(note.pitch)], default: []].append(layerIndex)
            }
        }
        let length = notes.map(\.end).max() ?? 0
        let song = Song(
            title: title, notes: notes, tempoMap: TempoMap(bpm: bpm),
            measures: Song.evenMeasures(beatsPerMeasure: 4, covering: max(length, 4))
        )
        let layerOfNote = song.notes.map { note -> Int in
            let key = [note.start, Double(note.pitch.midiNumber)]
            guard var queue = origins[key], !queue.isEmpty else { return 0 }
            let layer = queue.removeFirst()
            origins[key] = queue
            return layer
        }
        return (song, layerOfNote)
    }
}
