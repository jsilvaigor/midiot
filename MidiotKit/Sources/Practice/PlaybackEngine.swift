import MusicCore

/// Decides what should sound at each moment while a song plays.
///
/// A value with no clock or audio of its own: callers pass the current time (seconds on the
/// host clock) and receive the events due since the last call. `SongPlayer` drives it in real
/// time; tests drive it with made-up times.
public struct PlaybackEngine: Sendable {
    public enum Event: Hashable, Sendable {
        case noteOn(Note)
        case noteOff(Note)
        case click(isDownbeat: Bool)
        /// Everything must stop sounding: the position jumped or playback paused.
        case allNotesOff
        /// The end of the song was reached; playback has stopped.
        case finished
        /// The player's attempt at a note was judged. `noteID` indexes `song.notes`.
        /// `offset` is how far from the note the key was pressed, in seconds (negative is
        /// early); nil when timing was not measured (wait mode, missed notes).
        case judged(noteID: Int, Judgement, offset: Double?)
        /// The player pressed a key that no upcoming note asks for, at this beat.
        case wrongKey(Pitch, beat: Double)
        /// Wait mode stopped the music until these notes are played.
        case waiting(for: [Note])
        /// The awaited notes were played and the music moves on.
        case resumed
        /// The position jumped; judgements of notes from this beat on no longer apply.
        case judgementsCleared(fromBeat: Double)
    }

    /// How the player did on one note (requirement FB-1).
    public enum Judgement: String, Hashable, Sendable, Codable {
        case correct, early, late, missed
    }

    /// A press within this many seconds of the note counts as on time.
    public static let onTimeWindow = 0.09
    /// A press further than this from every matching note is a wrong key.
    public static let matchWindow = 0.30

    public let song: Song
    /// Bars to repeat, as a range of beats.
    public var loop: ClosedRange<Double>?
    public var metronomeIsOn = false
    /// Hands the player plays. The app stays silent on these and judges the player instead;
    /// it plays the other hand (requirement SP-3). Empty means the app plays everything.
    public var playerHands: Set<Hand> = []
    /// Wait mode: the music stops at each of the player's notes until they are played
    /// (requirement SP-2). Timing is not judged in this mode.
    public var waitsForPlayer = false
    /// True while wait mode is holding the music.
    public private(set) var isWaiting = false
    public private(set) var isPlaying = false
    /// Playback speed relative to the song's own tempo (requirement SP-5).
    public private(set) var rate = 1.0

    // Position at `anchorTime`; while paused, simply the position.
    private var anchorBeat = 0.0
    private var anchorTime = 0.0
    private var nextIndex = 0
    private var sounding: [Note] = []
    /// Beat at which the count-in ends and the music starts.
    private var countInEnd: Double?
    private var lastClickBeat: Double?
    /// Per note: whether the player's attempt has been judged.
    private var isJudged: [Bool]
    /// First note not yet checked for being missed.
    private var missIndex = 0

    public init(song: Song) {
        self.song = song
        isJudged = Array(repeating: false, count: song.notes.count)
    }

    /// Position in beats. Negative during a count-in before the first bar.
    public func beat(at time: Double) -> Double {
        guard isPlaying, !isWaiting else { return anchorBeat }
        let seconds = song.tempoMap.seconds(atBeat: anchorBeat) + (time - anchorTime) * rate
        return song.tempoMap.beat(atSeconds: seconds)
    }

    /// Starts from the current position, optionally after a count-in of metronome clicks.
    public mutating func play(at time: Double, countInBeats: Double = 0) {
        guard !isPlaying else { return }
        if anchorBeat >= song.length { anchorBeat = loop?.lowerBound ?? 0 }
        pointNextIndex(at: anchorBeat)
        if countInBeats > 0 {
            countInEnd = anchorBeat
            anchorBeat -= countInBeats
        }
        anchorTime = time
        lastClickBeat = nil
        isPlaying = true
    }

    public mutating func pause(at time: Double) -> [Event] {
        guard isPlaying else { return [] }
        let beat = beat(at: time)
        isPlaying = false
        // Pausing during a count-in returns to where the music would have started.
        anchorBeat = countInEnd.map { max(beat, $0) } ?? beat
        countInEnd = nil
        isWaiting = false
        sounding.removeAll()
        return [.allNotesOff]
    }

    public mutating func seek(to beat: Double, at time: Double) -> [Event] {
        anchorBeat = min(max(beat, 0), song.length)
        anchorTime = time
        countInEnd = nil
        lastClickBeat = nil
        pointNextIndex(at: anchorBeat)
        isWaiting = false
        for index in nextIndex..<song.notes.count { isJudged[index] = false }
        missIndex = nextIndex
        let wasSounding = !sounding.isEmpty
        sounding.removeAll()
        return (wasSounding ? [.allNotesOff] : []) + [.judgementsCleared(fromBeat: anchorBeat)]
    }

    public mutating func setRate(_ newRate: Double, at time: Double) {
        // Re-anchor first so the change takes effect from now, not from when playback started.
        anchorBeat = beat(at: time)
        anchorTime = time
        rate = min(max(newRate, 0.1), 4)
    }

