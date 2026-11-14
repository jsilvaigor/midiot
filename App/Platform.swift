import SwiftUI

/// The few places where the Mac and the iPad differ.
enum Platform {
    #if os(macOS)
    static let isPad = false
    static let willTerminate = NSApplication.willTerminateNotification
    /// Shift held right now, for extending a selection with a click.
    @MainActor static var isShiftDown: Bool { NSEvent.modifierFlags.contains(.shift) }
    /// What the user calls this device, for naming a play kept as a copy.
    @MainActor static var deviceName: String { Host.current().localizedName ?? "Mac" }
    #else
    static let isPad = true
    static let willTerminate = UIApplication.willTerminateNotification
    @MainActor static var isShiftDown: Bool { false }
    @MainActor static var deviceName: String { UIDevice.current.name }
    #endif

    /// A control height: as designed on the Mac, at least a fingertip on the iPad.
    static func touch(_ height: CGFloat) -> CGFloat { isPad ? max(height, 44) : height }
}
