import SwiftUI

/// Centered glyph, title and message for a screen with nothing to show yet.
public struct EmptyState: View {
    private let systemImage: String
    private let title: LocalizedStringKey
    private let message: LocalizedStringKey

    public init(systemImage: String, title: LocalizedStringKey, message: LocalizedStringKey) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: Spacing.m) {
            ZStack {
                Circle()
                    .fill(Palette.accentSoft)
                    .frame(width: 76, height: 76)
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Palette.accent)
            }
            .filamentGlow(radius: 24)
            .padding(.bottom, Spacing.xs)
            .accessibilityHidden(true)

            Text(title)
                .font(.serif(40))
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.bodyText)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FilamentBackground())
    }
}
