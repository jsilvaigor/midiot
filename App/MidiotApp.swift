import DesignSystem
import SwiftUI

@main
struct MidiotApp: App {
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system
    @State private var model = AppModel()

    init() {
        Typography.registerFonts()
        #if os(macOS)
        SnapshotMode.runIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.locale, language.locale)
                .preferredColorScheme(.dark)
                .tint(Palette.accent)
                .font(.bodyText)
                #if os(macOS)
                .frame(minWidth: 900, minHeight: 600)
                #endif
                .task {
                    #if os(macOS)
                    // The Dock can show a blank tile for a build run from Xcode; hand it the icon.
                    let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
                    // It arrives sized for a file list; ask for the large version or the Dock blurs it.
                    icon.size = NSSize(width: 512, height: 512)
                    NSApplication.shared.applicationIconImage = icon
                    #endif
                    model.start()
                }
                .onChange(of: model.devices.devices) { model.devicesChanged() }
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 800)
        #endif
    }
}
