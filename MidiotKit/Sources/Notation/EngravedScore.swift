import Foundation
import MusicCore
import VerovioToolkit

/// A MusicXML score engraved by Verovio: the notes to practice and the pages to draw.
///
/// Both come from one engraving pass, so every `Note.notationID` names a shape in `pages`.
public struct EngravedScore: Sendable {
    public enum ImportError: Error, Equatable {
        /// The engraving data that ships with Verovio is missing from the app.
        case missingResources
        case unreadableScore
        case noNotes
    }

    public let song: Song
    /// Pages top to bottom; short pieces have one.
    public let pages: [ScoreScene]

    /// - Parameters:
    ///   - data: a MusicXML file, plain (`.musicxml`, `.xml`) or compressed (`.mxl`).
    ///   - pageWidth: width in points the music is laid out for; systems break to fit it.
    public init(musicXML data: Data, title: String, pageWidth: Double = 900) throws(ImportError) {
        guard let resources = VerovioResources.bundle.url(forResource: "data", withExtension: nil) else {
            throw .missingResources
        }
        let toolkit = VerovioToolkit(resources.path)
        // Verovio lays out in tenths of a millimetre-like units; `scale` 40 maps 2.5 units to a point.
        let options: [String: Any] = [
            "pageWidth": Int(pageWidth * 2.5), "pageHeight": 60000, "adjustPageHeight": true,
            "scale": 40, "breaks": "auto", "header": "none", "footer": "none", "svgViewBox": true,
            "pageMarginLeft": 60, "pageMarginRight": 60, "pageMarginTop": 60, "pageMarginBottom": 60,
        ]
        let json = (try? JSONSerialization.data(withJSONObject: options)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        _ = toolkit.setOptions(json)

        // Compressed MusicXML is a zip archive, which starts with "PK".
        let loaded = data.starts(with: [0x50, 0x4B])
            ? toolkit.loadZipDataBase64(data.base64EncodedString())
            : toolkit.loadData(String(decoding: data, as: UTF8.self))
        guard loaded, toolkit.getPageCount() > 0 else { throw .unreadableScore }

        // The timemap must be rendered before note pitches can be queried.
        guard let entries = try? JSONDecoder().decode(
            [TimemapEntry].self, from: Data(toolkit.renderToTimemap(#"{"includeMeasures": true}"#).utf8)
        ) else { throw .unreadableScore }
        let details = MEIDetails(mei: toolkit.getMEI("{}"))

        var starts: [String: Double] = [:]
        var notes: [Note] = []
        var tempos: [TempoMap.Change] = []
        var measureStarts: [Double] = []
        for entry in entries {
            if let tempo = entry.tempo { tempos.append(.init(beat: entry.qstamp, bpm: tempo)) }
            if entry.measureOn != nil { measureStarts.append(entry.qstamp) }
            for id in entry.off ?? [] {
                guard let start = starts.removeValue(forKey: id), let pitch = Self.pitch(of: id, in: toolkit) else { continue }
                let staff = details.staff[id] ?? 1
                notes.append(Note(
                    id: 0, pitch: pitch, start: start, duration: max(entry.qstamp - start, 0.01),
                    // On a grand staff the upper staff is the right hand.
                    hand: details.staffCount > 1 && staff > 1 ? .left : .right,
                    finger: details.finger[id], notationID: id
                ))
            }
            for id in entry.on ?? [] { starts[id] = entry.qstamp }
        }
        guard !notes.isEmpty else { throw .noNotes }

        let end = max(notes.map(\.end).max() ?? 0, entries.last?.qstamp ?? 0)
        let measures = measureStarts.enumerated().map { index, start in
            Measure(
                number: index + 1, start: start,
                length: (index + 1 < measureStarts.count ? measureStarts[index + 1] : end) - start
            )
        }
        song = Song(title: title, notes: notes, tempoMap: TempoMap(changes: tempos), measures: measures)
        pages = (1...toolkit.getPageCount()).compactMap { ScoreScene(svg: toolkit.renderToSVG($0, false)) }
    }

    private static func pitch(of id: String, in toolkit: VerovioToolkit) -> Pitch? {
        struct Values: Decodable { let pitch: Int? }
        let values = try? JSONDecoder().decode(Values.self, from: Data(toolkit.getMIDIValuesForElement(id).utf8))
        return values?.pitch.map(Pitch.init(midiNumber:))
    }
}

/// One moment in Verovio's timemap: which notes start and stop, in quarter-note beats.
private struct TimemapEntry: Decodable {
    let qstamp: Double
    let on: [String]?
    let off: [String]?
    let tempo: Double?
    let measureOn: String?
}

/// Staff and fingering of each note, read from Verovio's MEI encoding of the score.
private final class MEIDetails: NSObject, XMLParserDelegate {
    private(set) var staff: [String: Int] = [:]
    private(set) var finger: [String: Int] = [:]
    private(set) var staffCount = 1

    private var currentStaff = 1
    private var fingeringTarget: String?
    private var fingeringText = ""

    init(mei: String) {
        super.init()
        let parser = XMLParser(data: Data(mei.utf8))
        parser.delegate = self
        parser.parse()
    }

    func parser(
        _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
        qualifiedName: String?, attributes: [String: String]
    ) {
        switch name {
        case "staff":
            currentStaff = attributes["n"].flatMap(Int.init) ?? 1
            staffCount = max(staffCount, currentStaff)
        case "note":
            // A note can be moved to another staff than the one it is encoded in.
            if let id = attributes["xml:id"] { staff[id] = attributes["staff"].flatMap(Int.init) ?? currentStaff }
        case "fing":
            fingeringTarget = attributes["startid"].map { String($0.dropFirst()) }
            fingeringText = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if fingeringTarget != nil { fingeringText += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard name == "fing", let target = fingeringTarget else { return }
        if let number = Int(fingeringText.trimmingCharacters(in: .whitespacesAndNewlines)), (1...5).contains(number) {
            finger[target] = number
        }
        fingeringTarget = nil
    }
}
