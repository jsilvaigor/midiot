import MusicCore
import Observation
import os
import SwiftMIDIIO

/// Watches for MIDI keyboards, connects to every one that appears, and reports what is played.
///
/// Devices can be plugged in and removed at any time (requirement HW-4).
@MainActor
@Observable
public final class DeviceManager {
    /// Keyboards connected right now, in a stable order.
    public private(set) var devices: [ConnectedDevice] = []
    /// Set when MIDI could not be started; shown to the user.
    public private(set) var startError: String?

    @ObservationIgnored private let manager: MIDIManager
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private let log = Logger(subsystem: "dev.midiot.Midiot", category: "midi")

    public init() {
        manager = MIDIManager(clientName: "Midiot", model: "Midiot", manufacturer: "Midiot")
    }

    /// Starts listening.
    /// - Parameter onEvent: called for every playing gesture, on the MIDI thread, so sound can be
    ///   triggered without waiting for the main thread.
    public func start(onEvent: @escaping @Sendable (PerformanceEvent) -> Void) {
        guard !isStarted else { return }
        isStarted = true

        manager.notificationHandler = { [weak self] notification in
            switch notification {
            case .added, .removed, .setupChanged, .propertyChanged:
                Task { @MainActor in self?.refreshDevices() }
            default:
                break
            }
        }

        do {
            try manager.start()
            try manager.addInputConnection(
                to: .allOutputs,
                tag: "keyboards",
                receiver: .events { events, timeStamp, source in
                    let device = source?.device
                    let profile = DeviceProfile.matching(deviceName: device?.name ?? source?.name ?? "")
                    for event in events {
                        guard let kind = PerformanceEvent.Kind(event, padChannel: profile.padChannel) else { continue }
                        onEvent(PerformanceEvent(kind: kind, hostTime: timeStamp, deviceID: device?.uniqueID))
                    }
                }
            )
        } catch {
            startError = String(describing: error)
            log.error("MIDI failed to start: \(String(describing: error), privacy: .public)")
        }
        refreshDevices()
    }

    private func refreshDevices() {
        // A device can expose several ports (the Launchkey has two); list each device once.
        var seen = Set<Int32>()
        var found: [ConnectedDevice] = []
        for endpoint in manager.endpoints.outputs {
            let id = endpoint.device?.uniqueID ?? endpoint.uniqueID
            guard seen.insert(id).inserted else { continue }
            let name = endpoint.device?.name ?? endpoint.name
            found.append(ConnectedDevice(id: id, name: name, profile: .matching(deviceName: name)))
        }
        found.sort { ($0.name, $0.id) < ($1.name, $1.id) }
        if found != devices {
            devices = found
            log.info("Connected keyboards: \(found.map(\.name).joined(separator: ", "), privacy: .public)")
        }
    }
}
