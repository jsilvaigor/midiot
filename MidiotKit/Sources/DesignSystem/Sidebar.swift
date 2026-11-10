import SwiftUI

/// "midiot" in Instrument Serif italic with the lit amber dot.
public struct Wordmark: View {
    public init() {}

    public var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 3) {
            Text(verbatim: "midiot")
                .font(.serif(32, italic: true))
                .foregroundStyle(Palette.textPrimary)
            Circle()
                .fill(Palette.accent)
                .frame(width: 7, height: 7)
                .filamentGlow(radius: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Midiot"))
    }
}

/// Group heading in the sidebar ("Learn", "Create").
public struct SidebarHeading: View {
    private let title: LocalizedStringKey

    public init(_ title: LocalizedStringKey) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .capsLabel()
            .padding(.horizontal, 12)
            .padding(.bottom, Spacing.xs)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One navigation row. The selected row is tinted and carries a small lit dot.
public struct SidebarItem: View {
    private let title: LocalizedStringKey
    private let systemImage: String
    private let isSelected: Bool
    private let action: () -> Void

    public init(
        _ title: LocalizedStringKey,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(isSelected ? Palette.accent : Palette.textSecondary)
                    .frame(width: 20)
                Text(title)
                    .font(.sans(14, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
                Spacer(minLength: 0)
                if isSelected {
                    Circle()
                        .fill(Palette.accent)
                        .frame(width: 5, height: 5)
                        .filamentGlow(radius: 4)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(
                isSelected ? Palette.accentSoft : .clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A keyboard or controller shown in the sidebar's status card.
public struct DeviceStatus: Identifiable {
    public let id: String
    public let name: String
    /// Role and size, already localized: "Instrument · 49 keys".
    public let detail: String
    public let isConnected: Bool

    public init(id: String, name: String, detail: String, isConnected: Bool) {
        self.id = id
        self.name = name
        self.detail = detail
        self.isConnected = isConnected
    }
}

/// Card at the bottom of the sidebar listing connected keyboards (HW-4).
public struct DeviceStatusCard: View {
    private let title: LocalizedStringKey
    private let emptyMessage: LocalizedStringKey
    private let devices: [DeviceStatus]

    public init(title: LocalizedStringKey, emptyMessage: LocalizedStringKey, devices: [DeviceStatus]) {
        self.title = title
        self.emptyMessage = emptyMessage
        self.devices = devices
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).capsLabel()
            if devices.isEmpty {
                HStack(spacing: 10) {
                    StatusDot(isOn: false)
                    Text(emptyMessage)
                        .font(.sans(13))
                        .foregroundStyle(Palette.textSecondary)
                }
            } else {
                ForEach(devices) { device in
                    HStack(spacing: 10) {
                        StatusDot(isOn: device.isConnected)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: device.name)
                                .font(.sans(13, weight: .medium))
                                .foregroundStyle(device.isConnected ? Palette.textPrimary : Palette.textSecondary)
                            Text(verbatim: device.detail)
                                .font(.sans(12))
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.hairline))
    }
}

/// Green lit dot for a connected device, hollow ring otherwise.
public struct StatusDot: View {
    private let isOn: Bool

    public init(isOn: Bool) {
        self.isOn = isOn
    }

    public var body: some View {
        Group {
            if isOn {
                Circle()
                    .fill(Palette.noteCorrect)
                    .filamentGlow(Palette.noteCorrect, radius: 4)
            } else {
                Circle()
                    .strokeBorder(Palette.textTertiary, lineWidth: 1.5)
            }
        }
        .frame(width: 7, height: 7)
        .accessibilityHidden(true)
    }
}
