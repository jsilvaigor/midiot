import MusicCore
import SwiftUI

/// A note in the falling-notes lane.
public struct FallingNote: Identifiable, Sendable {
    public let id: Int
    public let pitch: Pitch
    public let start: Double
    public let duration: Double
    public let color: Color
    /// Short text drawn at the bottom of the note, such as a finger number.
    public let label: String?

    public init(id: Int, pitch: Pitch, start: Double, duration: Double, color: Color, label: String? = nil) {
        self.id = id
        self.pitch = pitch
        self.start = start
        self.duration = duration
        self.color = color
        self.label = label
    }
}

/// Notes falling toward the keyboard. The bottom edge is "now"; place it directly above a
/// `KeyboardView` of the same range and width so each note lands on its key.
public struct FallingNotesView: View {
    public struct BarLine: Sendable {
        public let beat: Double
        public let label: String

        public init(beat: Double, label: String) {
            self.beat = beat
            self.label = label
        }
    }

    /// The stretch just above the keys where a note's lower edge is when pressing its key
    /// counts as on time, and the stretch above that where it counts as early.
    public struct TimingZones: Sendable {
        /// Heights of the two bands in beats, from the bottom edge up.
        public let onTimeBeats: Double
        public let earlyBeats: Double
        public let onTimeLabel: String
        public let earlyLabel: String

        public init(onTimeBeats: Double, earlyBeats: Double, onTimeLabel: String, earlyLabel: String) {
            self.onTimeBeats = onTimeBeats
            self.earlyBeats = earlyBeats
            self.onTimeLabel = onTimeLabel
            self.earlyLabel = earlyLabel
        }
    }

    private let range: KeyboardRange
    private let notes: [FallingNote]
    private let barLines: [BarLine]
    private let visibleBeats: Double
    private let position: () -> Double
    private let timingZones: (() -> TimingZones?)?

    /// - Parameters:
    ///   - notes: sorted by start.
    ///   - visibleBeats: how many beats fit between the top edge and the bottom.
    ///   - position: the current beat; read every frame, so it must be cheap.
    ///   - timingZones: the on-time and early bands to draw above the keys; read every
    ///     frame, because they grow and shrink with the tempo. Nil draws none.
    public init(
        range: KeyboardRange, notes: [FallingNote], barLines: [BarLine] = [],
        visibleBeats: Double = 8, timingZones: (() -> TimingZones?)? = nil, position: @escaping () -> Double
    ) {
        self.timingZones = timingZones
        self.range = range
        self.notes = notes
        self.barLines = barLines
        self.visibleBeats = visibleBeats
        self.position = position
    }

