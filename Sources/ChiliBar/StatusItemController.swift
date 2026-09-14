import AppKit
import SwiftUI
import ChiliBarCore

/// Owns the menu bar item: the rolling clock, the Pomodoro session, the hover peek and the panel.
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let formatter = ClockFormatter()
    private let notifier = Notifier()
    private let settingsWindow = SettingsWindowController()

    private var zones: [Zone] = []
    private var rotation = RotationState(zoneCount: 0)
    private var timer = PomodoroTimer()
    private var configError: String?
    /// The rest length currently running, so the picker can show which option is active.
    private var currentRestLength: TimeInterval?
    /// The alert currently on screen, if any. Held so the countdown inside it can be
    /// refreshed each second alongside the menu bar.
    private var activeAlert: SessionAlert?
    /// Pending auto-dismiss, cancelled whenever a newer alert replaces this one.
    private var pendingAlertDismiss: DispatchWorkItem?

    private var clockTimer: Timer?
    private var rotationTimer: Timer?
    /// Runs only during a session, to drive the seconds ticking down.
    private var sessionTimer: Timer?

    private var configWatcher: ConfigWatcher?
    private var hoverTracker: HoverTracker?
    private var pendingPeekClose: DispatchWorkItem?

    // One popover and one hosting controller each, reused for the life of the app.
    // Allocating a fresh NSPopover per hover orphaned the previous one — nothing held a
    // reference to close it, so it stayed on screen behind the new one.
    private lazy var peekController = NSHostingController(rootView: PeekView(content: .zones([])))
    private lazy var peekPopover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.contentViewController = peekController
        return popover
    }()

    private lazy var panelController = NSHostingController(rootView: panelView())
    private lazy var panelPopover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = panelController
        return popover
    }()

    /// Fully monospaced so letters hold their width too, not only digits.
    private let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)


    // MARK: - Lifecycle

    func start() {
        loadSettings()
        loadZones()
        configureButton()
        notifier.start()
        notifier.onAuthorizationChange = { [weak self] in self?.refreshPopovers() }
        render()
        startRotationTimer()
        scheduleNextMinuteTick()
        startWatchingConfig()
    }

    /// Applies edits to zones.json and settings.json without a relaunch.
    private func startWatchingConfig() {
        let watcher = ConfigWatcher(
            files: [ZoneStore.defaultURL, SettingsStore.defaultURL]
        ) { [weak self] in
            self?.reloadConfig()
        }
        watcher.start()
        configWatcher = watcher
    }

    private func reloadConfig() {
        configError = nil
        loadSettings()
        loadZones()
        // A shorter zone list can leave the rotation pointing past the end.
        rotation.updateZoneCount(zones.count)
        startRotationTimer()
        render()
        refreshPopovers()
        NSLog("Chili Bar: reloaded config — \(zones.count) zones\(configError.map { ", error: \($0)" } ?? "")")
    }

    private func loadSettings() {
        do {
            timer.settings = try SettingsStore.loadOrCreateDefaults(at: SettingsStore.defaultURL)
        } catch {
            // Note: reloadConfig() clears configError first, so this doesn't accumulate.
            // Defaults still give a working timer; the panel says why the file was ignored.
            configError = "settings.json: \(error.localizedDescription)"
        }
    }

    private func loadZones() {
        do {
            zones = try ZoneStore.loadOrCreateDefaults(at: ZoneStore.defaultURL)
        } catch {
            // Fall back so the app still runs, but surface the reason rather than silently
            // showing the wrong thing — or silently overwriting what the user wrote.
            zones = ZoneStore.defaultZones
            configError = "zones.json: \(error.localizedDescription)"
        }
        rotation.updateZoneCount(zones.count)
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.font = font
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(togglePanel)

        let tracker = HoverTracker(
            onEnter: { [weak self] in self?.showPeek() },
            onExit: { [weak self] in self?.schedulePeekClose() }
        )
        tracker.attach(to: button)
        hoverTracker = tracker
    }

    // MARK: - Rendering

    private func render(at date: Date = Date()) {
        guard let button = statusItem.button else { return }

        switch timer.phase {
        case .idle:
            // No chili while idle — its presence is the signal that a session is live.
            button.image = nil
            renderClock(on: button, at: date)
        case .work:
            button.image = ChiliIcon.working
            renderCountdown(on: button, at: date)
        case .rest:
            button.image = ChiliIcon.resting
            renderCountdown(on: button, at: date)
        }
    }

    private func renderClock(on button: NSStatusBarButton, at date: Date) {
        let labels = formatter.paddedMenuBarLabels(for: zones, at: date)
        guard !labels.isEmpty else {
            button.title = "Chili Bar"
            statusItem.length = NSStatusItem.variableLength
            return
        }

        button.title = labels[min(rotation.index, labels.count - 1)]
        pinWidth(to: labels, iconWidth: 0)
    }

    private func renderCountdown(on button: NSStatusBarButton, at date: Date) {
        let text = CountdownFormatter.string(for: timer.remaining(at: date))
        button.title = text
        // Countdown strings are zero-padded and fixed length, so one sample pins the width.
        pinWidth(to: [text], iconWidth: 20)
    }

    /// Pins the item to the width of the widest label.
    ///
    /// Padding the strings alone isn't enough — the item would still be measured per title.
    /// Fixing the length is what stops every icon to the left of ours shifting.
    private func pinWidth(to labels: [String], iconWidth: CGFloat) {
        let widest = labels
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        statusItem.length = ceil(widest) + 12 + iconWidth
    }

    // MARK: - Timers

    /// Fires on the real minute boundary and reschedules from there.
    ///
    /// A plain 60-second repeat would drift away from the system clock and leave the bar
    /// showing a stale minute for up to a minute.
    private func scheduleNextMinuteTick() {
        let now = Date()
        guard let nextMinute = Calendar.current.nextDate(
            after: now,
            matching: DateComponents(second: 0),
            matchingPolicy: .nextTime
        ) else { return }

        let timer = Timer(fire: nextMinute, interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.render()
            self.refreshPopovers()
            self.scheduleNextMinuteTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    private func startRotationTimer() {
        rotationTimer?.invalidate()
        let rotationTimer = Timer(timeInterval: timer.settings.rotationSeconds, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Rotation is paused during a session, so this is a no-op then.
            self.rotation.advance()
            if self.timer.phase == .idle {
                self.render()
            }
        }
        RunLoop.main.add(rotationTimer, forMode: .common)
        self.rotationTimer = rotationTimer
    }

    /// One-second ticking, alive only while a session is.
    private func startSessionTimer() {
        guard sessionTimer == nil else { return }
        let sessionTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.sessionTick()
        }
        RunLoop.main.add(sessionTimer, forMode: .common)
        self.sessionTimer = sessionTimer
    }

    private func stopSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = nil
    }

    private func sessionTick() {
        let now = Date()
        for event in timer.tick(at: now) {
            handle(event, at: now)
        }
        syncSessionState()
        render(at: now)
        refreshPopovers()
    }

    /// Everything a transition should do: notify, update state, and put it on screen.
    ///
    /// The panel is not a fallback for the notification — both fire. A notification reaches
    /// you in another full-screen app, where the menu bar isn't drawn at all; the panel
    /// reaches you when notifications are refused, silenced by a Focus mode, or just missed.
    private func handle(_ event: TimerEvent, at now: Date) {
        notifier.post(event)

        switch event {
        case .endingSoon:
            present(SessionAlert(
                kind: .endingSoon,
                countdown: CountdownFormatter.string(for: timer.remaining(at: now)),
                restOption: nil
            ))
        case .workEnded(let restLength):
            currentRestLength = restLength
            present(SessionAlert(
                kind: .breakStarted,
                countdown: CountdownFormatter.string(for: restLength),
                restOption: restLength
            ))
        case .restEnded:
            present(SessionAlert(kind: .breakEnded, countdown: "", restOption: nil))
        case .workEndedWhileAway:
            currentRestLength = nil
            present(SessionAlert(kind: .endedWhileAway, countdown: "", restOption: nil))
        }
    }

    /// Keeps the rotation and the session timer in step with the phase.
    private func syncSessionState() {
        switch timer.phase {
        case .idle:
            currentRestLength = nil
            rotation.resume()
            stopSessionTimer()
        case .work, .rest:
            // The countdown owns the status item while a session runs.
            rotation.pause()
            startSessionTimer()
        }
    }

    // MARK: - Peek and panel

    private func rows(at date: Date = Date()) -> [ZoneRow] {
        zones.map { zone in
            ZoneRow(
                label: zone.label,
                time: formatter.time(in: zone, at: date),
                dayAndDate: formatter.dayAndDate(in: zone, at: date),
                isWorkingHours: zone.isWorkingHours(at: date)
            )
        }
    }

    private func panelState(at date: Date = Date()) -> PanelState {
        PanelState(
            phase: timer.phase,
            isPaused: timer.isPaused,
            countdown: CountdownFormatter.string(for: timer.remaining(at: date)),
            completedSessions: timer.completedWorkSessions,
            currentRestLength: currentRestLength,
            rows: rows(at: date),
            configError: configError,
            notificationsBlocked: notifier.isBlocked
        )
    }

    private func panelView(at date: Date = Date()) -> MenuPanelView {
        MenuPanelView(
            state: panelState(at: date),
            onStart: { [weak self] in self?.startWork() },
            onPauseResume: { [weak self] in self?.togglePause() },
            onSkip: { [weak self] in self?.skip() },
            onChooseRest: { [weak self] in self?.chooseRest($0) },
            onEditZones: { [weak self] in self?.openConfigFile() },
            onOpenSettings: { [weak self] in self?.openSettings() },
            onOpenNotificationSettings: { [weak self] in self?.openNotificationSettings() },
            onQuit: { NSApp.terminate(nil) }
        )
    }

    private func peekView(content: PeekContent) -> PeekView {
        PeekView(
            content: content,
            onChooseRest: { [weak self] in self?.chooseRest($0) },
            onStart: { [weak self] in self?.startWork() },
            onDismiss: { [weak self] in self?.dismissAlert() }
        )
    }

    /// How long a transition alert stays up before getting out of the way.
    ///
    /// Long enough to read and act on from across the desk, short enough that it isn't a
    /// dialog you have to dismiss. The one alert that doesn't auto-dismiss is the
    /// slept-through one — that's the message the user demonstrably missed.
    private static let alertDuration: TimeInterval = 10

    private func present(_ alert: SessionAlert) {
        pendingPeekClose?.cancel()
        pendingPeekClose = nil
        pendingAlertDismiss?.cancel()
        pendingAlertDismiss = nil

        activeAlert = alert

        // The click panel already shows the countdown and the picker; stacking the alert on
        // top of it would only cover what the user deliberately opened. The alert is still
        // recorded so the panel can reflect it, and still expires on the same schedule —
        // returning early here would strand activeAlert set, which blocks hover for good.
        if !panelPopover.isShown, let button = statusItem.button {
            peekController.rootView = peekView(content: .alert(alert))
            if !peekPopover.isShown {
                peekPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }

        guard alert.dismissesAutomatically else { return }
        let work = DispatchWorkItem { [weak self] in self?.dismissAlert() }
        pendingAlertDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.alertDuration, execute: work)
    }

    /// Closes an alert the user has acknowledged, or that has had its time.
    private func dismissAlert() {
        pendingAlertDismiss?.cancel()
        pendingAlertDismiss = nil
        activeAlert = nil
        peekPopover.close()
    }

    private func showPeek() {
        pendingPeekClose?.cancel()
        pendingPeekClose = nil

        // An alert is holding the popover. Hovering shouldn't replace the message the user
        // is being shown.
        guard activeAlert == nil else { return }

        // The panel already shows everything the peek would; stacking them looks broken.
        guard !panelPopover.isShown, !peekPopover.isShown else { return }
        guard let button = statusItem.button, !zones.isEmpty else { return }

        peekController.rootView = peekView(content: .zones(rows()))
        peekPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    /// Closes after a beat rather than immediately.
    ///
    /// The pointer crosses a few pixels of dead space between the button and the popover;
    /// closing on the instant of exit makes the panel flicker as you approach it.
    private func schedulePeekClose() {
        // Alerts close on their own schedule, not when the pointer wanders off.
        guard activeAlert == nil else { return }

        pendingPeekClose?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.peekPopover.close()
        }
        pendingPeekClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    @objc private func togglePanel() {
        pendingPeekClose?.cancel()
        // Opening the full panel supersedes the alert — everything it said is in there.
        dismissAlert()

        if panelPopover.isShown {
            panelPopover.close()
            return
        }

        guard let button = statusItem.button else { return }

        panelController.rootView = panelView()
        panelPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    /// Updates whichever popover is open so its contents stay live.
    ///
    /// Assigning `rootView` rather than replacing `contentViewController`: swapping the
    /// content controller of a *visible* NSPopover leaves the old window on screen, which
    /// showed up as a second, half-hidden peek panel stacked behind the real one.
    private func refreshPopovers() {
        if peekPopover.isShown {
            if let activeAlert {
                // Only the counting-down alerts need re-rendering; the rest are static.
                let refreshed = SessionAlert(
                    kind: activeAlert.kind,
                    countdown: activeAlert.countdown.isEmpty
                        ? ""
                        : CountdownFormatter.string(for: timer.remaining(at: Date())),
                    restOption: currentRestLength
                )
                self.activeAlert = refreshed
                peekController.rootView = peekView(content: .alert(refreshed))
            } else {
                peekController.rootView = peekView(content: .zones(rows()))
            }
        }
        if panelPopover.isShown {
            panelController.rootView = panelView()
        }
    }

    // MARK: - Session actions

    private func startWork() {
        dismissAlert()
        // Permission can be revoked between launch and now; the panel should say so.
        notifier.refreshAuthorization()
        timer.startWork(at: Date())
        currentRestLength = nil
        syncSessionState()
        render()
        refreshPopovers()
    }

    private func togglePause() {
        let now = Date()
        if timer.isPaused {
            timer.resume(at: now)
        } else {
            timer.pause(at: now)
        }
        render(at: now)
        refreshPopovers()
    }

    private func skip() {
        let now = Date()
        for event in timer.skip(at: now) {
            handle(event, at: now)
        }
        syncSessionState()
        render(at: now)
        refreshPopovers()
    }

    private func chooseRest(_ length: TimeInterval) {
        dismissAlert()
        let now = Date()
        timer.startRest(length: length, at: now)
        currentRestLength = length
        syncSessionState()
        render(at: now)
        refreshPopovers()
    }

    private func openSettings() {
        panelPopover.close()
        settingsWindow.show(
            settings: timer.settings,
            zones: zones
        ) { [weak self] settings, zones in
            // Written to the same files a hand-edit would touch, so both routes agree and the
            // file watcher reloads the app either way.
            try SettingsStore.save(settings, to: SettingsStore.defaultURL)
            try ZoneStore.save(zones, to: ZoneStore.defaultURL)
            self?.reloadConfig()
        }
    }

    /// Deep-links straight to the Notifications pane rather than the top of System Settings.
    private func openNotificationSettings() {
        panelPopover.close()
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Zones

    private func openConfigFile() {
        // Ensure both files exist before revealing them, or Finder opens an empty folder.
        _ = try? ZoneStore.loadOrCreateDefaults(at: ZoneStore.defaultURL)
        _ = try? SettingsStore.loadOrCreateDefaults(at: SettingsStore.defaultURL)
        NSWorkspace.shared.activateFileViewerSelecting([
            ZoneStore.defaultURL,
            SettingsStore.defaultURL,
        ])
    }
}
