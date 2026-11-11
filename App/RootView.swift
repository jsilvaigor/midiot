import DesignSystem
import SwiftUI

/// Main window: sidebar on the left, the selected section on the right.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView(selection: $model.section, devices: deviceStatuses)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            switch model.section {
            case .today:
                TodayView()
            case .library:
                LibraryView()
            case .practice:
                PracticeView()
            case .chords:
                ChordsView()
            case .sketchpad:
                SketchpadView(model: model.sketchpad)
            case .settings:
                SettingsView()
            }
        }
    }
}

extension RootView {
    /// Connected keyboards in the form the sidebar card shows them.
    private var deviceStatuses: [DeviceStatus] {
        model.devices.devices.map { device in
            let keys = LocalizedStringResource("\(device.profile.range.keyCount) keys", locale: locale)
            return DeviceStatus(id: String(device.id), name: device.name, detail: String(localized: keys), isConnected: true)
        }
    }
}

/// Wordmark, navigation groups and the connected-devices card.
struct SidebarView: View {
    @Binding var selection: AppSection
    let devices: [DeviceStatus]

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Wordmark()
                .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 2) {
                SidebarHeading("Learn")
                item(.today)
                item(.library)
                item(.practice)
                item(.chords)
            }

            VStack(alignment: .leading, spacing: 2) {
                SidebarHeading("Create")
                item(.sketchpad)
            }

            VStack(alignment: .leading, spacing: 2) {
                item(.settings)
            }

            Spacer(minLength: Spacing.l)

            DeviceStatusCard(
                title: "Connected",
                emptyMessage: "No keyboard yet",
                devices: devices
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.sidebar)
    }

    private func item(_ section: AppSection) -> some View {
        SidebarItem(
            section.title,
            systemImage: section.systemImage,
            isSelected: selection == section
        ) {
            selection = section
        }
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case today, library, practice, chords, sketchpad, settings

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .today: "Today"
        case .library: "Library"
        case .practice: "Practice"
        case .chords: "Chords"
        case .sketchpad: "Sketchpad"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "calendar"
        case .library: "music.note.list"
        case .practice: "pianokeys"
        case .chords: "square.grid.2x2"
        case .sketchpad: "waveform.path"
        case .settings: "slider.horizontal.3"
        }
    }
}
