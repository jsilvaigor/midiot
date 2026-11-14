import Foundation
import Observation
import Sketch

/// Keeps plays in iCloud so the Mac and the iPad show the same ones.
///
/// The system moves the files. This watches the folder: it fetches plays another device made,
/// and when one play was changed in two places before they could sync, keeps the version
/// iCloud chose and saves the other as a separate play.
@MainActor
@Observable
final class CloudPlays {
    enum Status: Equatable {
        case checking
        /// Not signed in to iCloud, or the app was built without iCloud access.
        case unavailable
        /// - Parameter fetching: plays still on their way to this device.
        case on(fetching: Int)
    }

    private(set) var status = Status.checking

    @ObservationIgnored private var store: PlayStore?
    @ObservationIgnored private var query: NSMetadataQuery?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var onChange: () -> Void = {}
    @ObservationIgnored private var isSettling = false
    @ObservationIgnored private var settleAgain = false

    /// Looks for the iCloud folder and, when there is one, moves the plays kept on this
    /// device into it.
    /// - Parameters:
    ///   - deviceName: added to the title of a play that had to be kept as a copy.
    ///   - otherDeviceName: the same, when the copy came from a device whose name is unknown.
    ///   - onReady: called once with the store to use from now on.
    ///   - onChange: called whenever the plays may have changed underneath the app.
    func start(
        local: PlayStore, deviceName: String, otherDeviceName: String,
        onReady: @escaping (PlayStore) -> Void, onChange: @escaping () -> Void
    ) {
        guard store == nil else { return }
        self.onChange = onChange
        self.otherDeviceName = otherDeviceName
        Task {
            let cloud = await Task.detached(priority: .utility) { () -> PlayStore? in
                guard let cloud = PlayStore.cloud() else { return nil }
                try? FileManager.default.createDirectory(at: cloud.root, withIntermediateDirectories: true)
                _ = try? local.adopt(into: cloud) { "\($0.title) (\(deviceName))" }
                return cloud
            }.value
            guard let cloud else {
                status = .unavailable
                return
            }
            store = cloud
            status = .on(fetching: 0)
            onReady(cloud)
            watch()
            settle()
        }
    }

    @ObservationIgnored private var otherDeviceName = ""

    private func watch() {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*.json'", NSMetadataItemFSNameKey)
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.settle() }
            })
        }
        query.start()
        self.query = query
    }

    /// Fetches what is missing, settles conflicts, and tells the app to look again.
    private func settle() {
        guard let store else { return }
        guard !isSettling else {
            settleAgain = true
            return
        }
        isSettling = true
        let other = otherDeviceName
        Task {
            let fetching = await Task.detached(priority: .utility) { () -> Int in
                store.resolveConflicts { play, device in "\(play.title) (\(device ?? other))" }
                return store.requestDownloads()
            }.value
            status = .on(fetching: fetching)
            onChange()
            isSettling = false
            if settleAgain {
                settleAgain = false
                settle()
            }
        }
    }
}
