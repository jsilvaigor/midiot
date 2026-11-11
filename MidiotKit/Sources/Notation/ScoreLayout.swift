import CoreGraphics
import MusicCore

/// Where musical time falls on the engraved pages: the cursor position for any beat, and the
/// bar under any point.
public struct ScoreLayout: Sendable {
    /// A vertical cursor line on one page, in that page's coordinates (points).
    public struct Position: Hashable, Sendable {
        public let page: Int
        public let x: CGFloat
        /// Top and bottom of the system (line of music) the cursor is on.
        public let top: CGFloat
        public let bottom: CGFloat
    }

    private struct Anchor {
        let beat: Double
        let x: CGFloat
        let page: Int
        let system: CGRect
    }

    private struct Bar {
        let number: Int
        let page: Int
        let frame: CGRect
    }

    private let anchors: [Anchor]
    private let bars: [Bar]

    public init(song: Song, pages: [ScoreScene]) {
        var anchors: [Anchor] = []
        var bars: [Bar] = []

        /// The page and system (line of music) containing a frame.
        func locate(_ id: String) -> (page: Int, frame: CGRect, system: CGRect)? {
            for (page, scene) in pages.enumerated() {
                guard let frame = scene.frames[id] else { continue }
                let center = CGPoint(x: frame.midX, y: frame.midY)
                let system = scene.ids(ofClass: "system").compactMap { scene.frames[$0] }.first { $0.contains(center) }
                return (page, frame, system ?? frame)
            }
            return nil
        }

        var systemOfMeasure: [Int: (page: Int, system: CGRect)] = [:]
        for measure in song.measures {
            guard let id = measure.notationID, let found = locate(id) else { continue }
            bars.append(Bar(number: measure.number, page: found.page, frame: found.frame))
            systemOfMeasure[measure.number] = (found.page, found.system)
            // The cursor reaches the right edge of the bar as the bar ends.
            anchors.append(Anchor(beat: measure.end - 1e-4, x: found.frame.maxX, page: found.page, system: found.system))
        }

        // One anchor per distinct onset: the leftmost notehead sounding at that beat.
        var onsetX: [Double: (x: CGFloat, page: Int, system: CGRect)] = [:]
        for note in song.notes {
            guard let id = note.notationID, let found = locate(id) else { continue }
            // Prefer the bar's system: a note's own frame can poke outside it.
            let number = song.measure(atBeat: note.start)?.number
            let system = number.flatMap { systemOfMeasure[$0]?.system } ?? found.system
            if let existing = onsetX[note.start], existing.x <= found.frame.minX { continue }
            onsetX[note.start] = (found.frame.minX, found.page, system)
        }
        anchors += onsetX.map { Anchor(beat: $0.key, x: $0.value.x, page: $0.value.page, system: $0.value.system) }

        self.anchors = anchors.sorted { $0.beat < $1.beat }
        self.bars = bars
    }

    public var isEmpty: Bool { anchors.isEmpty }

    /// Cursor position for a beat, moving smoothly between notes on the same system.
    public func position(atBeat beat: Double) -> Position? {
        guard let first = anchors.first else { return nil }
        guard let index = anchors.lastIndex(where: { $0.beat <= beat }) else {
            return Position(page: first.page, x: first.x, top: first.system.minY, bottom: first.system.maxY)
        }
        let current = anchors[index]
        var x = current.x
        if index + 1 < anchors.count {
            let next = anchors[index + 1]
            if next.page == current.page, next.system == current.system, next.beat > current.beat {
                x += (next.x - current.x) * CGFloat((beat - current.beat) / (next.beat - current.beat))
            }
        }
        return Position(page: current.page, x: x, top: current.system.minY, bottom: current.system.maxY)
    }

    /// Frame of a bar on its page.
    public func frame(ofMeasure number: Int) -> (page: Int, frame: CGRect)? {
        bars.first { $0.number == number }.map { ($0.page, $0.frame) }
    }

    /// Number of the bar under a point on a page.
    public func measure(at point: CGPoint, page: Int) -> Int? {
        bars.first { $0.page == page && $0.frame.contains(point) }?.number
    }
}
