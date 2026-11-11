import MusicCore

/// How the notes of a MIDI file are divided between the hands (requirement SS-1).
public enum HandAssignment: Hashable, Sendable {
    /// Use two tracks when the file has exactly two with notes, otherwise split at middle C.
    case automatic
    /// Indexes into `MIDIFile.tracks`; notes on other tracks are left out.
    case tracks(right: Int, left: Int)
    /// Notes at or above the pitch go to the right hand, on all tracks.
    case split(at: Pitch)
}

public extension Song {
    /// Builds a practice song from a MIDI file. Drum-channel notes are dropped.
    init(midiFile file: MIDIFile, title: String, hands: HandAssignment = .automatic) {
        let ticksPerBeat = Double(file.ticksPerQuarter)
        let pitched = file.tracks.map { $0.notes.filter { $0.channel != 9 } }
        let withNotes = pitched.indices.filter { !pitched[$0].isEmpty }

        var assignment = hands
        if assignment == .automatic {
            if withNotes.count == 2 {
                // The track that sits higher on average is the right hand.
                let mean = withNotes.map { index in
                    Double(pitched[index].reduce(0) { $0 + $1.pitch }) / Double(pitched[index].count)
                }
                assignment = mean[0] >= mean[1]
                    ? .tracks(right: withNotes[0], left: withNotes[1])
                    : .tracks(right: withNotes[1], left: withNotes[0])
            } else {
                assignment = .split(at: .middleC)
            }
        }

        var notes: [Note] = []
        func add(_ source: [MIDIFile.Note], hand: (MIDIFile.Note) -> Hand) {
            for note in source {
                notes.append(Note(
                    id: 0, pitch: Pitch(midiNumber: note.pitch),
                    start: Double(note.startTick) / ticksPerBeat,
                    duration: Double(note.durationTicks) / ticksPerBeat,
                    hand: hand(note), velocity: note.velocity
                ))
            }
        }
        switch assignment {
        case let .tracks(right, left):
            if pitched.indices.contains(right) { add(pitched[right]) { _ in .right } }
            if pitched.indices.contains(left), left != right { add(pitched[left]) { _ in .left } }
        case let .split(at: splitPitch):
            add(pitched.flatMap { $0 }) { $0.pitch >= splitPitch.midiNumber ? .right : .left }
        case .automatic:
            break // resolved above
        }

        let tempoMap = TempoMap(changes: file.tempos.map {
            TempoMap.Change(beat: Double($0.tick) / ticksPerBeat, bpm: $0.bpm)
        })
        let length = notes.map(\.end).max() ?? 0
        self.init(
            title: title, notes: notes, tempoMap: tempoMap,
            measures: Self.measures(for: file, covering: length)
        )
    }

    /// Lays out bars from the file's time signatures, assuming 4/4 where none is given.
    private static func measures(for file: MIDIFile, covering length: Double) -> [Measure] {
        let ticksPerBeat = Double(file.ticksPerQuarter)
        var changes = file.timeSignatures
            .filter { $0.numerator > 0 && $0.denominator > 0 }
            .map { (beat: Double($0.tick) / ticksPerBeat, length: Double($0.numerator) * 4 / Double($0.denominator)) }
        if changes.first?.beat != 0 { changes.insert((0, 4), at: 0) }

        var measures: [Measure] = []
        var start = 0.0
        var index = 0
        while start < length {
            while index + 1 < changes.count, changes[index + 1].beat <= start + 1e-9 { index += 1 }
            let barLength = changes[index].length
            measures.append(Measure(number: measures.count + 1, start: start, length: barLength))
            start += barLength
        }
        return measures
    }
}
