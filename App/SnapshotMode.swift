import AppKit
import DesignSystem
import Library
import SwiftUI

/// Development aid: renders the app's screens to PNG files and quits, so their look can be
/// reviewed without operating the app.
///
///     Midiot -snapshot <output folder> [-snapshotSong <file> ...] [-snapshotBeat <beat>]
///
/// Songs are imported into a throwaway library inside the output folder, never the real one.
@MainActor
enum SnapshotMode {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "-snapshot"), arguments.indices.contains(flag + 1) else { return }
        let folder = URL(fileURLWithPath: arguments[flag + 1])
        let songs = arguments.indices
            .filter { arguments[$0] == "-snapshotSong" && arguments.indices.contains($0 + 1) }
            .map { URL(fileURLWithPath: arguments[$0 + 1]) }
        let beat = arguments.firstIndex(of: "-snapshotBeat").flatMap { Double(arguments[$0 + 1]) } ?? 0

        Task { @MainActor in
            await run(folder: folder, songs: songs, beat: beat)
            exit(0)
        }
    }

    private static func run(folder: URL, songs: [URL], beat: Double) async {
        let storeRoot = folder.appendingPathComponent("library")
        try? FileManager.default.removeItem(at: storeRoot)
        let model = AppModel(store: SongStore(root: storeRoot))
        model.start()

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
        }

        model.closeSong()
        model.section = .settings
        save(RootView(), model: model, to: folder.appendingPathComponent("settings.png"))
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
