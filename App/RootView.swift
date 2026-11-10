import DesignSystem
import SwiftUI

/// Main window: sidebar on the left, the selected section on the right.
struct RootView: View {
    @State private var section: AppSection? = .library

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $section) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            switch section ?? .library {
            case .library:
                EmptyState(
                    systemImage: "music.note.list",
                    title: "No songs yet",
                    message: "Songs you import will appear here."
                )
            case .practice:
                PracticeView()
            case .settings:
                SettingsView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { DeviceStatusView() }
        }
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case library, practice, settings

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .library: "Library"
        case .practice: "Practice"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .library: "music.note.list"
        case .practice: "pianokeys"
        case .settings: "gearshape"
        }
    }
}
