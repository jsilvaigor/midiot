import Foundation

/// What the keyboard and the recorded layer do when a cue is current on stage (requirement LV-1).
public struct StagePreset: Codable, Hashable, Sendable {
    /// A second sound played with the main one.
    public struct Second: Codable, Hashable, Sendable {
        /// General MIDI program; nil is the grand piano.
        public var program: Int?
        /// MIDI pitch of the lowest key that plays the main sound; keys below it play this
        /// one. Nil layers both sounds over the whole keyboard.
        public var splitAt: Int?

        public init(program: Int?, splitAt: Int? = nil) {
            self.program = program
            self.splitAt = splitAt
        }
    }

    /// General MIDI program the keyboard plays; nil is the grand piano.
    public var program: Int?
    public var second: Second?
    /// Tempo the recorded layer plays at; nil is the tempo it was recorded at.
    public var bpm: Double?
    /// MIDI channel, 0...15, that plays the main sound outside the app: the keyboard goes
    /// to MIDI out on it and the built-in sound stays quiet. Nil is the app's own sound.
    public var externalChannel: Int?

    public init(program: Int? = nil, second: Second? = nil, bpm: Double? = nil, externalChannel: Int? = nil) {
        self.program = program
        self.second = second
        self.bpm = bpm
        self.externalChannel = externalChannel
    }
}

/// The cues of a play in performance order, as the stage steps through them.
public struct CueSheet: Hashable, Sendable {
    public struct Entry: Hashable, Sendable, Identifiable {
        /// Scene number and letter: "3B".
        public let label: String
        public let sceneTitle: String
        public let cue: Cue

        public var id: UUID { cue.id }
    }

    public let entries: [Entry]

    public init(_ play: Play) {
        entries = play.scenes.flatMap { scene in
            scene.cues.map { Entry(label: play.label(of: $0.id) ?? "", sceneTitle: scene.title, cue: $0) }
        }
    }

    /// Where a step from `index` lands: one cue on or back, never past either end.
    public func index(stepping offset: Int, from index: Int) -> Int {
        guard !entries.isEmpty else { return 0 }
        return min(max(index + offset, 0), entries.count - 1)
    }

    public func index(of cueID: UUID) -> Int? {
        entries.firstIndex { $0.cue.id == cueID }
    }
}

/// How a cue's recorded layer runs on stage: how long it lasts and when it fades by itself
/// (requirement LV-2).
public struct LayerPlan: Hashable, Sendable {
    /// Seconds a fade takes, in or out.
    public static let fadeSeconds = 4.0

    /// Speed relative to the tempo the take was recorded at.
    public let rate: Double
    /// Seconds the take lasts at that speed.
    public let duration: Double
    /// Second at which the layer starts fading out so that it is silent at the cue's target
    /// length. Nil when the cue has no target or the take ends before it.
    public let fadeOutStart: Double?

    public init(take: Take, preset: StagePreset, targetSeconds: Double?) {
        let rate = preset.bpm.map { min(max($0 / max(take.bpm, 1), 0.25), 4) } ?? 1
        self.rate = rate
        duration = take.seconds / rate
        if let target = targetSeconds, target > 0, target < duration - 0.5 {
            fadeOutStart = max(target - Self.fadeSeconds, 0)
        } else {
            fadeOutStart = nil
        }
    }

    /// Seconds into the layer at a position of the take in beats.
    public func seconds(atBeat beat: Double, bpm: Double) -> Double {
        max(beat, 0) * 60 / max(bpm, 1) / rate
    }
}
