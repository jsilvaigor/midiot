import DesignSystem
import SwiftUI

@main
struct MidiotApp: App {
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system

    init() {
        Typography.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.locale, language.locale)
                .preferredColorScheme(.dark)
                .tint(Palette.accent)
                .font(.bodyText)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1280, height: 800)
    }
}
