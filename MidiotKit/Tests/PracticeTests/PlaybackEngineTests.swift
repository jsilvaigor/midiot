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
        #expect(pitches(engine.advance(to: 2)) == ["alloff", "on60"])
        #expect(engine.beat(at: 2.5) == 0.5)
    }

    @Test func handsCanBeSilenced() {
        var engine = PlaybackEngine(song: Self.song)
        engine.audibleHands = [.left]
        engine.play(at: 0)
        #expect(pitches(engine.advance(to: 3)) == [])
        #expect(pitches(engine.advance(to: 4)) == ["on52"])
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
        engine.audibleHands = []
        engine.play(at: 0)
        let clicks = (0...5).flatMap { pitches(engine.advance(to: Double($0))) }
        #expect(clicks == ["CLICK", "click", "click", "click", "CLICK", "click"])
    }

    @Test func seekSilencesAndRepositions() {
        var engine = PlaybackEngine(song: Self.song)
        engine.play(at: 0)
        _ = engine.advance(to: 0)
        #expect(pitches(engine.seek(to: 4, at: 0.5)) == ["alloff"])
        #expect(pitches(engine.advance(to: 0.5)) == ["on52"])
    }
}
