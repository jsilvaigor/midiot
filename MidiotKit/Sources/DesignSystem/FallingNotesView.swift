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

    private let range: KeyboardRange
    private let notes: [FallingNote]
    private let barLines: [BarLine]
    private let visibleBeats: Double
    private let position: () -> Double

    /// - Parameters:
    ///   - notes: sorted by start.
    ///   - visibleBeats: how many beats fit between the top edge and the bottom.
    ///   - position: the current beat; read every frame, so it must be cheap.
    public init(
        range: KeyboardRange, notes: [FallingNote], barLines: [BarLine] = [],
        visibleBeats: Double = 8, position: @escaping () -> Double
    ) {
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
            Canvas { context, size in
                _ = timeline.date
                draw(in: &context, size: size, now: now)
            }
        }
        .clipped()
        .accessibilityHidden(true)
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
