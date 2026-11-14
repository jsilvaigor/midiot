import Foundation

// Plays kept in iCloud so the Mac and the iPad show the same ones. The system moves the files;
// this is what the app does around that: move in what was made before iCloud was on, fetch
// what another device made, and settle a play changed in two places at once.

public extension Play {
    /// The same play under another title, as a separate play.
    func copy(titled title: String) -> Play {
        Play(title: title, opensOn: opensOn, createdAt: createdAt, scenes: scenes)
    }
}

public extension PlayStore {
    /// The app's folder in iCloud, or nil when the user is not signed in or the app has no
    /// iCloud access. Slow the first time: call it away from the main thread.
    static func cloud() -> PlayStore? {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
        return PlayStore(root: container.appendingPathComponent("Documents/Plays", isDirectory: true))
    }

    /// Moves every play of this store into `cloud`, for the first launch with iCloud on.
    /// A play that is already there in a different state is kept beside it as a copy, so
    /// neither device's work is lost.
    /// - Parameter copyTitle: the title for such a copy, given the play.
    /// - Returns: how many plays were moved or copied.
    @discardableResult
    func adopt(into cloud: PlayStore, copyTitle: (Play) -> String) throws -> Int {
        var moved = 0
        for play in plays() {
            if let existing = cloud.play(play.id) {
                if existing != play {
                    try cloud.save(play.copy(titled: copyTitle(play)))
                    moved += 1
                }
            } else {
                try cloud.save(play)
                moved += 1
            }
            try delete(play)
        }
        return moved
    }

    /// Starts fetching plays that are in iCloud but not on this device yet.
    /// - Returns: how many are still on their way.
    @discardableResult
    func requestDownloads() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey]
        )) ?? []
        var pending = 0
        for file in files {
            // A play not fetched yet shows up as a hidden ".name.json.icloud" stand-in, or as
            // the file itself marked not current.
            let isStandIn = file.pathExtension == "icloud"
            let status = try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus
            guard isStandIn || (file.pathExtension == "json" && status != nil && status != .current) else { continue }
            try? FileManager.default.startDownloadingUbiquitousItem(at: file)
            pending += 1
        }
        return pending
    }

    /// Settles plays that were changed on two devices before they could sync: the version
    /// iCloud chose stays, and every other version becomes a separate play.
    /// - Parameter copyTitle: the title for such a play, given the losing version and the
    ///   name of the device it came from, when known.
    /// - Returns: how many copies were made.
    @discardableResult
    func resolveConflicts(copyTitle: (Play, String?) -> String) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var copies = 0
        for file in files where file.pathExtension == "json" {
            guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: file), !versions.isEmpty else { continue }
            let current = play(UUID(uuidString: file.deletingPathExtension().lastPathComponent) ?? UUID())
            for version in versions {
                if let data = try? Data(contentsOf: version.url),
                   let other = try? Self.decoder.decode(Play.self, from: data), other != current {
                    try? save(other.copy(titled: copyTitle(other, version.localizedNameOfSavingComputer)))
                    copies += 1
                }
                version.isResolved = true
            }
            try? NSFileVersion.removeOtherVersionsOfItem(at: file)
        }
        return copies
    }
}
