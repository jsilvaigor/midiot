import DesignSystem
import SwiftUI

/// Toolbar item naming the connected keyboards.
struct DeviceStatusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let devices = model.devices.devices
        HStack(spacing: Spacing.s) {
            Circle()
                .fill(devices.isEmpty ? Palette.textTertiary : Palette.noteCorrect)
                .frame(width: 7, height: 7)
            if devices.isEmpty {
                Text("No keyboard connected")
            } else {
                Text(verbatim: devices.map(\.name).joined(separator: " + "))
            }
        }
        .font(.captionText)
        .foregroundStyle(devices.isEmpty ? Palette.textSecondary : Palette.textPrimary)
        .padding(.horizontal, Spacing.s)
    }
}
