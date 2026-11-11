import CoreGraphics
import MusicCore

/// Positions of piano keys inside a rectangle. Pure geometry, shared by drawing and hit-testing.
public struct KeyboardLayout: Sendable {
    public let range: KeyboardRange
    public let size: CGSize

    /// Black keys are this fraction of a white key's width and of the keyboard's height.
    static let blackWidthRatio: CGFloat = 0.58
    static let blackHeightRatio: CGFloat = 0.62

    private let whiteCount: Int

    public init(range: KeyboardRange, size: CGSize) {
        self.range = range
        self.size = size
        whiteCount = range.pitches.count { !$0.isBlackKey }
    }

    public var whiteKeyWidth: CGFloat { whiteCount > 0 ? size.width / CGFloat(whiteCount) : 0 }

    /// Number of white keys in the range below `pitch`.
    private func whitesBelow(_ pitch: Pitch) -> Int {
        guard pitch > range.lowest else { return 0 }
        return (range.lowest.midiNumber..<pitch.midiNumber).count { !Pitch(midiNumber: $0).isBlackKey }
    }

    public func frame(of pitch: Pitch) -> CGRect {
        let x = CGFloat(whitesBelow(pitch)) * whiteKeyWidth
        if pitch.isBlackKey {
            // A black key straddles the line between its two white neighbours.
            let width = whiteKeyWidth * Self.blackWidthRatio
            return CGRect(x: x - width / 2, y: 0, width: width, height: size.height * Self.blackHeightRatio)
        }
        return CGRect(x: x, y: 0, width: whiteKeyWidth, height: size.height)
    }

    /// The key under a point, black keys taking priority because they sit on top.
    public func pitch(at point: CGPoint) -> Pitch? {
        guard CGRect(origin: .zero, size: size).contains(point) else { return nil }
        let pitches = range.pitches
        return pitches.first { $0.isBlackKey && frame(of: $0).contains(point) }
            ?? pitches.first { !$0.isBlackKey && frame(of: $0).contains(point) }
    }
}
