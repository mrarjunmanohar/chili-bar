import Foundation
import UserNotifications
import ChiliBarCore

/// Delivers the session notifications.
///
/// `UNUserNotificationCenter` needs a real bundle identifier, so this only works from the
/// assembled `.app` — running the bare binary out of `.build/` will fail to register.
///
/// Treat delivery as best-effort. Because the app is ad-hoc signed, macOS pins the grant to
/// the binary's cdhash and drops it on any rebuild, answering the next request with a flat
/// "denied" and no prompt. The panel carries its own cues for exactly that reason; these
/// notifications are the channel that reaches a full-screen app, not the only one.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Read and written on the main thread only — the authorization callbacks arrive on an
    /// arbitrary queue, so every write hops back before touching this.
    private(set) var isAuthorized = false

    /// True once permission is known to be refused, as opposed to merely not asked yet.
    ///
    /// The distinction drives what the panel says: "not asked" resolves itself, "denied"
    /// needs the user to go to System Settings.
    private(set) var isBlocked = false

    /// Called when the status changes, so the panel can redraw.
    var onAuthorizationChange: (() -> Void)?

    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            if let error {
                NSLog("Chili Bar: notification authorization failed — \(error.localizedDescription)")
            } else if !granted {
                NSLog("Chili Bar: notifications denied; the timer still runs, silently.")
            }
            self?.refreshAuthorization()
        }
    }

    /// Re-reads the live status.
    ///
    /// `requestAuthorization` is answered once at launch, but permission can be revoked or
    /// granted in System Settings at any point afterwards and nothing tells the app. Called
    /// again at the start of every session so the panel can't go stale.
    func refreshAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let status = settings.authorizationStatus
            DispatchQueue.main.async {
                guard let self else { return }
                let wasAuthorized = self.isAuthorized
                let wasBlocked = self.isBlocked
                self.isAuthorized = (status == .authorized || status == .provisional)
                self.isBlocked = (status == .denied)
                if self.isAuthorized != wasAuthorized || self.isBlocked != wasBlocked {
                    self.onAuthorizationChange?()
                }
            }
        }
    }

    func post(_ event: TimerEvent) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.sound = .default

        switch event {
        case .endingSoon(let remaining):
            content.title = "Wrapping up"
            content.body = "Break in \(minutes(remaining))."
        case .workEnded(let restLength):
            content.title = "Break time"
            content.body = "\(minutes(restLength)) — step away from the screen."
        case .restEnded:
            content.title = "Back to work"
            content.body = "Break's over."
        case .workEndedWhileAway(let endedAt):
            content.title = "Session ended"
            content.body = "Your focus session finished at \(clockTime(endedAt)). No break was started."
        }

        // nil trigger delivers immediately.
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("Chili Bar: could not post notification — \(error.localizedDescription)")
            }
        }
    }

    /// The wall-clock time the interval actually ran out — which can be hours before the
    /// app noticed, so a relative "2 minutes ago" would be a lie.
    private func clockTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func minutes(_ interval: TimeInterval) -> String {
        let count = max(1, Int(interval.rounded() / 60))
        return count == 1 ? "1 minute" : "\(count) minutes"
    }

    /// Without this, a notification raised while Chili Bar is the active app is suppressed —
    /// which is precisely when you are working and most need to see it.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