    public var body: some View {
        TimelineView(.animation) { timeline in
            // The position is read here, once per tick, and the canvas uses the tick's date:
            // a canvas that depends on neither is redrawn only when something else changes.
            let now = position()
            let zones = timingZones?()
            Canvas { context, size in
                _ = timeline.date
                if let zones { drawBands(zones, in: &context, size: size) }
                draw(in: &context, size: size, now: now)
                if let zones { drawMarks(zones, in: &context, size: size) }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    /// The two bands as rectangles, bottom edge up.
    private func bands(_ zones: TimingZones, size: CGSize) -> (onTime: CGRect, early: CGRect) {
        let pointsPerBeat = size.height / visibleBeats
        let onTime = max(zones.onTimeBeats * pointsPerBeat, 6)
        let early = max(zones.earlyBeats * pointsPerBeat, onTime)
        return (CGRect(x: 0, y: size.height - onTime, width: size.width, height: onTime),
                CGRect(x: 0, y: size.height - early, width: size.width, height: early - onTime))
    }

    /// The bands' fills, under the notes: press a key while its note's lower edge is in the
    /// green band and it is on time; in the blue band above, early.
    private func drawBands(_ zones: TimingZones, in context: inout GraphicsContext, size: CGSize) {
        let (onTime, early) = bands(zones, size: size)
        context.fill(Path(early), with: .linearGradient(
            Gradient(colors: [Palette.noteEarly.opacity(0.04), Palette.noteEarly.opacity(0.14)]),
            startPoint: CGPoint(x: 0, y: early.minY), endPoint: CGPoint(x: 0, y: early.maxY)
        ))
        context.fill(Path(onTime), with: .color(Palette.noteCorrect.opacity(0.24)))
    }

    /// The bands' edges and names, over the notes so a passing note never hides them.
    /// Color is never the only cue: each band is named at both edges of the lane.
    private func drawMarks(_ zones: TimingZones, in context: inout GraphicsContext, size: CGSize) {
        let (onTime, early) = bands(zones, size: size)
        context.fill(Path(CGRect(x: 0, y: onTime.minY - 1, width: size.width, height: 2)), with: .color(Palette.noteCorrect.opacity(0.85)))
        if early.height >= 4 {
            context.stroke(
                Path { $0.move(to: CGPoint(x: 0, y: early.minY)); $0.addLine(to: CGPoint(x: size.width, y: early.minY)) },
                with: .color(Palette.noteEarly.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )
        }

        /// A name on a dark chip, centered on its band's height at one edge of the lane.
        func tag(_ label: String, color: Color, band: CGRect, x: CGFloat, anchor: UnitPoint) {
            let text = context.resolve(Text(verbatim: label).font(.sans(10, weight: .semibold)).foregroundStyle(color))
            let textSize = text.measure(in: size)
            let height = textSize.height + 4
            let box = CGRect(
                x: anchor == .leading ? x : x - textSize.width - 10,
                y: min(band.midY - height / 2, size.height - height - 1),
                width: textSize.width + 10, height: height
            )
            context.fill(Path(roundedRect: box, cornerRadius: 5), with: .color(Palette.background.opacity(0.9)))
            context.stroke(Path(roundedRect: box, cornerRadius: 5), with: .color(color.opacity(0.5)), lineWidth: 1)
            context.draw(text, at: CGPoint(x: box.midX, y: box.midY))
        }
        for (x, anchor) in [(CGFloat(6), UnitPoint.leading), (size.width - 6, .trailing)] {
            if early.height >= 30 { tag(zones.earlyLabel, color: Palette.noteEarly, band: early, x: x, anchor: anchor) }
            tag(zones.onTimeLabel, color: Palette.noteCorrect, band: onTime, x: x, anchor: anchor)
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, now: Double) {
        let layout = KeyboardLayout(range: range, size: size)
        let pointsPerBeat = size.height / visibleBeats
        func y(_ beat: Double) -> CGFloat { size.height - (beat - now) * pointsPerBeat }

        // Octave guides: a faint line at every C.
        for pitch in range.pitches where pitch.pitchClass == 0 {
            let x = layout.frame(of: pitch).minX
            context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(.white.opacity(0.05)))
        }

        for line in barLines where line.beat >= now && line.beat <= now + visibleBeats {
            let lineY = y(line.beat)
            context.fill(Path(CGRect(x: 0, y: lineY, width: size.width, height: 1)), with: .color(.white.opacity(0.09)))
            context.draw(
                Text(verbatim: line.label).font(.mono(10)).foregroundStyle(Palette.textTertiary),
                at: CGPoint(x: 6, y: lineY - 8), anchor: .leading
            )
        }

        for note in notes {
            if note.start > now + visibleBeats { break }
            guard note.start + note.duration >= now, range.contains(note.pitch) else { continue }
            let key = layout.frame(of: note.pitch)
            let bottom = y(note.start)
            let height = max(note.duration * pointsPerBeat - 3, 6)
            let rect = CGRect(x: key.minX + 2, y: bottom - height, width: max(key.width - 4, 3), height: height)
            let path = Path(roundedRect: rect, cornerRadius: min(8, rect.width / 2), style: .continuous)

            var glow = context
            glow.addFilter(.shadow(color: note.color.opacity(0.3), radius: 8))
            glow.fill(path, with: .linearGradient(
                Gradient(colors: [note.color.mix(with: .white, by: 0.35), note.color]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)
            ))

            if let label = note.label, rect.width >= 12, rect.height >= 18 {
                context.draw(
                    Text(verbatim: label).font(.mono(10, weight: .semibold)).foregroundStyle(Palette.accentInk),
                    at: CGPoint(x: rect.midX, y: rect.maxY - 9)
                )
            }
        }
    }
}
