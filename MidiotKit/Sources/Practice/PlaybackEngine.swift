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
    }

    public let song: Song
    /// Bars to repeat, as a range of beats.
    public var loop: ClosedRange<Double>?
    public var metronomeIsOn = false
    /// Hands the app plays. A hand left out is silent, for the player to play (requirement SP-3).
    public var audibleHands: Set<Hand> = [.left, .right]
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

    public init(song: Song) {
        self.song = song
    }

    /// Position in beats. Negative during a count-in before the first bar.
    public func beat(at time: Double) -> Double {
        guard isPlaying else { return anchorBeat }
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
        sounding.removeAll()
        return [.allNotesOff]
    }

    public mutating func seek(to beat: Double, at time: Double) -> [Event] {
        anchorBeat = min(max(beat, 0), song.length)
        anchorTime = time
        countInEnd = nil
        lastClickBeat = nil
        pointNextIndex(at: anchorBeat)
        let wasSounding = !sounding.isEmpty
        sounding.removeAll()
        return wasSounding ? [.allNotesOff] : []
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
        var events: [Event] = []
        var beat = beat(at: time)

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
                guard audibleHands.contains(note.hand) else { continue }
                events.append(.noteOn(note))
                sounding.append(note)
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

    private mutating func pointNextIndex(at beat: Double) {
        nextIndex = song.notes.firstIndex { $0.start >= beat - 1e-9 } ?? song.notes.count
    }
}
