import AppKit
import Foundation
import SwiftUI
import Testing
import VerovioToolkit
@testable import Notation

/// Engraves the fixture with Verovio and checks the native scene built from it.
/// With SNAPSHOT_OUT set to a folder, also writes `score.png` there for visual review.
@Suite struct ScoreSceneTests {
    @MainActor @Test func renderNatively() throws {
        let url = try #require(Bundle.module.url(forResource: "two-hands", withExtension: "musicxml", subdirectory: "Fixtures"))
        let data = try #require(VerovioResources.bundle.url(forResource: "data", withExtension: nil))
        let toolkit = VerovioToolkit(data.path)
        #expect(toolkit.setOptions(#"{"pageWidth": 2100, "pageHeight": 60000, "adjustPageHeight": true, "scale": 40, "breaks": "auto", "header": "none", "footer": "none", "svgViewBox": true}"#))
        #expect(toolkit.loadData(try String(contentsOf: url, encoding: .utf8)))

        let start = Date()
        let scene = try #require(ScoreScene(svg: toolkit.renderToSVG(1, false)))
        print("SCENE parse s", Date().timeIntervalSince(start), "shapes", scene.shapes.count, "labels", scene.labels.count, "size", scene.size)

        let notes = scene.ids(ofClass: "note")
        let measures = scene.ids(ofClass: "measure").sorted { scene.frames[$0]!.minX < scene.frames[$1]!.minX }
        print("NOTES", notes.count, "MEASURES", measures.map { scene.frames[$0]!.integral })
        #expect(notes.count == 25)
        #expect(measures.count == 4)

        // Element ids are generated per load, so pick the two leftmost notes from the scene.
        let leftmost = notes.sorted { (scene.frames[$0]!.minX, scene.frames[$0]!.minY) < (scene.frames[$1]!.minX, scene.frames[$1]!.minY) }
        let first = leftmost[0], second = leftmost[4]
        for attribute in ["pname", "oct", "staff", "dur"] {
            print("ATTR", attribute, toolkit.getElementAttr(first, attribute).replacingOccurrences(of: "\n", with: " "))
        }
        print("MIDI", toolkit.getMIDIValuesForElement(first).replacingOccurrences(of: "\n", with: " "))
        print("TIMES", toolkit.getTimesForElement(first).replacingOccurrences(of: "\n", with: " "))

        guard let out = ProcessInfo.processInfo.environment["SNAPSHOT_OUT"] else { return }
        // Light ink on charcoal, two notes colored, one bar shaded: what the practice view needs.
        let colors = [first: Color(red: 0.37, green: 0.83, blue: 0.60), second: Color(red: 0.94, green: 0.38, blue: 0.36)]
        let bar = scene.frames[measures[1]]!
        let view = ZStack(alignment: .topLeading) {
            Color(red: 0.05, green: 0.05, blue: 0.06)
            Rectangle().fill(Color.orange.opacity(0.12))
                .frame(width: bar.width, height: bar.height).offset(x: bar.minX, y: bar.minY)
            ScoreCanvas(scene: scene, ink: Color(red: 0.95, green: 0.94, blue: 0.91), noteColors: colors)
        }
        .frame(width: scene.size.width, height: scene.size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: out).appendingPathComponent("score.png"))
    }
}
