import DesignSystem
import MusicCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system
    @AppStorage(NoteNamingSetting.storageKey) private var naming = NoteNaming.letters

    /// Output delay above which playing feels disconnected from the sound.
    private let noticeableDelay: TimeInterval = 0.025

    var body: some View {
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

            Section("Sound") {
                LabeledContent("Piano") { soundStatus }
                if let latency = model.latency {
                    LabeledContent("Output delay") {
                        Text("\(Int((latency.total * 1000).rounded())) ms")
                    }
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
        .background(Palette.background)
        .navigationTitle(Text("Settings"))
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
