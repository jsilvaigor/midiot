import MusicCore

/// Writes a readable draft score for a song that has no notation of its own, such as a MIDI
/// import. Rhythms are rounded to sixteenth notes and each hand is written as one line of
/// notes and chords, so the result is for reading along, not for print.
public enum MusicXMLWriter {
    /// Sixteenth notes per beat: the rhythmic grid of the draft.
    private static let grid = 4

    public static func draft(from song: Song) -> String {
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
                if measure.number == song.measures.first?.number { xml += "<divisions>\(grid)</divisions><key><fifths>0</fifths></key>" }
                let (beats, unit) = timeSignature(forSixteenths: length)
                xml += "<time><beats>\(beats)</beats><beat-type>\(unit)</beat-type></time>"
                if measure.number == song.measures.first?.number {
                    xml += "<staves>2</staves><clef number=\"1\"><sign>G</sign><line>2</line></clef>"
                        + "<clef number=\"2\"><sign>F</sign><line>4</line></clef>"
                }
                xml += "</attributes>"
            }
            if measure.number == song.measures.first?.number {
                let bpm = Int(song.tempoMap.bpm(atBeat: 0).rounded())
                xml += "<direction placement=\"above\"><direction-type><metronome><beat-unit>quarter</beat-unit>"
                    + "<per-minute>\(bpm)</per-minute></metronome></direction-type><staff>1</staff><sound tempo=\"\(bpm)\"/></direction>"
            }
            previousLength = length

            for (index, hand) in [Hand.right, .left].enumerated() {
                if index > 0 { xml += "<backup><duration>\(length)</duration></backup>" }
                xml += staff(
                    hand: hand, number: index + 1, song: song, start: start, length: length,
                    carried: &carried[hand]
                )
            }
            xml += "</measure>\n"
        }
        return xml + "</part></score-partwise>\n"
    }

    /// One hand's notes for one bar.
    private static func staff(
        hand: Hand, number: Int, song: Song, start: Int, length: Int,
        carried: inout (pitches: [Pitch], remaining: Int)?
    ) -> String {
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
                    xml += note(pitch, piece, staff: number, inChord: pitchIndex > 0, tieStop: tieStop, tieStart: tieStart)
                }
            }
            cursor = position + sounding
        }
        if cursor < length { xml += rests(length - cursor, staff: number) }
        return xml
    }

    private static func note(_ pitch: Pitch, _ sixteenths: Int, staff: Int, inChord: Bool, tieStop: Bool, tieStart: Bool) -> String {
        let steps: [(String, Int)] = [("C", 0), ("C", 1), ("D", 0), ("D", 1), ("E", 0), ("F", 0),
                                      ("F", 1), ("G", 0), ("G", 1), ("A", 0), ("A", 1), ("B", 0)]
        let (step, alter) = steps[pitch.pitchClass]
        var xml = "<note>" + (inChord ? "<chord/>" : "")
        xml += "<pitch><step>\(step)</step>" + (alter != 0 ? "<alter>\(alter)</alter>" : "") + "<octave>\(pitch.octave)</octave></pitch>"
        xml += "<duration>\(sixteenths)</duration>"
        if tieStop { xml += "<tie type=\"stop\"/>" }
        if tieStart { xml += "<tie type=\"start\"/>" }
        xml += "<voice>\(staff)</voice>" + noteType(sixteenths)
        if alter != 0 { xml += "<accidental>sharp</accidental>" }
        xml += "<staff>\(staff)</staff>"
        if tieStop || tieStart {
            xml += "<notations>" + (tieStop ? "<tied type=\"stop\"/>" : "") + (tieStart ? "<tied type=\"start\"/>" : "") + "</notations>"
        }
        return xml + "</note>"
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
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
