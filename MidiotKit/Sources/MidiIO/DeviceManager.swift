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
    /// DAW ports of the Launchkeys whose pads the app is lighting.
    @ObservationIgnored private var lightPorts: Set<Int32> = []
    @ObservationIgnored private var wantedLights: [Int: PadLight] = [:]
    /// What each pad was last told; a pad missing here has not been told anything yet.
    @ObservationIgnored private var sentLights: [Int: PadLight?] = [:]
    @ObservationIgnored private let log = Logger(subsystem: "dev.midiot.Midiot", category: "midi")

    public init() {
        manager = MIDIManager(clientName: "Midiot", model: "Midiot", manufacturer: "Midiot")
    }

    /// Starts listening.
    /// - Parameter onEvent: called for every playing gesture, on the MIDI thread, so sound can be
    ///   triggered without waiting for the main thread.
    /// - Parameter onControl: called for every pad and knob gesture, also on the MIDI thread.
    public func start(
        onEvent: @escaping @Sendable (PerformanceEvent) -> Void,
        onControl: @escaping @Sendable (ControlEvent) -> Void = { _ in }
    ) {
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
                receiver: .events { [weak self] events, timeStamp, source in
                    let device = source?.device
                    let profile = DeviceProfile.matching(deviceName: device?.name ?? source?.name ?? "")
                    // The Launchkey's DAW port reports its buttons and knobs; nothing on it is playing.
                    let isDAWPort = profile.model == .launchkeyMiniMK3 && LaunchkeyLights.isDAWPort(name: source?.name ?? "")
                    for event in events {
                        if isDAWPort {
                            if case let .cc(cc) = event, cc.controller.number == LaunchkeyLights.padModeController, cc.channel == 15 {
                                // The pads changed layout; their lights need sending again.
                                Task { @MainActor in self?.padLayoutChanged(to: Int(cc.value.midi1Value)) }
                            } else if case .cc = event, let control = ControlEvent(event, padChannel: nil, deviceID: device?.uniqueID) {
                                onControl(control)
                            } else if let control = LaunchkeyLights.padPress(event, deviceID: device?.uniqueID) {
                                // In DAW mode the Mini reports its drum pads here, not on the keyboard port.
                                onControl(control)
                            }
                        } else if let kind = PerformanceEvent.Kind(event, padChannel: profile.padChannel) {
                            onEvent(PerformanceEvent(kind: kind, hostTime: timeStamp, deviceID: device?.uniqueID))
                        } else if let control = ControlEvent(event, padChannel: profile.padChannel, deviceID: device?.uniqueID) {
                            onControl(control)
                        }
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
        connectLights()
    }

    // MARK: Pad lights (requirement HW-2)

    /// Lights the pads: `lights` is keyed by the note each pad sends; pads left out go dark.
    /// Only the Launchkey Mini MK3 has lights the app can drive.
    public func setPadLights(_ lights: [Int: PadLight]) {
        wantedLights = lights
        sendLights()
    }

    /// Gives the pads back to the device. Call before the app quits.
    public func releasePadLights() {
        guard !lightPorts.isEmpty else { return }
        try? manager.managedOutputConnections[Self.lightsTag]?.send(events: LaunchkeyLights.leave)
        lightPorts = []
        sentLights = [:]
    }

    private static let lightsTag = "pad lights"

    /// Finds the Launchkey's DAW port and takes its pads over, whenever devices come and go.
    private func connectLights() {
        let ports = manager.endpoints.inputs.filter {
            DeviceProfile.matching(deviceName: $0.device?.name ?? $0.name).model == .launchkeyMiniMK3
                && LaunchkeyLights.isDAWPort(name: $0.name)
        }
        let ids = Set(ports.map(\.uniqueID))
        guard ids != lightPorts else { return }
        lightPorts = ids
        sentLights = [:]
        manager.remove(.outputConnection, .withTag(Self.lightsTag))
        guard !ports.isEmpty else { return }
        do {
            try manager.addOutputConnection(to: .inputs(ports), tag: Self.lightsTag)
            try manager.managedOutputConnections[Self.lightsTag]?.send(events: LaunchkeyLights.enter)
            log.info("Pad lights on: \(ports.map(\.name).joined(separator: ", "), privacy: .public)")
        } catch {
            lightPorts = []
            log.error("Pad lights failed: \(String(describing: error), privacy: .public)")
        }
        sendLights()
        // A port that has only just appeared can miss what is sent straight away; say it again
        // once it has settled.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, self.lightPorts == ids else { return }
            try? self.manager.managedOutputConnections[Self.lightsTag]?.send(events: LaunchkeyLights.enter)
            self.sentLights = [:]
            self.sendLights()
        }
    }

    private func padLayoutChanged(to layout: Int) {
        // Colours sent while another layout was showing are lost; send them all again.
        guard layout == LaunchkeyLights.drumLayout else { return }
        sentLights = [:]
        sendLights()
    }

    /// Sends only what changed since last time.
    private func sendLights() {
        guard !lightPorts.isEmpty, let connection = manager.managedOutputConnections[Self.lightsTag] else { return }
        var events: [MIDIEvent] = []
        for note in DeviceProfile.launchkeyPadNotes where sentLights[note] != .some(wantedLights[note]) {
            events += LaunchkeyLights.events(pad: note, light: wantedLights[note])
            sentLights[note] = .some(wantedLights[note])
        }
        guard !events.isEmpty else { return }
        try? connection.send(events: events)
    }
}
