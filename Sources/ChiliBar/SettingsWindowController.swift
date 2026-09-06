import AppKit
import SwiftUI
import ChiliBarCore

/// Hosts the settings window.
///
/// An `LSUIElement` app has no Dock icon and doesn't normally take focus, so opening settings
/// has to activate the app explicitly or the window appears behind whatever you were using.
final class SettingsWindowController {
    private var window: NSWindow?

    func show(
        settings: TimerSettings,
        zones: [Zone],
        onSave: @escaping (TimerSettings, [Zone]) throws -> Void
    ) {
        // Reuse the open window rather than stacking a second one.
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let view = SettingsView(
            settings: settings,
            zones: zones,
            onSave: onSave,
            onClose: { [weak self] in self?.close() }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Chili Bar Settings"
        window.contentViewController = NSHostingController(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func close() {
        window?.close()
        window = nil
    }
}
