import DesignSystem
import MidiIO
import MusicCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system
    @AppStorage(NoteNamingSetting.storageKey) private var naming = NoteNaming.letters

    /// Output delay above which playing feels disconnected from the sound.
    private let noticeableDelay: TimeInterval = 0.025

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("Language", selection: $language) {
                    Text("System").tag(AppLanguage.system)
                    // Each language is shown in its own name, so these are not translated.
                    Text(verbatim: "English").tag(AppLanguage.english)
                    Text(verbatim: "Português").tag(AppLanguage.portuguese)
                }
                Picker("Note names", selection: $naming) {
                    Text(verbatim: "C D E").tag(NoteNaming.letters)
                    Text(verbatim: "Dó Ré Mi").tag(NoteNaming.solfege)
                }
                Stepper(value: $model.dailyGoal, in: 5...120, step: 5) {
                    LabeledContent("Daily goal") { Text("\(Int(model.dailyGoal)) min").font(.readoutSmall) }
                }
            }

            Section("Keyboards") {
                if model.devices.devices.isEmpty {
                    Text("No keyboard connected").foregroundStyle(Palette.textSecondary)
                }
                ForEach(model.devices.devices) { device in
                    LabeledContent {
                        Text("\(device.profile.range.keyCount) keys")
                    } label: {
                        Text(verbatim: device.name)
                    }
                }
                if let error = model.devices.startError {
                    Text(verbatim: error).foregroundStyle(Palette.noteWrong)
                }
            }

            Section {
                Picker("Send to", selection: Binding(get: { model.midiOut }, set: { model.setMIDIOut($0) })) {
                    Text("Off (MIDI out)").tag(MIDIOutChoice.off)
                    Text("Other apps, as a port named Midiot").tag(MIDIOutChoice.otherApps)
                    ForEach(model.devices.destinations) { destination in
                        Text(verbatim: destination.name).tag(MIDIOutChoice.destination(id: destination.id, name: destination.name))
                    }
                    // The chosen one stays listed while it is unplugged.
                    if case let .destination(id, name) = model.midiOut, !model.devices.destinations.contains(where: { $0.id == id }) {
                        Text("\(name) (not connected)").tag(model.midiOut)
                    }
                }
                Toggle("Silence Midiot's own instruments", isOn: $model.mutesOwnSound)
                    .disabled(model.midiOut == .off)
            } header: {
                Text("MIDI out")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Everything Midiot plays is sent as well: the piano and the Sketchpad's sound on channel 1, recorded layers on channels 2 to 9, and the Stage's sounds on channels 12 and 13. The metronome is not sent.")
                    Text("A Stage cue can instead play only through MIDI out, on a channel of its own. Channels 1 to 9, 12, 13 and 16 are used by Midiot's own sounds.")
                }
                .font(.sans(12)).foregroundStyle(Palette.textSecondary)
            }

            Section {
                ForEach(ControlAction.Context.allCases, id: \.self) { context in
                    Text(ControlNames.context(context)).capsLabel().padding(.top, 6)
                    ForEach(ControlAction.allCases.filter { $0.context == context }, id: \.self) { action in
                        controlRow(action)
                    }
                }
                Button("Reset to the Launchkey defaults") { model.resetControlMap() }
            } header: {
                Text("Pads and knobs")
            } footer: {
                Text("Press Learn, then hit the pad or turn the knob to use. The same pad can do one thing while practicing and another on stage.")
                    .font(.sans(12)).foregroundStyle(Palette.textSecondary)
            }

            Section("Sound") {
                LabeledContent("Piano") { soundStatus }
                if let latency = model.latency {
                    LabeledContent("Output delay") {
                        Text("\(Int((latency.total * 1000).rounded())) ms").font(.readoutSmall)
                    }
                    LabeledContent("Timing adjustment") {
                        HStack(spacing: 12) {
                            Slider(value: $model.timingAdjustment, in: -100...200, step: 5).frame(width: 180)
                            Text("\(Int(model.timingAdjustment)) ms").font(.readoutSmall).frame(width: 64, alignment: .trailing)
                        }
                    }
                    Text("Midiot already allows for the output delay. Raise this if notes you play on time are marked late; lower it if they are marked early.")
                        .font(.sans(12))
                        .foregroundStyle(Palette.textSecondary)
                    if latency.total > noticeableDelay {
                        Label(
                            "This output adds noticeable delay. Use wired headphones or speakers for practice.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(Palette.accent)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(FilamentBackground())
        .navigationTitle(Text("Settings"))
        .onDisappear { model.learning = nil }
    }

    private func controlRow(_ action: ControlAction) -> some View {
        let isLearning = model.learning == action
        return LabeledContent {
            HStack(spacing: 12) {
                if isLearning {
                    Text(action.isContinuous ? "Turn a knob…" : "Hit a pad…").foregroundStyle(Palette.accent)
                } else if let source = model.controlMap.source(of: action) {
                    ControlNames.source(source).font(.readoutSmall)
                } else {
                    Text("Not set").foregroundStyle(Palette.textTertiary)
                }
                Button(isLearning ? "Cancel" : "Learn (control)") { model.learning = isLearning ? nil : action }
                    .frame(minWidth: 64)
                Button { model.clearControl(action) } label: { Image(systemName: "xmark") }
                    .disabled(isLearning || model.controlMap.source(of: action) == nil)
                    .help(Text("Remove"))
                    .accessibilityLabel(Text("Remove"))
            }
        } label: {
            Text(ControlNames.action(action))
        }
    }

    @ViewBuilder private var soundStatus: some View {
        switch model.soundStatus {
        case .loading:
            Text("Loading…")
        case let .ready(bank):
            if bank.isSystemFallback {
                Text("macOS built-in sounds")
            } else {
                Text(verbatim: bank.name)
            }
        case let .failed(message):
            Text(verbatim: message).foregroundStyle(Palette.noteWrong)
        }
    }
}
