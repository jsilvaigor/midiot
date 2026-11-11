/// Adaptive practice (requirement FB-3): decides the tempo for the next pass of a loop from
/// how the last passes went.
public struct AdaptiveTempo: Hashable, Sendable {
    /// A pass at or above this accuracy is clean.
    public static let cleanAccuracy = 0.9
    /// A pass below this accuracy is poor.
    public static let poorAccuracy = 0.6
    public static let cleanPassesToSpeedUp = 3
    public static let poorPassesToSlowDown = 2
    public static let step = 0.05
    /// Tempo never drops below this fraction of the song's tempo, nor rises above full tempo.
    public static let slowest = 0.4

    /// Clean passes in a row so far.
    public private(set) var cleanPasses = 0
    public private(set) var poorPasses = 0

    public init() {}

    /// Records a finished pass and returns the tempo to use next, as a fraction of the song's tempo.
    public mutating func passEnded(accuracy: Double, rate: Double) -> Double {
        if accuracy >= Self.cleanAccuracy {
            poorPasses = 0
            cleanPasses += 1
            guard cleanPasses >= Self.cleanPassesToSpeedUp else { return rate }
            cleanPasses = 0
            return min(1, Self.rounded(rate + Self.step))
        }
        cleanPasses = 0
        guard accuracy < Self.poorAccuracy else {
            poorPasses = 0
            return rate
        }
        poorPasses += 1
        guard poorPasses >= Self.poorPassesToSlowDown else { return rate }
        poorPasses = 0
        return max(Self.slowest, Self.rounded(rate - Self.step))
    }

    /// To the nearest 5%, so repeated steps do not drift.
    private static func rounded(_ rate: Double) -> Double {
        (rate * 20).rounded() / 20
    }
}
