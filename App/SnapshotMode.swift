import AppKit
import DesignSystem
import Library
import MusicCore
import Practice
import Sketch
import SwiftUI

/// Development aid: renders the app's screens to PNG files and quits, so their look can be
/// reviewed without operating the app.
///
///     Midiot -snapshot <output folder> [-snapshotSong <file> ...] [-snapshotBeat <beat>] [-snapshotLanguage pt-BR]
///
/// Songs are imported into a throwaway library inside the output folder, never the real one.
@MainActor
enum SnapshotMode {
    /// Language the screens are rendered in; nil is the system's.
    private static var language: String?

    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "-snapshot"), arguments.indices.contains(flag + 1) else { return }
        let folder = URL(fileURLWithPath: arguments[flag + 1])
        let songs = arguments.indices
            .filter { arguments[$0] == "-snapshotSong" && arguments.indices.contains($0 + 1) }
            .map { URL(fileURLWithPath: arguments[$0 + 1]) }
        language = arguments.firstIndex(of: "-snapshotLanguage").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        let beat = arguments.firstIndex(of: "-snapshotBeat").flatMap { Double(arguments[$0 + 1]) } ?? 0

        Task { @MainActor in
            await run(folder: folder, songs: songs, beat: beat)
            exit(0)
        }
    }

    private static func run(folder: URL, songs: [URL], beat: Double) async {
        let storeRoot = folder.appendingPathComponent("library")
        try? FileManager.default.removeItem(at: storeRoot)
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("Plays"))
        let model = AppModel(store: SongStore(root: storeRoot), seedsStarterSongs: false)
        model.start()

        save(RootView(), model: model, to: folder.appendingPathComponent("today-first.png"))
        model.section = .library
        save(RootView(), model: model, to: folder.appendingPathComponent("library-empty.png"))

        model.importSongs(from: songs)
        await waitUntil { model.songs.count == songs.count || model.libraryError != nil }
        save(RootView(), model: model, to: folder.appendingPathComponent("library.png"))

        if let last = model.songs.first {
            model.open(last)
            await waitUntil { model.session != nil }
            model.session?.seek(to: beat)
            try? await Task.sleep(for: .milliseconds(300))
            save(RootView(), model: model, to: folder.appendingPathComponent("practice.png"))

            // Right hand in wait mode: play one correct key and hold one wrong key.
            if let session = model.session {
                session.handMode = .right
                session.waitsForPlayer = true
                session.countInIsOn = false
                session.loopBars = 1...2
                session.seek(to: 0)
                session.togglePlay()
                try? await Task.sleep(for: .milliseconds(300))
                if let first = session.awaited.first { model.mouseDown(on: first.pitch); model.mouseUp(on: first.pitch) }
                try? await Task.sleep(for: .milliseconds(900))
                model.mouseDown(on: .middleC)
                try? await Task.sleep(for: .milliseconds(200))
                save(RootView(), model: model, to: folder.appendingPathComponent("practice-wait.png"))
                for mode in ["split", "sheet"] {
                    UserDefaults.standard.set(mode, forKey: "practiceViewMode")
                    save(RootView(), model: model, to: folder.appendingPathComponent("practice-\(mode).png"))
                }
                UserDefaults.standard.removeObject(forKey: "practiceViewMode")
                model.mouseUp(on: .middleC)
            }
        }

        // Two complete runs with deliberate mistakes, then the review of the second.
        if let session = model.session {
            session.pause()
            session.loopBars = nil
            session.handMode = .both
            session.waitsForPlayer = false
            session.rate = 1.5
            for run in 0..<2 {
                session.seek(to: 0)
                session.togglePlay()
                var played = Set<Int>()
                while session.isPlaying {
                    let beat = session.beat
                    for note in session.song.notes where !played.contains(note.id) {
                        // The left hand rushes; bar 3 goes badly, worse on the first run.
                        let lead = note.hand == .left ? 0.35 : 0.02
                        guard note.start <= beat + lead else { continue }
                        played.insert(note.id)
                        let inBar3 = note.start >= 8 && note.start < 12
                        if inBar3, note.hand == .right, note.id % (run == 0 ? 2 : 3) == 0 {
                            model.mouseDown(on: Pitch(midiNumber: note.pitch.midiNumber + 1))
                            model.mouseUp(on: Pitch(midiNumber: note.pitch.midiNumber + 1))
                        } else {
                            model.mouseDown(on: note.pitch)
                            model.mouseUp(on: note.pitch)
                        }
                    }
                    try? await Task.sleep(for: .milliseconds(8))
                }
                await waitUntil { session.review != nil }
            }
            save(RootView(), model: model, to: folder.appendingPathComponent("review.png"))
            session.startSuggestedLoop()
            try? await Task.sleep(for: .milliseconds(400))
            save(RootView(), model: model, to: folder.appendingPathComponent("review-loop.png"))
        }

        model.closeSong()
        save(RootView(), model: model, to: folder.appendingPathComponent("library-progress.png"))

        // A drill opened from the path, shown as a sheet.
        model.section = .today
        model.open(Curriculum.Step(.scale(.bFlat), .right), title: "B♭ major scale · right hand")
        await waitUntil { model.session?.loaded.entry.format == .drill }
        UserDefaults.standard.set("split", forKey: "practiceViewMode")
        model.session?.seek(to: 2)
        save(RootView(), model: model, to: folder.appendingPathComponent("drill.png"))
        UserDefaults.standard.removeObject(forKey: "practiceViewMode")
        model.closeSong()
        save(RootView(), model: model, to: folder.appendingPathComponent("today.png"))
        await sketchpad(model: model, folder: folder)

        model.section = .chords
        save(RootView(), model: model, to: folder.appendingPathComponent("chords.png"))
        model.section = .settings
        save(RootView(), model: model, to: folder.appendingPathComponent("settings.png"))
    }

    /// Builds a play, plays two takes and an overdub with the mouse, and writes every export.
    private static func sketchpad(model: AppModel, folder: URL) async {
        // The Sketchpad remembers its sound, tempo and play; put the user's back afterwards.
        let keys = ["sketchTempo", "sketchProgram", "sketchPlay"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { UserDefaults.standard.set(value, forKey: key) } }

        let sketch = model.sketchpad
        model.section = .sketchpad
        save(RootView(), model: model, to: folder.appendingPathComponent("sketchpad-empty.png"))

        sketch.newPlay(title: "A Midsummer Night’s Dream", sceneTitle: "Act I · Athens", cueName: "Overture")
        sketch.updateCue { $0.status = .ready }
        if let scene = sketch.play?.scenes.first { sketch.addCue(to: scene.id, name: "Theseus enters") }
        sketch.addScene(title: "Act III · Forest at night")
        if let scene = sketch.play?.scenes.last {
            sketch.addCue(to: scene.id, name: "Lost lovers")
            sketch.addCue(to: scene.id, name: "Forest at night")
        }
        sketch.updatePlay { $0.opensOn = Date(timeIntervalSince1970: 1_805_000_000) }
        save(RootView(), model: model, to: folder.appendingPathComponent("sketchpad-no-takes.png"))
        sketch.updateCue {
            $0.note = "Under Puck’s line “Up and down, up and down.” Fade on Lysander’s exit."
            $0.targetSeconds = 45
            $0.status = .draft
            $0.mood = .mystery
        }
        sketch.bpm = 60
        sketch.sound = .sound(program: 88)

        func play(_ numbers: [Int], milliseconds: Int) async {
            for number in numbers { model.mouseDown(on: Pitch(midiNumber: number)) }
            try? await Task.sleep(for: .milliseconds(milliseconds))
            for number in numbers { model.mouseUp(on: Pitch(midiNumber: number)) }
        }
        func phrase(_ melody: [Int]) async {
            for (index, note) in melody.enumerated() {
                // A low note under every fourth melody note.
                await play(index % 4 == 0 ? [note, [50, 45, 43, 50][index / 4 % 4]] : [note], milliseconds: 240)
                try? await Task.sleep(for: .milliseconds(10))
            }
        }

        await phrase([62, 65, 69, 72, 76, 72, 69, 65, 67, 71, 74, 77, 74, 72, 69, 65])
        sketch.keepLast(seconds: 30)
        try? await Task.sleep(for: .milliseconds(300))
        await phrase([69, 72, 76, 79, 76, 72, 69, 64, 62, 65, 69, 72, 76, 74, 72, 69])
        // Hold a chord so the app has something to name.
        for number in [50, 65, 69, 72, 76] { model.mouseDown(on: Pitch(midiNumber: number)) }
        try? await Task.sleep(for: .milliseconds(700))
        sketch.keepLast(seconds: 8)
        if let id = sketch.selectedTakeID { sketch.toggleKeeper(id) }

        // A second layer of slow strings over the keeper.
        sketch.sound = .sound(program: 48)
        sketch.overdub()
        try? await Task.sleep(for: .milliseconds(4100))
        save(RootView(), model: model, to: folder.appendingPathComponent("sketchpad-overdub.png"))
        for number in [38, 45, 43, 38] {
            guard sketch.isOverdubbing else { break }
            await play([number, number + 12], milliseconds: 900)
        }
        sketch.stop()
        sketch.quantize()
        sketch.selectedNotes = [NoteRef(layer: 0, index: 4), NoteRef(layer: 0, index: 5), NoteRef(layer: 0, index: 6)]
        // Light the keys of the first suggested chord.
        sketch.shownChord = sketch.suggestions.first?.chord
        save(RootView(), model: model, to: folder.appendingPathComponent("sketchpad.png"))

        for (format, name) in [
            (SketchpadModel.ExportFormat.midi, "cue.mid"), (.musicXML, "cue.musicxml"),
            (.pdfGrandStaff, "cue-grand-staff.pdf"), (.pdfLeadSheet, "cue-lead-sheet.pdf"),
        ] {
            let data = sketch.export(format, layerName: { "Layer \($0)" }, subtitle: "A Midsummer Night’s Dream · Cue 2B · Take 2")
            try? data?.write(to: folder.appendingPathComponent(name))
        }
        for number in [50, 65, 69, 72, 76] { model.mouseUp(on: Pitch(midiNumber: number)) }
    }

    private static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func save(_ view: some View, model: AppModel, to url: URL) {
        let size = CGSize(width: 1280, height: 800)
        let root = view
            .environment(model)
            .environment(\.locale, language.map(Locale.init(identifier:)) ?? .autoupdatingCurrent)
            .preferredColorScheme(.dark)
            .tint(Palette.accent)
            .font(.bodyText)
            .frame(width: size.width, height: size.height)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // Let SwiftUI finish its first layout and draw passes.
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}
