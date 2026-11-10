import DesignSystem
import SwiftUI

struct SettingsView: View {
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system

    var body: some View {
        Form {
            Picker("Language", selection: $language) {
                Text("System").tag(AppLanguage.system)
                // Each language is shown in its own name, so these are not translated.
                Text(verbatim: "English").tag(AppLanguage.english)
                Text(verbatim: "Português").tag(AppLanguage.portuguese)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(FilamentBackground())
        .navigationTitle(Text("Settings"))
    }
}
