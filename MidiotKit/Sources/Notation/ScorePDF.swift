import CoreGraphics
import CoreText
import Foundation

/// Writes engraved music as a PDF for printing: a clean draft, not final engraving
/// (requirement CO-7). Lines of music are kept whole and flowed onto as many sheets as needed.
public enum ScorePDF {
    /// A4 in points.
    public static let a4 = CGSize(width: 595, height: 842)

    /// - Parameters:
    ///   - pages: engraved music, as from `EngravedScore.pages`.
    ///   - subtitle: a line under the title, such as the play and cue.
    public static func data(pages: [ScoreScene], title: String, subtitle: String? = nil, paper: CGSize = a4) -> Data {
        let output = NSMutableData()
        var box = CGRect(origin: .zero, size: paper)
        guard let consumer = CGDataConsumer(data: output), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            return Data()
        }
        let margin: CGFloat = 40
        let width = paper.width - margin * 2
        let bottom = paper.height - margin

        var sheet = 0
        // Distance from the top of the sheet to the next free line.
        var cursor = margin
        var isOpen = false

        func beginSheet() {
            context.beginPDFPage(nil)
            isOpen = true
            sheet += 1
            cursor = margin
            if sheet == 1 {
                draw(title, font: font(22, bold: false, italic: false), at: CGPoint(x: paper.width / 2, y: paper.height - cursor - 20), centered: true, in: context)
                cursor += 32
                if let subtitle, !subtitle.isEmpty {
                    draw(subtitle, font: font(10, bold: false, italic: true), at: CGPoint(x: paper.width / 2, y: paper.height - cursor - 10), centered: true, in: context)
                    cursor += 18
                }
                cursor += 10
            } else {
                draw("\(title) · \(sheet)", font: font(8, bold: false, italic: false), at: CGPoint(x: paper.width - margin, y: margin / 2), centered: false, rightAligned: true, in: context)
            }
        }

        beginSheet()
        for scene in pages where scene.size.width > 0 {
            let scale = width / scene.size.width
            for band in bands(of: scene) {
                let height = band.height * scale
                if cursor + height > bottom, cursor > margin + 80 {
                    context.endPDFPage()
                    beginSheet()
                }
                context.saveGState()
                // Scene coordinates run downward from the top left; PDF runs upward.
                context.translateBy(x: margin, y: paper.height - cursor)
                context.scaleBy(x: scale, y: -scale)
                context.translateBy(x: 0, y: -band.minY)
                context.clip(to: CGRect(x: 0, y: band.minY, width: scene.size.width, height: band.height))
                draw(scene, within: band, in: context)
                context.restoreGState()
                cursor += height
            }
        }
        if isOpen { context.endPDFPage() }
        context.closePDF()
        return output as Data
    }

    /// The scene cut into horizontal strips, one per line of music, meeting halfway between lines.
    static func bands(of scene: ScoreScene) -> [CGRect] {
        let systems = scene.ids(ofClass: "system").compactMap { scene.frames[$0] }.sorted { $0.minY < $1.minY }
        guard !systems.isEmpty else { return [CGRect(origin: .zero, size: scene.size)] }
        return systems.enumerated().map { index, system in
            let top = index == 0 ? max(system.minY - 20, 0) : (systems[index - 1].maxY + system.minY) / 2
            let end = index + 1 < systems.count ? (system.maxY + systems[index + 1].minY) / 2 : min(system.maxY + 20, scene.size.height)
            return CGRect(x: 0, y: top, width: scene.size.width, height: max(end - top, 1))
        }
    }

    private static func draw(_ scene: ScoreScene, within band: CGRect, in context: CGContext) {
        context.setFillColor(gray: 0, alpha: 1)
        context.setStrokeColor(gray: 0, alpha: 1)
        for shape in scene.shapes {
            let bounds = shape.path.boundingBoxOfPath.insetBy(dx: -2, dy: -2)
            guard bounds.intersects(band) else { continue }
            if shape.isFilled {
                context.addPath(shape.path)
                context.fillPath()
            }
            if let width = shape.strokeWidth {
                context.addPath(shape.path)
                context.setLineWidth(width)
                context.strokePath()
            }
        }
        for label in scene.labels where label.origin.y >= band.minY - 1 && label.origin.y <= band.maxY + 40 {
            let text = NSMutableAttributedString()
            for run in label.runs {
                text.append(NSAttributedString(string: run.text, attributes: [
                    kCTFontAttributeName as NSAttributedString.Key: font(run.size, bold: label.isBold, italic: label.isItalic),
                ]))
            }
            let line = CTLineCreateWithAttributedString(text)
            let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            let x: CGFloat = switch label.anchor {
            case .start: label.origin.x
            case .middle: label.origin.x - width / 2
            case .end: label.origin.x - width
            }
            // The page is flipped, so text is flipped back to read upright.
            context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            context.textPosition = CGPoint(x: x, y: label.origin.y)
            CTLineDraw(line, context)
        }
    }

    private static func draw(
        _ string: String, font: CTFont, at point: CGPoint, centered: Bool, rightAligned: Bool = false, in context: CGContext
    ) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: string, attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        ))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: point.x - (centered ? width / 2 : (rightAligned ? width : 0)), y: point.y)
        CTLineDraw(line, context)
    }

    private static func font(_ size: CGFloat, bold: Bool, italic: Bool) -> CTFont {
        let base = CTFontCreateWithName("Times New Roman" as CFString, size, nil)
        var traits: CTFontSymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        guard !traits.isEmpty else { return base }
        return CTFontCreateCopyWithSymbolicTraits(base, size, nil, traits, [.traitBold, .traitItalic]) ?? base
    }
}
