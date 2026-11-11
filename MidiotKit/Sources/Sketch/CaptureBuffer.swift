import Foundation
import Synchronization

/// Everything played recently, so an idea can be kept after it was played (requirement CO-1).
///
/// A value with no clock of its own: callers pass times in seconds on the host clock.
/// `CaptureBuffer` wraps it for use from the MIDI thread.
public struct CaptureHistory: Sendable {
    public enum Event: Hashable, Sendable {
        case noteOn(pitch: Int, velocity: Int)
        case noteOff(pitch: Int)
        case sustain(isDown: Bool)
    }

    /// A note as it was played, in seconds on the host clock.
    public struct PlayedNote: Hashable, Sendable {
        public let pitch: Int
        public let velocity: Int
        public let start: Double
        public let end: Double
    }

    /// Seconds of playing kept.
    public let retention: Double
    private var events: [(time: Double, event: Event)] = []

    public init(retention: Double = 600) {
        self.retention = retention
    }

    public var isEmpty: Bool { events.isEmpty }

    public mutating func record(_ event: Event, at time: Double) {
        // MIDI stamps can arrive slightly out of order; keep the list sorted.
        var index = events.count
        while index > 0, events[index - 1].time > time { index -= 1 }
        events.insert((time, event), at: index)
        if let newest = events.last?.time, let first = events.first, first.time < newest - retention - 60 {
            events.removeAll { $0.time < newest - retention }
        }
    }

    /// The notes that started between `from` and `to`, with the sustain pedal folded into
    /// their lengths. A key still held at `to` ends there.
    public func notes(from: Double, to: Double) -> [PlayedNote] {
        var held: [Int: (start: Double, velocity: Int)] = [:]
        // Keys released while the pedal is down keep sounding until it comes up.
        var sustained: [(pitch: Int, start: Double, velocity: Int)] = []
        var pedalIsDown = false
        var result: [PlayedNote] = []

        func finish(_ pitch: Int, _ start: Double, _ velocity: Int, at end: Double) {
            guard start >= from, start <= to else { return }
            result.append(PlayedNote(pitch: pitch, velocity: velocity, start: start, end: max(min(end, to), start + 0.02)))
        }

        for (time, event) in events where time <= to {
            switch event {
            case let .noteOn(pitch, velocity):
                // Striking a key again ends its earlier sound.
                if let old = held.removeValue(forKey: pitch) { finish(pitch, old.start, old.velocity, at: time) }
                if let index = sustained.firstIndex(where: { $0.pitch == pitch }) {
                    let old = sustained.remove(at: index)
                    finish(pitch, old.start, old.velocity, at: time)
                }
                held[pitch] = (time, velocity)
            case let .noteOff(pitch):
                guard let old = held.removeValue(forKey: pitch) else { continue }
                if pedalIsDown {
                    sustained.append((pitch, old.start, old.velocity))
                } else {
                    finish(pitch, old.start, old.velocity, at: time)
                }
            case let .sustain(isDown):
                pedalIsDown = isDown
                if !isDown {
                    for note in sustained { finish(note.pitch, note.start, note.velocity, at: time) }
                    sustained.removeAll()
                }
            }
        }
        for (pitch, note) in held { finish(pitch, note.start, note.velocity, at: to) }
        for note in sustained { finish(note.pitch, note.start, note.velocity, at: to) }
        return result.sorted { ($0.start, $0.pitch) < ($1.start, $1.pitch) }
    }

    /// How much was played in each of `buckets` equal slices of the `window` seconds ending at
    /// `now`, oldest first, each 0...1.
    public func activity(buckets: Int, window: Double, now: Double) -> [Double] {
        guard buckets > 0, window > 0 else { return [] }
        var counts = Array(repeating: 0.0, count: buckets)
        let start = now - window
        for (time, event) in events where time >= start && time <= now {
            guard case let .noteOn(_, velocity) = event else { continue }
            let index = min(Int((time - start) / window * Double(buckets)), buckets - 1)
            counts[index] += 0.5 + Double(velocity) / 254
        }
        // Six notes in one slice is already busy playing.
        return counts.map { min($0 / 6, 1) }
    }
}

/// A `CaptureHistory` that can be written from the MIDI thread and read from anywhere.
public final class CaptureBuffer: Sendable {
    private let history: Mutex<CaptureHistory>

    public init(retention: Double = 600) {
        history = Mutex(CaptureHistory(retention: retention))
    }

    public var retention: Double { history.withLock { $0.retention } }

    public func record(_ event: CaptureHistory.Event, at time: Double) {
        history.withLock { $0.record(event, at: time) }
    }

    public func notes(from: Double, to: Double) -> [CaptureHistory.PlayedNote] {
        history.withLock { $0.notes(from: from, to: to) }
    }

    public func activity(buckets: Int, window: Double, now: Double) -> [Double] {
        history.withLock { $0.activity(buckets: buckets, window: window, now: now) }
    }
}

public extension Layer {
    /// Turns played notes into a layer timed in beats.
    /// - Parameters:
    ///   - origin: host time that becomes beat 0. Notes that start before it are dropped,
    ///     except within a sixteenth of a second, which is pulled to the start.
    ///   - bpm: tempo the beats are measured at.
    init(played: [CaptureHistory.PlayedNote], origin: Double, bpm: Double, program: Int? = nil) {
        let beatsPerSecond = bpm / 60
        let notes = played.compactMap { note -> SketchNote? in
            guard note.start >= origin - 0.0625 else { return nil }
            let start = max(note.start - origin, 0)
            return SketchNote(
                pitch: note.pitch, start: start * beatsPerSecond,
                duration: max(note.end - max(note.start, origin), 0.02) * beatsPerSecond, velocity: note.velocity
            )
        }
        self.init(notes: notes, program: program)
    }
}

public extension Take {
    /// A take from the notes played in a stretch of time, starting at its first note.
    /// Returns nil when nothing was played.
    init?(played: [CaptureHistory.PlayedNote], number: Int, bpm: Double, program: Int? = nil, date: Date = Date()) {
        guard let first = played.map(\.start).min() else { return nil }
        self.init(number: number, createdAt: date, bpm: bpm, layers: [Layer(played: played, origin: first, bpm: bpm, program: program)])
    }
}
