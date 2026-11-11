import MusicCore

/// Writes a readable draft score for a song that has no notation of its own, such as a MIDI
/// import. Rhythms are rounded to sixteenth notes and each hand is written as one line of
/// notes and chords, so the result is for reading along, not for print.
public enum MusicXMLWriter {
    /// Sixteenth notes per beat: the rhythmic grid of the draft.
    private static let grid = 4

    /// - Parameters:
    ///   - fifths: key signature, sharps positive and flats negative. Notes are spelled to suit it.
    ///   - sharpened: a pitch class always written as a sharp, for the raised seventh of a
    ///     minor key (C♯ in D minor, even though the key signature has a flat).
    public static func draft(from song: Song, fifths: Int = 0, sharpened: Int? = nil) -> String {
        write(song, fifths: fifths, sharpened: sharpened, hands: [.right, .left], chords: [:])
    }

    /// A chord symbol printed above the staff of a lead sheet.
    public struct ChordSymbol: Hashable, Sendable {
        /// Root letter, "A" to "G", and its alteration: 1 sharp, -1 flat.
        public let step: String
        public let alter: Int
        /// MusicXML chord kind, such as "minor-seventh".
        public let kind: String
        /// What follows the root when printed: "m7".
        public let suffix: String

        public init(step: String, alter: Int, kind: String, suffix: String) {
            self.step = step
            self.alter = alter
            self.kind = kind
            self.suffix = suffix
        }

        /// - Parameter root: the root as written, "B♭" or "F♯".
        public init(root: String, kind: String, suffix: String) {
            self.init(
                step: String(root.prefix(1)), alter: root.contains("♯") ? 1 : (root.contains("♭") ? -1 : 0),
                kind: kind, suffix: suffix
            )
        }
    }

    /// Writes a lead sheet: the top line of the song on one staff, with a chord symbol over
    /// each bar that has one (requirement CO-7).
    /// - Parameter chords: chord per bar number.
    public static func leadSheet(from song: Song, chords: [Int: ChordSymbol], fifths: Int = 0) -> String {
        write(song.melodyLine(), fifths: fifths, sharpened: nil, hands: [.right], chords: chords)
    }

