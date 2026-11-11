import CoreGraphics

/// Parses the `d` attribute of an SVG path and `transform` attributes.
/// Covers what Verovio emits (lines, cubic and quadratic curves); elliptical arcs are not supported.
enum SVGPathParser {
    static func path(from data: String) -> CGPath {
        let path = CGMutablePath()
        var scanner = NumberScanner(data)
        var command: Character = "M"
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        // Second control point of the previous curve, for the smooth-curve commands.
        var lastControl: CGPoint?

        while let next = scanner.nextCommandOrNumberStart() {
            if next.isLetter {
                command = next
                scanner.advance()
                if command == "Z" || command == "z" {
                    path.closeSubpath()
                    current = subpathStart
                    lastControl = nil
                    continue
                }
            }
            let relative = command.isLowercase
            func point() -> CGPoint? {
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }

            switch command {
            case "M", "m":
                guard let p = point() else { return path }
                path.move(to: p)
                current = p
                subpathStart = p
                lastControl = nil
                // Further coordinate pairs after a move are implicit line-tos.
                command = relative ? "l" : "L"
            case "L", "l":
                guard let p = point() else { return path }
                path.addLine(to: p)
                current = p
                lastControl = nil
            case "H", "h":
                guard let x = scanner.number() else { return path }
                current.x = relative ? current.x + x : x
                path.addLine(to: current)
                lastControl = nil
            case "V", "v":
                guard let y = scanner.number() else { return path }
                current.y = relative ? current.y + y : y
                path.addLine(to: current)
                lastControl = nil
            case "C", "c":
                guard let c1 = point(), let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                current = p
                lastControl = c2
            case "S", "s":
                let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                guard let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                current = p
                lastControl = c2
            case "Q", "q":
                guard let c = point(), let p = point() else { return path }
                path.addQuadCurve(to: p, control: c)
                current = p
                lastControl = nil
            default:
                return path // unsupported command: keep what was drawn so far
            }
        }
        return path
    }

    /// Parses `translate(x, y) scale(x, y) rotate(deg) matrix(a b c d e f)` lists.
    static func transform(from text: String?) -> CGAffineTransform {
        guard let text else { return .identity }
        var result = CGAffineTransform.identity
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "("), let close = rest.firstIndex(of: ")"), open < close {
            let name = rest[..<open].trimmingCharacters(in: .whitespaces.union(.init(charactersIn: ",")))
            var numbers = NumberScanner(String(rest[rest.index(after: open)..<close]))
            var values: [CGFloat] = []
            while let value = numbers.number() { values.append(value) }
            let step: CGAffineTransform
            switch (name, values.count) {
            case ("translate", 1): step = CGAffineTransform(translationX: values[0], y: 0)
            case ("translate", 2): step = CGAffineTransform(translationX: values[0], y: values[1])
            case ("scale", 1): step = CGAffineTransform(scaleX: values[0], y: values[0])
            case ("scale", 2): step = CGAffineTransform(scaleX: values[0], y: values[1])
            case ("rotate", 1): step = CGAffineTransform(rotationAngle: values[0] * .pi / 180)
            case ("matrix", 6):
                step = CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
            default: step = .identity
            }
            // SVG applies the rightmost transform to the shape first.
            result = step.concatenating(result)
            rest = rest[rest.index(after: close)...]
        }
        return result
    }
}

/// Reads numbers out of SVG attribute text, where separators are optional ("10-5" is two numbers).
struct NumberScanner {
    private let characters: [Character]
    private var index = 0

    init(_ text: String) {
        characters = Array(text)
    }

    private mutating func skipSeparators() {
        while index < characters.count, characters[index].isWhitespace || characters[index] == "," { index += 1 }
    }

    /// The next significant character, without consuming it: a command letter or the start of a number.
    mutating func nextCommandOrNumberStart() -> Character? {
        skipSeparators()
        return index < characters.count ? characters[index] : nil
    }

    mutating func advance() { index += 1 }

    mutating func number() -> CGFloat? {
        skipSeparators()
        let start = index
        if index < characters.count, characters[index] == "-" || characters[index] == "+" { index += 1 }
        var seenDot = false
        while index < characters.count {
            let c = characters[index]
            if c.isNumber {
                index += 1
            } else if c == ".", !seenDot {
                seenDot = true
                index += 1
            } else if c == "e" || c == "E", index + 1 < characters.count,
                      characters[index + 1].isNumber || characters[index + 1] == "-" {
                index += 2
            } else {
                break
            }
        }
        guard index > start, let value = Double(String(characters[start..<index])) else {
            index = start
            return nil
        }
        return CGFloat(value)
    }
}
