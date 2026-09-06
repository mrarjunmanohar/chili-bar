import Foundation
import ServiceManagement

/// Wraps `SMAppService` registration for starting Chili Bar at login.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when macOS has the registration but the user has switched it off in
    /// System Settings → General → Login Items. Toggling it on from here won't override that,
    /// so the UI has to say where to go instead of silently failing.
    static var needsUserApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Login items are registered by bundle path. Registering a build sitting in the repo's
    /// `dist/` would pin login to a path that gets deleted on the next build.
    static var isInApplicationsFolder: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
