import DesignSystem
import SwiftUI

@main
struct MidiotApp: App {
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system
    @State private var model = AppModel()

    init() {
        Typography.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.locale, language.locale)
                .preferredColorScheme(.dark)
                .tint(Palette.accent)
                .font(.bodyText)
                .frame(minWidth: 900, minHeight: 600)
                .task { model.start() }
                .onChange(of: model.devices.devices) { model.devicesChanged() }
        }
        .defaultSize(width: 1280, height: 800)
    }
}
