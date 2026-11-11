import SwiftUI

/// Segmented control: a row of options with the chosen one raised.
public struct SegmentedControl<Value: Hashable>: View {
    public struct Option {
        let value: Value
        let title: LocalizedStringKey
        let dot: Color?

        public init(_ value: Value, _ title: LocalizedStringKey, dot: Color? = nil) {
            self.value = value
            self.title = title
            self.dot = dot
        }
    }

    @Binding private var selection: Value
    private let options: [Option]

    public init(selection: Binding<Value>, options: [Option]) {
        _selection = selection
        self.options = options
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let isOn = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    HStack(spacing: 7) {
                        if let dot = option.dot {
                            Circle().fill(dot).frame(width: 7, height: 7)
                        }
                        Text(option.title)
                            .font(.sans(13, weight: isOn ? .medium : .regular))
                            .foregroundStyle(isOn ? Palette.textPrimary : Palette.textSecondary)
                            .fixedSize()
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(isOn ? Palette.control : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Palette.surfaceRaised.opacity(0.7), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Palette.hairline))
    }
}

/// Square button with a single icon, used in headers and the transport bar.
public struct IconButton: View {
    private let systemImage: String
    private let label: LocalizedStringKey
    private let size: CGFloat
    private let action: () -> Void

    public init(systemImage: String, label: LocalizedStringKey, size: CGFloat = 44, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.36, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: size, height: size)
                .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).strokeBorder(Palette.hairline))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// The round amber play/pause button: the one primary action on the practice screen.
public struct PlayButton: View {
    private let isPlaying: Bool
    private let label: LocalizedStringKey
    private let action: () -> Void

    /// - Parameter label: spoken name of the action, such as "Play" or "Pause".
    public init(isPlaying: Bool, label: LocalizedStringKey, action: @escaping () -> Void) {
        self.isPlaying = isPlaying
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Palette.accentInk)
                .frame(width: 52, height: 52)
                .background(Palette.accent, in: Circle())
                .overlay(Circle().strokeBorder(Palette.accent.opacity(0.14), lineWidth: 4).padding(-4))
                .filamentGlow(radius: 14)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// Capsule-cornered toggle with an icon and a title; amber-tinted when on.
public struct ToggleChip: View {
    private let title: Text
    private let systemImage: String?
    private let isOn: Bool
    private let showsTitle: Bool
    private let action: () -> Void

    /// - Parameter showsTitle: false draws the icon alone; the title is then the tooltip and
    ///   the spoken label.
    public init(
        _ title: Text, systemImage: String? = nil, isOn: Bool, showsTitle: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isOn = isOn
        self.showsTitle = showsTitle
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 13, weight: .medium))
                }
                if showsTitle { title.font(.sans(13, weight: isOn ? .medium : .regular)) }
            }
            .foregroundStyle(isOn ? Palette.accentHighlight : Palette.textSecondary)
            .padding(.horizontal, showsTitle ? 14 : 12)
            .frame(height: 40)
            .background(isOn ? Palette.accentSoft : Palette.surfaceRaised.opacity(0.7),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(isOn ? Palette.accent.opacity(0.45) : Palette.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(showsTitle ? Text(verbatim: "") : title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Small rounded tag for table cells: file format, "Fits 25", and similar.
public struct Pill: View {
    public enum Tone { case neutral, blue, green, amber }

    private let title: Text
    private let tone: Tone

    public init(_ title: Text, tone: Tone = .neutral) {
        self.title = title
        self.tone = tone
    }

    public var body: some View {
        let color: Color? = switch tone {
        case .neutral: nil
        case .blue: Palette.handLeft
        case .green: Palette.noteCorrect
        case .amber: Palette.accent
        }
        title
            .font(.sans(12, weight: .medium))
            .foregroundStyle(color.map { $0.mix(with: .white, by: 0.25) } ?? Palette.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background((color ?? .clear).opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(color?.opacity(0.25) ?? Palette.hairlineStrong))
    }
}

/// Filled amber button for the main action of a screen.
public struct PrimaryButton: View {
    private let title: LocalizedStringKey
    private let systemImage: String?
    private let action: () -> Void

    public init(_ title: LocalizedStringKey, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 13, weight: .bold))
                }
                Text(title).font(.sans(14, weight: .semibold))
            }
            .foregroundStyle(Palette.accentInk)
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(Palette.accent, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            .filamentGlow(radius: 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
