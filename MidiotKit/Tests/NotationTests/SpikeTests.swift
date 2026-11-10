import Foundation
import Testing
import VerovioToolkit

/// Phase 2 exploration: what Verovio gives us for one small MusicXML file.
@Suite struct SpikeTests {
    @Test func explore() throws {
        let url = try #require(Bundle.module.url(forResource: "two-hands", withExtension: "musicxml", subdirectory: "Fixtures"))
        let xml = try String(contentsOf: url, encoding: .utf8)
        let data = try #require(VerovioResources.bundle.url(forResource: "data", withExtension: nil))
        let toolkit = VerovioToolkit(data.path)
        print("VERSION", toolkit.getVersion())
        #expect(toolkit.setOptions(#"{"pageWidth": 2100, "pageHeight": 60000, "adjustPageHeight": true, "scale": 40, "breaks": "auto", "header": "none", "footer": "none", "svgViewBox": true}"#))
        let start = Date()
        #expect(toolkit.loadData(xml))
        print("PAGES", toolkit.getPageCount(), "load s", Date().timeIntervalSince(start))
        let svg = toolkit.renderToSVG(1, false)
        print("SVG bytes", svg.count, "render s", Date().timeIntervalSince(start))
        let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SPIKE_OUT"] ?? NSTemporaryDirectory())
        try svg.write(to: out.appendingPathComponent("spike.svg"), atomically: true, encoding: .utf8)
        let timemap = toolkit.renderToTimemap(#"{"includeMeasures": true, "includeRests": false}"#)
        try timemap.write(to: out.appendingPathComponent("spike-timemap.json"), atomically: true, encoding: .utf8)
        try toolkit.getMEI("{}").write(to: out.appendingPathComponent("spike.mei"), atomically: true, encoding: .utf8)
        print("TIMEMAP", timemap.prefix(700))
        // First note id from the timemap.
        if let range = timemap.range(of: #""on"\s*:\s*\[\s*"([^"]+)""#, options: .regularExpression) {
            let id = String(timemap[range]).components(separatedBy: "\"").dropLast().last ?? ""
            print("FIRST", id)
            print("MIDI", toolkit.getMIDIValuesForElement(id))
            print("TIMES", toolkit.getTimesForElement(id))
            print("STAFF", toolkit.getElementAttr(id, "staff"), "PNAME", toolkit.getElementAttr(id, "pname"))
            print("NOTATED", toolkit.getNotatedIdForElement(id))
        }
        print("LOG", toolkit.getLog().prefix(300))
    }
}
