import AppKit

/// Entry point.
///
/// `.accessory` keeps Chili Bar out of the Dock and the ⌘-Tab switcher; `LSUIElement` in
/// Info.plist does the same at launch, before this code runs. Both are needed — the plist
/// stops the Dock icon ever appearing, this covers the running app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItemController = StatusItemController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController.start()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
