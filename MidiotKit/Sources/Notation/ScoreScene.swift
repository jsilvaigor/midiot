import CoreGraphics
import Foundation

/// A page of engraved music as drawable shapes in points, built from Verovio's SVG output.
///
/// Keeping the drawing as native paths, rather than showing the SVG in a web view, lets the app
/// recolor single notes, draw the staff light-on-dark, and know where every note and bar sits.
public struct ScoreScene: @unchecked Sendable { // CGPath is immutable once built
    public struct Shape {
        public let path: CGPath
        /// Line width in points when the shape is stroked.
        public let strokeWidth: CGFloat?
        public let isFilled: Bool
        /// Identifier of the note or rest this shape belongs to, if any.
        public let noteID: String?
    }

    public struct Label {
        public struct Run {
            public let text: String
            public let size: CGFloat
        }

        public enum Anchor { case start, middle, end }

        public let runs: [Run]
        /// Baseline position.
        public let origin: CGPoint
        public let anchor: Anchor
        public let isBold: Bool
        public let isItalic: Bool
        public let noteID: String?
    }

    public let size: CGSize
    public let shapes: [Shape]
    public let labels: [Label]
    /// Bounding box of every identified element (notes, chords, measures, staves, systems).
    public let frames: [String: CGRect]
    /// Verovio class of every identified element: "note", "measure", "staff", "system" and so on.
    public let classes: [String: String]

    public func ids(ofClass name: String) -> [String] {
        classes.filter { $0.value == name }.map(\.key)
    }

    public init?(svg: String) {
        let builder = SceneBuilder()
        let parser = XMLParser(data: Data(svg.utf8))
        parser.delegate = builder
        guard parser.parse(), builder.size != .zero else { return nil }
        size = builder.size
        shapes = builder.shapes
        labels = builder.labels
        frames = builder.frames
        classes = builder.classes
    }
}

private final class SceneBuilder: NSObject, XMLParserDelegate {
    var size = CGSize.zero
    var shapes: [ScoreScene.Shape] = []
    var labels: [ScoreScene.Label] = []
    var frames: [String: CGRect] = [:]
    var classes: [String: String] = [:]

    /// Drawing state inherited down the element tree.
    private struct State {
        var transform = CGAffineTransform.identity
        var isHidden = false
        var isBold = false
        var isItalic = false
        var noteID: String?
        /// Identified ancestors, whose frames grow with every shape drawn inside them.
        var ids: [String] = []
        var fontSize: CGFloat = 0
        /// True inside text set in Verovio's music font, whose characters are SMuFL code points.
        var isMusicFont = false
    }

    private var stack = [State()]
    private var glyphs: [String: CGPath] = [:]
    private var definingGlyph: String?
    private var inDefs = false
    private var svgDepth = 0

    // Text being collected.
    private var textOrigin: CGPoint?
    private var textAnchor = ScoreScene.Label.Anchor.start
    private var runs: [ScoreScene.Label.Run] = []

    private var state: State { stack[stack.count - 1] }