    private static func write(
        _ song: Song, fifths: Int, sharpened: Int?, hands: [Hand], chords: [Int: ChordSymbol]
    ) -> String {
        let spelling = Spelling(fifths: fifths, sharpened: sharpened)
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="4.0"><work><work-title>\(escape(song.title))</work-title></work>
        <part-list><score-part id="P1"><part-name></part-name></score-part></part-list><part id="P1">

        """

        // Chords held over the barline, per staff: pitches and sixteenths still to sound.
        var carried: [Hand: (pitches: [Pitch], remaining: Int)] = [:]
        var previousLength = 0

        for measure in song.measures {
            let start = quantize(measure.start)
            let length = max(quantize(measure.length), 1)
            xml += "<measure number=\"\(measure.number)\">"

            if measure.number == song.measures.first?.number || length != previousLength {
                xml += "<attributes>"
                if measure.number == song.measures.first?.number { xml += "<divisions>\(grid)</divisions><key><fifths>\(fifths)</fifths></key>" }
                let (beats, unit) = timeSignature(forSixteenths: length)
                xml += "<time><beats>\(beats)</beats><beat-type>\(unit)</beat-type></time>"
                if measure.number == song.measures.first?.number {
                    xml += hands.count > 1
                        ? "<staves>2</staves><clef number=\"1\"><sign>G</sign><line>2</line></clef>"
                            + "<clef number=\"2\"><sign>F</sign><line>4</line></clef>"
                        : "<clef><sign>G</sign><line>2</line></clef>"
                }
                xml += "</attributes>"
            }
            if measure.number == song.measures.first?.number {
                let bpm = Int(song.tempoMap.bpm(atBeat: 0).rounded())
                xml += "<direction placement=\"above\"><direction-type><metronome><beat-unit>quarter</beat-unit>"
                    + "<per-minute>\(bpm)</per-minute></metronome></direction-type><staff>1</staff><sound tempo=\"\(bpm)\"/></direction>"
            }
            previousLength = length
            if let chord = chords[measure.number] {
                xml += "<harmony><root><root-step>\(chord.step)</root-step>"
                    + (chord.alter != 0 ? "<root-alter>\(chord.alter)</root-alter>" : "")
                    + "</root><kind text=\"\(escape(chord.suffix))\">\(chord.kind)</kind></harmony>"
            }

            for (index, hand) in hands.enumerated() {
                if index > 0 { xml += "<backup><duration>\(length)</duration></backup>" }
                xml += staff(
                    hand: hand, number: index + 1, song: song, start: start, length: length,
                    spelling: spelling, carried: &carried[hand]
                )
            }
            xml += "</measure>\n"
        }
        return xml + "</part></score-partwise>\n"
    }

    /// One hand's notes for one bar.
    private static func staff(
        hand: Hand, number: Int, song: Song, start: Int, length: Int, spelling: Spelling,
        carried: inout (pitches: [Pitch], remaining: Int)?
    ) -> String {
        // Finger numbers by position and pitch, for the notes that have them.
        var fingers: [Int: [Pitch: Int]] = [:]
        // Chords by position within the bar, in sixteenths.
        var chords: [Int: (pitches: Set<Pitch>, duration: Int, tiedFromPrevious: Bool)] = [:]
        if let held = carried, held.remaining > 0 {
            chords[0] = (Set(held.pitches), held.remaining, true)
        }
        carried = nil
        for note in song.notes where note.hand == hand {
            let position = quantize(note.start) - start
            guard position >= 0, position < length else { continue }
            let duration = max(quantize(note.duration), 1)
            if let finger = note.finger { fingers[position, default: [:]][note.pitch] = finger }
            if var chord = chords[position] {
                guard !chord.tiedFromPrevious else { continue } // a new note cannot join a held chord
                chord.pitches.insert(note.pitch)
                chord.duration = min(chord.duration, duration)
                chords[position] = chord
            } else {
                chords[position] = ([note.pitch], duration, false)
            }
        }
        guard !chords.isEmpty else {
            return "<note><rest measure=\"yes\"/><duration>\(length)</duration><voice>\(number)</voice><staff>\(number)</staff></note>"
        }

        var xml = ""
        var cursor = 0
        let positions = chords.keys.sorted()
        for (index, position) in positions.enumerated() {
            if position > cursor { xml += rests(position - cursor, staff: number) }
            let chord = chords[position]!
            let limit = (index + 1 < positions.count ? positions[index + 1] : length) - position
            let sounding = min(chord.duration, limit)
            // Held past the barline: finish it in the next bar.
            let overflow = index + 1 == positions.count ? chord.duration - sounding : 0
            let pitches = chord.pitches.sorted()
            if overflow > 0 { carried = (pitches, overflow) }

            let pieces = split(sounding)
            for (pieceIndex, piece) in pieces.enumerated() {
                let tieStop = pieceIndex > 0 || chord.tiedFromPrevious
                let tieStart = pieceIndex + 1 < pieces.count || overflow > 0
                for (pitchIndex, pitch) in pitches.enumerated() {
                    xml += note(
                        pitch, piece, staff: number, inChord: pitchIndex > 0, tieStop: tieStop, tieStart: tieStart,
                        spelling: spelling, finger: pieceIndex == 0 && !chord.tiedFromPrevious ? fingers[position]?[pitch] : nil
                    )
                }
            }
            cursor = position + sounding
        }
        if cursor < length { xml += rests(length - cursor, staff: number) }
        return xml
    }

    private static func note(
        _ pitch: Pitch, _ sixteenths: Int, staff: Int, inChord: Bool, tieStop: Bool, tieStart: Bool,
        spelling: Spelling, finger: Int?
    ) -> String {
        let (step, alter, accidental) = spelling.spell(pitch)
        var xml = "<note>" + (inChord ? "<chord/>" : "")
        // The octave number belongs to the letter: C♭4 is the B below middle C's octave.
        let octave = pitch.octave + (step == "B" && alter == 1 ? -1 : 0) + (step == "C" && alter == -1 ? 1 : 0)
        xml += "<pitch><step>\(step)</step>" + (alter != 0 ? "<alter>\(alter)</alter>" : "") + "<octave>\(octave)</octave></pitch>"
        xml += "<duration>\(sixteenths)</duration>"
        if tieStop { xml += "<tie type=\"stop\"/>" }
        if tieStart { xml += "<tie type=\"start\"/>" }
        xml += "<voice>\(staff)</voice>" + noteType(sixteenths)
        if let accidental, !tieStop { xml += "<accidental>\(accidental)</accidental>" }
        xml += "<staff>\(staff)</staff>"
        if tieStop || tieStart || finger != nil {
            xml += "<notations>" + (tieStop ? "<tied type=\"stop\"/>" : "") + (tieStart ? "<tied type=\"start\"/>" : "")
            if let finger { xml += "<technical><fingering>\(finger)</fingering></technical>" }
            xml += "</notations>"
        }
        return xml + "</note>"
    }

    /// Chooses letter names for pitches in a key and says when an accidental must be printed.
    struct Spelling {
        let fifths: Int
        let sharpened: Int?

        /// Alteration the key signature gives each letter.
        private var signature: [String: Int] {
            let sharps = ["F", "C", "G", "D", "A", "E", "B"]
            var result: [String: Int] = [:]
            if fifths > 0 { for letter in sharps.prefix(fifths) { result[letter] = 1 } }
            if fifths < 0 { for letter in sharps.reversed().prefix(-fifths) { result[letter] = -1 } }
            return result
        }

        func spell(_ pitch: Pitch) -> (step: String, alter: Int, accidental: String?) {
            let sharp: [(String, Int)] = [("C", 0), ("C", 1), ("D", 0), ("D", 1), ("E", 0), ("F", 0),
                                          ("F", 1), ("G", 0), ("G", 1), ("A", 0), ("A", 1), ("B", 0)]
            let flat: [(String, Int)] = [("C", 0), ("D", -1), ("D", 0), ("E", -1), ("E", 0), ("F", 0),
                                         ("G", -1), ("G", 0), ("A", -1), ("A", 0), ("B", -1), ("B", 0)]
            let useSharp = fifths >= 0 || pitch.pitchClass == sharpened
            let (step, alter) = (useSharp ? sharp : flat)[pitch.pitchClass]
            guard alter != (signature[step] ?? 0) else { return (step, alter, nil) }
            return (step, alter, alter > 0 ? "sharp" : (alter < 0 ? "flat" : "natural"))
        }
    }

    private static func rests(_ sixteenths: Int, staff: Int) -> String {
        split(sixteenths).map {
            "<note><rest/><duration>\($0)</duration><voice>\(staff)</voice>\(noteType($0))<staff>\(staff)</staff></note>"
        }.joined()
    }

    /// Breaks a length into values that exist as single notes, longest first.
    private static func split(_ sixteenths: Int) -> [Int] {
        var remaining = sixteenths
        var pieces: [Int] = []
        for value in [16, 12, 8, 6, 4, 3, 2, 1] {
            while remaining >= value {
                pieces.append(value)
                remaining -= value
            }
        }
        return pieces
    }

    private static func noteType(_ sixteenths: Int) -> String {
        let (name, dotted): (String, Bool) = switch sixteenths {
        case 16: ("whole", false)
        case 12: ("half", true)
        case 8: ("half", false)
        case 6: ("quarter", true)
        case 4: ("quarter", false)
        case 3: ("eighth", true)
        case 2: ("eighth", false)
        default: ("16th", false)
        }
        return "<type>\(name)</type>" + (dotted ? "<dot/>" : "")
    }

    private static func timeSignature(forSixteenths length: Int) -> (beats: Int, unit: Int) {
        if length % 4 == 0 { return (length / 4, 4) }
        if length % 2 == 0 { return (length / 2, 8) }
        return (length, 16)
    }

    private static func quantize(_ beats: Double) -> Int {
        Int((beats * Double(grid)).rounded())
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

public extension Song {
    /// The top line of the song as a single voice: the highest note at each moment, each
    /// lasting until the next one starts at the latest. All notes go to the right hand.
    func melodyLine() -> Song {
        // Highest note per sixteenth-note position.
        var top: [Int: Note] = [:]
        for note in notes {
            let position = Int((note.start * 4).rounded())
            if let existing = top[position], existing.pitch >= note.pitch { continue }
            top[position] = note
        }
        let ordered = top.keys.sorted()
        let line = ordered.enumerated().map { index, position -> Note in
            var note = top[position]!
            note.hand = .right
            note.finger = nil
            note.notationID = nil
            if index + 1 < ordered.count {
                note.duration = min(note.duration, Double(ordered[index + 1] - position) / 4)
            }
            return note
        }
        return Song(title: title, notes: line, tempoMap: tempoMap, measures: measures)
    }
}