    /// Returns everything that became due up to `time`, in order.
    public mutating func advance(to time: Double) -> [Event] {
        guard isPlaying else { return [] }
        if isWaiting {
            // Hold the position; time passing while waiting is not part of the music.
            anchorTime = time
            return []
        }
        var events: [Event] = []
        var beat = beat(at: time)

        // Wait mode: do not pass the player's next notes until they are played.
        var awaited: [Note] = []
        if waitsForPlayer, let group = pendingGroup(), beat >= group[0].start {
            beat = group[0].start
            anchorBeat = beat
            anchorTime = time
            isWaiting = true
            awaited = group
        }

        let isCountingIn = countInEnd.map { beat < $0 } ?? false
        if !isCountingIn { countInEnd = nil }

        if let loop, !isCountingIn, beat >= loop.upperBound {
            // Carry the overshoot into the next pass so the loop keeps strict time.
            let overshoot = (beat - loop.upperBound).truncatingRemainder(dividingBy: max(loop.upperBound - loop.lowerBound, 0.001))
            events += seek(to: loop.lowerBound + overshoot, at: time)
            beat = anchorBeat
        } else if beat >= song.length {
            isPlaying = false
            anchorBeat = song.length
            events += sounding.map(Event.noteOff)
            sounding.removeAll()
            events.append(.finished)
            return events
        }

        let ended = sounding.filter { $0.end <= beat }
        if !ended.isEmpty {
            events += ended.map(Event.noteOff)
            sounding.removeAll { $0.end <= beat }
        }

        if !isCountingIn {
            while nextIndex < song.notes.count, song.notes[nextIndex].start <= beat {
                let note = song.notes[nextIndex]
                nextIndex += 1
                guard !playerHands.contains(note.hand) else { continue }
                events.append(.noteOn(note))
                sounding.append(note)
            }
        }

        if !awaited.isEmpty {
            events.append(.waiting(for: awaited))
        } else if !waitsForPlayer {
            // Notes the player never played, once it is too late to count a press for them.
            let window = beats(forSeconds: Self.matchWindow, at: beat)
            while missIndex < song.notes.count, song.notes[missIndex].start + window < beat {
                let note = song.notes[missIndex]
                if playerHands.contains(note.hand), !isJudged[missIndex] {
                    isJudged[missIndex] = true
                    events.append(.judged(noteID: note.id, .missed, offset: nil))
                }
                missIndex += 1
            }
        }

        if metronomeIsOn || isCountingIn {
            let measure = song.measure(atBeat: max(beat, 0))
            let start = measure?.start ?? 0
            let length = max(Int((measure?.length ?? 4).rounded()), 1)
            let index = Int((beat - start + 1e-9).rounded(.down))
            let clickBeat = start + Double(index)
            if clickBeat != lastClickBeat {
                lastClickBeat = clickBeat
                events.append(.click(isDownbeat: ((index % length) + length) % length == 0))
            }
        }
        return events
    }

    /// Call when the player presses a key. Returns the judgement, if the press counts for one.
    public mutating func playerPressed(_ pitch: Pitch, at time: Double) -> [Event] {
        guard isPlaying, !playerHands.isEmpty else { return [] }
        let beat = beat(at: time)
        if let countInEnd, beat < countInEnd { return [] }

        if waitsForPlayer {
            guard let group = pendingGroup() else { return [] }
            // A press shortly before the music reaches the note counts too.
            let isNear = isWaiting || seconds(forBeats: group[0].start - beat, at: beat) <= Self.matchWindow
            guard isNear, let note = group.first(where: { $0.pitch == pitch && !isJudged[$0.id] }) else {
                return [.wrongKey(pitch, beat: beat)]
            }
            isJudged[note.id] = true
            var events: [Event] = [.judged(noteID: note.id, .correct, offset: nil)]
            if isWaiting, group.allSatisfy({ isJudged[$0.id] }) {
                isWaiting = false
                anchorTime = time
                events.append(.resumed)
            }
            return events
        }

        let window = beats(forSeconds: Self.matchWindow, at: beat)
        let candidate = song.notes
            .filter { $0.pitch == pitch && playerHands.contains($0.hand) && !isJudged[$0.id] && abs($0.start - beat) <= window }
            .min { abs($0.start - beat) < abs($1.start - beat) }
        guard let note = candidate else { return [.wrongKey(pitch, beat: beat)] }
        isJudged[note.id] = true
        let offset = seconds(forBeats: beat - note.start, at: beat)
        let judgement: Judgement = abs(offset) <= Self.onTimeWindow ? .correct : (offset < 0 ? .early : .late)
        return [.judged(noteID: note.id, judgement, offset: offset)]
    }

    /// The player's next unplayed notes that start together, if any remain.
    private func pendingGroup() -> [Note]? {
        var index = missIndex
        while index < song.notes.count, !playerHands.contains(song.notes[index].hand) || isJudged[index] { index += 1 }
        guard index < song.notes.count else { return nil }
        let start = song.notes[index].start
        return song.notes[index...].prefix { $0.start - start < 1e-6 }
            .filter { playerHands.contains($0.hand) && !isJudged[$0.id] }
    }

    private func beats(forSeconds seconds: Double, at beat: Double) -> Double {
        seconds * song.tempoMap.bpm(atBeat: max(beat, 0)) / 60 * rate
    }

    private func seconds(forBeats beats: Double, at beat: Double) -> Double {
        beats * 60 / song.tempoMap.bpm(atBeat: max(beat, 0)) / rate
    }

    private mutating func pointNextIndex(at beat: Double) {
        nextIndex = song.notes.firstIndex { $0.start >= beat - 1e-9 } ?? song.notes.count
    }
}