    func parser(
        _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
        qualifiedName: String?, attributes: [String: String]
    ) {
        var next = state
        defer { stack.append(next) }

        let classNames = (attributes["class"] ?? "").split(separator: " ").map(String.init)
        if classNames.contains("placeholder") { next.isHidden = true }
        if !Set(classNames).isDisjoint(with: ["ending", "fing", "reh", "tempo"]) { next.isBold = true }
        if !Set(classNames).isDisjoint(with: ["dir", "dynam", "mNum"]) { next.isItalic = true }
        if classNames.contains("label") { next.isBold = false }

        if name != "tspan", !inDefs, let id = attributes["id"], let first = classNames.first {
            next.ids.append(id)
            classes[id] = first
            if first == "note" || first == "rest" { next.noteID = id }
        }
        if let size = attributes["font-size"].flatMap(Self.length), size > 0 { next.fontSize = size }
        if name == "tspan", let family = attributes["font-family"] {
            next.isMusicFont = !family.lowercased().contains("times") && !family.lowercased().contains("serif")
        }

        switch name {
        case "svg":
            svgDepth += 1
            let box = attributes["viewBox"].map { text -> [CGFloat] in
                var scanner = NumberScanner(text)
                var values: [CGFloat] = []
                while let value = scanner.number() { values.append(value) }
                return values
            }
            if svgDepth == 1 {
                if let box, box.count == 4 {
                    size = CGSize(width: box[2], height: box[3])
                } else if let width = attributes["width"].flatMap(Self.length),
                          let height = attributes["height"].flatMap(Self.length) {
                    size = CGSize(width: width, height: height)
                }
            } else if let box, box.count == 4, box[2] > 0 {
                // A nested viewBox maps its own units onto the whole page.
                let scale = size.width / box[2]
                next.transform = CGAffineTransform(translationX: -box[0], y: -box[1])
                    .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                    .concatenating(next.transform)
            }
        case "defs":
            inDefs = true
        case "g":
            if inDefs {
                definingGlyph = attributes["id"]
            } else {
                next.transform = SVGPathParser.transform(from: attributes["transform"]).concatenating(next.transform)
            }
        case "path":
            guard let data = attributes["d"] else { break }
            let local = SVGPathParser.path(from: data)
            let own = SVGPathParser.transform(from: attributes["transform"])
            if inDefs {
                if let definingGlyph {
                    var transform = own
                    glyphs[definingGlyph] = local.copy(using: &transform) ?? local
                }
            } else {
                let width = attributes["stroke-width"].flatMap(Self.length)
                add(local, transform: own.concatenating(next.transform), strokeWidth: width, state: next)
            }
        case "use":
            guard !inDefs, let reference = attributes["xlink:href"] ?? attributes["href"],
                  let glyph = glyphs[String(reference.dropFirst())] else { break }
            let own = SVGPathParser.transform(from: attributes["transform"])
            add(glyph, transform: own.concatenating(next.transform), strokeWidth: nil, state: next)
        case "ellipse":
            guard let cx = attributes["cx"].flatMap(Self.length), let cy = attributes["cy"].flatMap(Self.length),
                  let rx = attributes["rx"].flatMap(Self.length), let ry = attributes["ry"].flatMap(Self.length) else { break }
            let ellipse = CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2), transform: nil)
            add(ellipse, transform: next.transform, strokeWidth: nil, state: next)
        case "rect":
            guard let x = attributes["x"].flatMap(Self.length), let y = attributes["y"].flatMap(Self.length),
                  let width = attributes["width"].flatMap(Self.length), let height = attributes["height"].flatMap(Self.length) else { break }
            add(CGPath(rect: CGRect(x: x, y: y, width: width, height: height), transform: nil),
                transform: next.transform, strokeWidth: nil, state: next)
        case "polygon", "polyline":
            guard let points = attributes["points"] else { break }
            var scanner = NumberScanner(points)
            let path = CGMutablePath()
            var isFirst = true
            while let x = scanner.number(), let y = scanner.number() {
                if isFirst { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                isFirst = false
            }
            if name == "polygon" { path.closeSubpath() }
            add(path, transform: next.transform, strokeWidth: attributes["stroke-width"].flatMap(Self.length), state: next)
        case "text":
            let x = attributes["x"].flatMap(Self.length) ?? 0
            let y = attributes["y"].flatMap(Self.length) ?? 0
            textOrigin = CGPoint(x: x, y: y)
            textAnchor = switch attributes["text-anchor"] {
            case "middle": .middle
            case "end": .end
            default: .start
            }
            runs = []
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard textOrigin != nil, !state.isHidden else { return }
        let text = string.trimmingCharacters(in: .newlines)
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, state.fontSize > 0 else { return }
        let shown = state.isMusicFont ? Self.unicodeNotes(for: text) : text
        // Music-font symbols are set larger than the surrounding text; the Unicode stand-in
        // drawn in a text font needs to be closer to the text size.
        let size = state.fontSize * scale(of: state.transform) * (state.isMusicFont ? 0.7 : 1)
        runs.append(.init(text: shown, size: size))
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let ended = stack.removeLast()
        switch name {
        case "svg": svgDepth -= 1
        case "defs": inDefs = false
        case "g": if inDefs { definingGlyph = nil }
        case "text":
            if let origin = textOrigin, !runs.isEmpty {
                let position = origin.applying(ended.transform)
                labels.append(.init(
                    runs: runs, origin: position, anchor: textAnchor,
                    isBold: ended.isBold, isItalic: ended.isItalic, noteID: ended.noteID
                ))
                // Rough box so labels count toward their owners' frames.
                let height = runs.map(\.size).max() ?? 0
                grow(ended.ids, by: CGRect(x: position.x, y: position.y - height, width: height, height: height))
            }
            textOrigin = nil
        default: break
        }
    }

    private func add(_ local: CGPath, transform: CGAffineTransform, strokeWidth: CGFloat?, state: State) {
        guard !state.isHidden else { return }
        var transform = transform
        guard let path = local.copy(using: &transform), !path.isEmpty else { return }
        let width = strokeWidth.map { $0 * scale(of: transform) }
        shapes.append(.init(path: path, strokeWidth: width, isFilled: true, noteID: state.noteID))
        var bounds = path.boundingBoxOfPath
        if let width { bounds = bounds.insetBy(dx: -width / 2, dy: -width / 2) }
        grow(state.ids, by: bounds)
    }

    private func grow(_ ids: [String], by rect: CGRect) {
        for id in ids {
            frames[id] = frames[id]?.union(rect) ?? rect
        }
    }

    private func scale(of transform: CGAffineTransform) -> CGFloat {
        abs(transform.a * transform.d - transform.b * transform.c).squareRoot()
    }

    /// Replaces the music-font symbols used in tempo marks and chord symbols with standard
    /// Unicode characters, which system fonts can draw.
    private static func unicodeNotes(for text: String) -> String {
        // SMuFL metronome-mark notes (U+ECA0...) and the older individual-note range (U+E1D0...).
        let map: [Unicode.Scalar: String] = [
            "\u{ECA2}": "\u{1D15D}", "\u{ECA3}": "\u{1D15E}", "\u{ECA4}": "\u{1D15E}",
            "\u{ECA5}": "\u{2669}", "\u{ECA6}": "\u{2669}",
            "\u{ECA7}": "\u{266A}", "\u{ECA8}": "\u{266A}", "\u{ECB7}": ".",
            "\u{E1D2}": "\u{1D15D}", "\u{E1D3}": "\u{1D15E}", "\u{E1D4}": "\u{1D15E}",
            "\u{E1D5}": "\u{2669}", "\u{E1D6}": "\u{2669}",
            "\u{E1D7}": "\u{266A}", "\u{E1D8}": "\u{266A}", "\u{E1E7}": ".",
            // Accidentals in chord symbols.
            "\u{E260}": "\u{266D}", "\u{E261}": "\u{266E}", "\u{E262}": "\u{266F}",
            "\u{ED60}": "\u{266D}", "\u{ED61}": "\u{266E}", "\u{ED62}": "\u{266F}",
            "\u{EA64}": "\u{266D}", "\u{EA65}": "\u{266E}", "\u{EA66}": "\u{266F}",
        ]
        return String(text.unicodeScalars.map { map[$0] ?? String($0) }.joined())
    }

    /// A number with an optional unit suffix such as "px".
    private static func length(_ text: String) -> CGFloat? {
        var scanner = NumberScanner(text)
        return scanner.number()
    }
}
