import MusicCore
import Testing
@testable import Practice

@Suite struct PlaybackEngineTests {
    /// Two bars of 4/4 at 60 bpm, so one beat is one second: right hand C D on beats 0 and 1,
    /// left hand E held through bar 2.
    static let song = Song(
        title: "T",
        notes: [
            Note(id: 0, pitch: Pitch(midiNumber: 60), start: 0, duration: 1, hand: .right),
            Note(id: 0, pitch: Pitch(midiNumber: 62), start: 1, duration: 1, hand: .right),
            Note(id: 0, pitch: Pitch(midiNumber: 52), start: 4, duration: 4, hand: .left),
        ],
        tempoMap: TempoMap(bpm: 60),
        measures: Song.evenMeasures(beatsPerMeasure: 4, covering: 8)
    )

    func pitches(_ events: [PlaybackEngine.Event]) -> [String] {
        events.map {
            switch $0 {
            case let .noteOn(note): "on\(note.pitch.midiNumber)"
            case let .noteOff(note): "off\(note.pitch.midiNumber)"
            case let .click(isDownbeat): isDownbeat ? "CLICK" : "click"
            case .allNotesOff: "alloff"
            case .finished: "finished"
            case let .judged(noteID, judgement, _): "\(judgement.rawValue)#\(noteID)"
            case let .wrongKey(pitch, _): "wrong\(pitch.midiNumber)"
            case let .waiting(notes): "wait" + notes.map { String($0.pitch.midiNumber) }.joined(separator: "+")
            case .resumed: "resumed"
            case .judgementsCleared: "cleared"
            }
        }
    }

    @Test func playsNotesInTime() {
        var engine = PlaybackEngine(song: Self.song)
        engine.play(at: 100)
        #expect(pitches(engine.advance(to: 100)) == ["on60"])
        #expect(pitches(engine.advance(to: 100.5)) == [])
        #expect(pitches(engine.advance(to: 101)) == ["off60", "on62"])
        #expect(engine.beat(at: 101.5) == 1.5)
        #expect(pitches(engine.advance(to: 104)) == ["off62", "on52"])
        #expect(pitches(engine.advance(to: 108)) == ["off52", "finished"])
        #expect(!engine.isPlaying)
        #expect(engine.beat(at: 200) == 8)
    }

    @Test func rateSlowsPlayback() {
        var engine = PlaybackEngine(song: Self.song)
        engine.setRate(0.5, at: 0)
        engine.play(at: 0)
        _ = engine.advance(to: 0)
        #expect(pitches(engine.advance(to: 1)) == [])
        #expect(pitches(engine.advance(to: 2)) == ["off60", "on62"])
        // Changing speed mid-way continues from the current position.
        engine.setRate(1, at: 2)
        #expect(engine.beat(at: 3) == 2)
    }

    @Test func pauseAndResume() {
        var engine = PlaybackEngine(song: Self.song)
        engine.play(at: 0)
        _ = engine.advance(to: 0)
        #expect(pitches(engine.pause(at: 0.5)) == ["alloff"])
        #expect(engine.beat(at: 50) == 0.5)
        engine.play(at: 50)
        #expect(pitches(engine.advance(to: 50.5)) == ["on62"])
    }

    @Test func loopRepeatsARange() {
        var engine = PlaybackEngine(song: Self.song)
        engine.loop = 0...2
        engine.play(at: 0)
        #expect(pitches(engine.advance(to: 0)) == ["on60"])
        #expect(pitches(engine.advance(to: 1)) == ["off60", "on62"])
        #expect(pitches(engine.advance(to: 2)) == ["alloff", "cleared", "on60"])
        #expect(engine.beat(at: 2.5) == 0.5)
    }

    @Test func handsCanBeSilenced() {
        var engine = PlaybackEngine(song: Self.song)
        engine.playerHands = [.right]
        engine.play(at: 0)
        #expect(pitches(engine.advance(to: 0.2)) == [])
        #expect(pitches(engine.advance(to: 4)) == ["on52", "missed#0", "missed#1"])
    }

    @Test func countInClicksBeforeTheMusic() {
        var engine = PlaybackEngine(song: Self.song)
        engine.play(at: 0, countInBeats: 4)
        #expect(engine.beat(at: 0) == -4)
        #expect(pitches(engine.advance(to: 0)) == ["CLICK"])
        #expect(pitches(engine.advance(to: 1)) == ["click"])
        #expect(pitches(engine.advance(to: 2.5)) == ["click"])
        #expect(pitches(engine.advance(to: 3)) == ["click"])
        // The music starts; the metronome is off, so the clicks stop.
        #expect(pitches(engine.advance(to: 4)) == ["on60"])
        #expect(pitches(engine.advance(to: 5)) == ["off60", "on62"])
    }

    @Test func metronomeMarksDownbeats() {
        var engine = PlaybackEngine(song: Self.song)
        engine.metronomeIsOn = true
        engine.playerHands = [.left, .right]
        engine.play(at: 0)
        let clicks = (0...5).flatMap { pitches(engine.advance(to: Double($0))) }.filter { $0.lowercased() == "click" }
        #expect(clicks == ["CLICK", "click", "click", "click", "CLICK", "click"])
    }

