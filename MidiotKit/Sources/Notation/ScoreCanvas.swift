import SwiftUI

/// Draws a `ScoreScene`. Notes listed in `noteColors` are drawn in that color; everything else in `ink`.
public struct ScoreCanvas: View {
    private let scene: ScoreScene
    private let ink: Color
    private let noteColors: [String: Color]

    public init(scene: ScoreScene, ink: Color, noteColors: [String: Color] = [:]) {
        self.scene = scene
        self.ink = ink
        self.noteColors = noteColors
    }

    public var body: some View {
        Canvas { context, size in
            // Fit the page to the available width.
            let scale = scene.size.width > 0 ? size.width / scene.size.width : 1
            context.scaleBy(x: scale, y: scale)

            for shape in scene.shapes {
                let color = shape.noteID.flatMap { noteColors[$0] } ?? ink
                let path = Path(shape.path)
                if shape.isFilled { context.fill(path, with: .color(color)) }
                if let width = shape.strokeWidth {
                    context.stroke(path, with: .color(color), lineWidth: width)
                }
            }

            for label in scene.labels {
                let color = label.noteID.flatMap { noteColors[$0] } ?? ink
                var text = Text(verbatim: "")
                for run in label.runs {
                    var font = Font.custom("Times New Roman", size: run.size)
                    if label.isBold { font = font.bold() }
                    if label.isItalic { font = font.italic() }
                    text = text + Text(verbatim: run.text).font(font)
                }
                let anchor: UnitPoint = switch label.anchor {
                case .start: .bottomLeading
                case .middle: .bottom
                case .end: .bottomTrailing
                }
                let resolved = context.resolve(text.foregroundStyle(color))
                // SVG positions text by its baseline; SwiftUI by its box, so lift by the descent.
                let descent = resolved.measure(in: CGSize(width: 10_000, height: 10_000)).height
                    - resolved.firstBaseline(in: CGSize(width: 10_000, height: 10_000))
                context.draw(resolved, at: CGPoint(x: label.origin.x, y: label.origin.y + descent), anchor: anchor)
            }
        }
        .aspectRatio(scene.size.width / max(scene.size.height, 1), contentMode: .fit)
    }
}
