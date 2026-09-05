import Foundation
import UserNotifications
import ChiliBarCore

/// Delivers the three session notifications.
///
/// `UNUserNotificationCenter` needs a real bundle identifier, so this only works from the
/// assembled `.app` — running the bare binary out of `.build/` will fail to register.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private var isAuthorized = false

    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            self?.isAuthorized = granted
            if let error {
                NSLog("Chili Bar: notification authorization failed — \(error.localizedDescription)")
            } else if !granted {
                NSLog("Chili Bar: notifications denied; the timer still runs, silently.")
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
