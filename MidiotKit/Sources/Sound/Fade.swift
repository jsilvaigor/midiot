/// A change of loudness over time: a straight line from one level to another.
///
/// A value with no clock of its own: callers pass times in seconds on the host clock.
public struct Fade: Hashable, Sendable {
    /// Levels are 0 (silent) to 1 (full).
    public let from: Double
    public let to: Double
    public let start: Double
    public let duration: Double

    public init(from: Double, to: Double, start: Double, duration: Double) {
        self.from = min(max(from, 0), 1)
        self.to = min(max(to, 0), 1)
        self.start = start
        self.duration = max(duration, 0)
    }

    /// A level that does not change.
    public static func steady(_ level: Double) -> Fade {
        Fade(from: level, to: level, start: 0, duration: 0)
    }

    public func level(at time: Double) -> Double {
        guard duration > 0, time < start + duration else { return to }
        guard time > start else { return from }
        return from + (to - from) * (time - start) / duration
    }

    public func isOver(at time: Double) -> Bool {
        time >= start + duration
    }

    /// A new fade that starts from wherever this one has got to, so changing direction
    /// midway never jumps. A full fade takes `fullDuration`; a partial one takes its share.
    public func turning(to level: Double, at time: Double, fullDuration: Double) -> Fade {
        let now = self.level(at: time)
        let target = min(max(level, 0), 1)
        return Fade(from: now, to: target, start: time, duration: fullDuration * abs(target - now))
    }
}