    @Test func seekSilencesAndRepositions() {
        var engine = PlaybackEngine(song: Self.song)
        engine.play(at: 0)
        _ = engine.advance(to: 0)
        #expect(pitches(engine.seek(to: 4, at: 0.5)) == ["alloff", "cleared"])
        #expect(pitches(engine.advance(to: 0.5)) == ["on52"])
    }

    // MARK: Judging the player

    @Test func timingIsJudged() {
        var engine = PlaybackEngine(song: Self.song)
        engine.playerHands = [.right]
        engine.play(at: 0)
        _ = engine.advance(to: 0)
        // Note 0 is at 0 s, note 1 at 1 s.
        #expect(pitches(engine.playerPressed(Pitch(midiNumber: 60), at: 0.05)) == ["correct#0"])
        #expect(pitches(engine.playerPressed(Pitch(midiNumber: 62), at: 0.8)) == ["early#1"])
        // Already judged, so a second press has nothing to match.
        #expect(pitches(engine.playerPressed(Pitch(midiNumber: 62), at: 1.0)) == ["wrong62"])
        #expect(pitches(engine.playerPressed(Pitch(midiNumber: 61), at: 1.0)) == ["wrong61"])
    }

    @Test func lateAndMissed() {
        var engine = PlaybackEngine(song: Self.song)
        engine.playerHands = [.right]
        engine.play(at: 0)
        #expect(pitches(engine.playerPressed(Pitch(midiNumber: 60), at: 0.2)) == ["late#0"])
        // Nothing pressed for note 1 (at 1 s); it is missed once the window has passed.
        #expect(pitches(engine.advance(to: 1.2)) == [])
        #expect(pitches(engine.advance(to: 1.4)) == ["missed#1"])
    }

    @Test func pressesAreIgnoredWhenTheAppPlaysEverything() {
        var engine = PlaybackEngine(song: Self.song)
        engine.play(at: 0)
        #expect(engine.playerPressed(Pitch(midiNumber: 60), at: 0).isEmpty)
    }

    @Test func waitModeHoldsUntilTheNoteIsPlayed() {
        var engine = PlaybackEngine(song: Self.song)
        engine.playerHands = [.right]
        engine.waitsForPlayer = true
        engine.play(at: 0)
        #expect(pitches(engine.advance(to: 0)) == ["wait60"])
        #expect(engine.isWaiting)
        // Time passes, the music does not.
        #expect(pitches(engine.advance(to: 5)) == [])
        #expect(engine.beat(at: 5) == 0)
        #expect(pitches(engine.playerPressed(Pitch(midiNumber: 61), at: 5)) == ["wrong61"])
        #expect(pitches(engine.playerPressed(Pitch(midiNumber: 60), at: 6)) == ["correct#0", "resumed"])
        #expect(engine.beat(at: 6.5) == 0.5)
        #expect(pitches(engine.advance(to: 7)) == ["wait62"])
        #expect(pitches(engine.playerPressed(Pitch(midiNumber: 62), at: 7)) == ["correct#1", "resumed"])
        // The left hand is the app's: it plays at beat 4, three beats later.
        #expect(pitches(engine.advance(to: 10)) == ["on52"])
    }

    @Test func waitModeNeedsEveryNoteOfAChord() {
        let chord = Song(
            title: "C",
            notes: [60, 64, 67].map { Note(id: 0, pitch: Pitch(midiNumber: $0), start: 1, duration: 1, hand: .right) },
            tempoMap: TempoMap(bpm: 60), measures: Song.evenMeasures(beatsPerMeasure: 4, covering: 4)
        )
        var engine = PlaybackEngine(song: chord)
        engine.playerHands = [.right]
        engine.waitsForPlayer = true
        engine.play(at: 0)
        // Pressed just before the chord arrives: counts.
        #expect(pitches(engine.playerPressed(Pitch(midiNumber: 60), at: 0.9)) == ["correct#0"])
        #expect(pitches(engine.advance(to: 1)) == ["wait64+67"])
        #expect(pitches(engine.playerPressed(Pitch(midiNumber: 64), at: 2)) == ["correct#1"])
        #expect(engine.isWaiting)
        #expect(pitches(engine.playerPressed(Pitch(midiNumber: 67), at: 3)) == ["correct#2", "resumed"])
    }

    @Test func seekingBackClearsJudgements() {
        var engine = PlaybackEngine(song: Self.song)
        engine.playerHands = [.right]
        engine.play(at: 0)
        _ = engine.playerPressed(Pitch(midiNumber: 60), at: 0)
        #expect(pitches(engine.seek(to: 0, at: 0.5)) == ["cleared"])
        #expect(pitches(engine.playerPressed(Pitch(midiNumber: 60), at: 0.5)) == ["correct#0"])
    }
}
