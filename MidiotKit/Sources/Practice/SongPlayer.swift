import Dispatch
import MusicCore
import Synchronization

/// Plays a song in real time by running a `PlaybackEngine` on a fast timer.
///
/// Events are delivered on the player's own queue, never the main thread, so sound keeps time
/// while the interface is busy. All methods are safe to call from any thread.
public final class SongPlayer: Sendable {
    public typealias Output = @Sendable (PlaybackEngine.Event) -> Void

    private let engine: Mutex<PlaybackEngine>
    private let output: Output
    private let queue = DispatchQueue(label: "dev.midiot.player", qos: .userInteractive)
    private let timer: DispatchSourceTimer

    /// Seconds on the host clock, the same clock MIDI events are stamped with.
    public static var now: Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000 }

    public init(song: Song, output: @escaping Output) {
        engine = Mutex(PlaybackEngine(song: song))
        self.output = output
        timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        // 2 ms steps keep note timing error well under what the ear can detect.
        timer.schedule(deadline: .now(), repeating: .milliseconds(2), leeway: .microseconds(200))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
    }

    deinit {
        timer.cancel()
        output(.allNotesOff)
    }

    public var song: Song { engine.withLock { $0.song } }
    public var isPlaying: Bool { engine.withLock { $0.isPlaying } }
    public var rate: Double { engine.withLock { $0.rate } }
    /// Current position in beats.
    public var beat: Double { engine.withLock { $0.beat(at: Self.now) } }

    public func play(countInBeats: Double = 0) {
        engine.withLock { $0.play(at: Self.now, countInBeats: countInBeats) }
    }

    public func pause() {
        send(engine.withLock { $0.pause(at: Self.now) })
    }

    public func seek(to beat: Double) {
        send(engine.withLock { $0.seek(to: beat, at: Self.now) })
    }

    public func setRate(_ rate: Double) {
        engine.withLock { $0.setRate(rate, at: Self.now) }
    }

    public func setLoop(_ loop: ClosedRange<Double>?) {
        engine.withLock { $0.loop = loop }
    }

    public func setMetronome(_ isOn: Bool) {
        engine.withLock { $0.metronomeIsOn = isOn }
    }

    public func setPlayerHands(_ hands: Set<Hand>) {
        engine.withLock { $0.playerHands = hands }
    }

    public func setWaitsForPlayer(_ waits: Bool) {
        engine.withLock { $0.waitsForPlayer = waits }
    }

    /// Reports a key press by the player. Safe to call from the MIDI thread.
    /// - Parameter time: when the key was pressed, in host-clock seconds; nil means now.
    public func playerPressed(_ pitch: Pitch, at time: Double? = nil) {
        send(engine.withLock { $0.playerPressed(pitch, at: time ?? Self.now) })
    }

    private func tick() {
        send(engine.withLock { $0.advance(to: Self.now) })
    }

    private func send(_ events: [PlaybackEngine.Event]) {
        for event in events { output(event) }
    }
}
