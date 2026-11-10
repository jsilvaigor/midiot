import SwiftUI

/// Centered icon, title and message for a screen with nothing to show yet.
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
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Palette.accent)
            Text(title)
                .font(.displayTitle)
                .foregroundStyle(Palette.textPrimary)
            Text(message)
                .font(.bodyText)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}
