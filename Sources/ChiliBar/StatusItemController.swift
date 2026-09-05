import AppKit
import SwiftUI
import ChiliBarCore

/// Owns the menu bar item: the rolling clock, the hover peek, and the click menu.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let formatter = ClockFormatter()

    private var zones: [Zone] = []
    private var rotation = RotationState(zoneCount: 0)
    private var configError: String?

    private var clockTimer: Timer?
    private var rotationTimer: Timer?

    private var hoverTracker: HoverTracker?
    private var popover: NSPopover?
    private var pendingPopoverClose: DispatchWorkItem?

    /// Menu bar text is fully monospaced so that letters, not just digits, hold their width.
    /// Combined with the pinned item width below, nothing in the bar can twitch mid-rotation.
    private let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    private static let rotationInterval: TimeInterval = 4

    // MARK: - Lifecycle

    func start() {
        loadZones()
        configureButton()
        buildMenu()
        render()
        startRotationTimer()
        scheduleNextMinuteTick()
    }

    private func loadZones() {
        do {
            zones = try ZoneStore.loadOrCreateDefaults(at: ZoneStore.defaultURL)
            configError = nil
        } catch {
            // Fall back so the app still runs, but surface the reason in the menu rather
            // than silently showing the wrong thing — or silently overwriting their file.
            zones = ZoneStore.defaultZones
            configError = error.localizedDescription
        }
        rotation.updateZoneCount(zones.count)
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.font = font

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

        let labels = formatter.paddedMenuBarLabels(for: zones, at: date)
        guard !labels.isEmpty else {
            button.title = "Chili Bar"
            statusItem.length = NSStatusItem.variableLength
            return
        }

        button.title = labels[min(rotation.index, labels.count - 1)]
        pinWidth(to: labels)
    }

    /// Pins the item to the width of the widest label.
    ///
    /// Padding the strings alone isn't enough — the item would still be measured per title.
    /// Fixing the length is what stops every icon to the left of ours shifting every 4 seconds.
    private func pinWidth(to labels: [String]) {
        let widest = labels
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        statusItem.length = ceil(widest) + 12
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
            self.refreshPeekIfVisible()
            self.scheduleNextMinuteTick()
        }
        // .common so ticks continue while a menu is being tracked.
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    private func startRotationTimer() {
        let timer = Timer(
            timeInterval: Self.rotationInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            self.rotation.advance()
            self.render()
        }
        RunLoop.main.add(timer, forMode: .common)
        rotationTimer = timer
    }

    // MARK: - Hover peek

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

    private func showPeek() {
        pendingPopoverClose?.cancel()
        pendingPopoverClose = nil

        // The menu already shows everything the peek would, and stacking them looks broken.
        guard statusItem.menu?.highlightedItem == nil, !(popover?.isShown ?? false) else { return }
        guard let button = statusItem.button, !zones.isEmpty else { return }

        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: HoverPanelView(rows: rows()))
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.popover = popover
    }

    /// Closes after a beat rather than immediately.
    ///
    /// The pointer crosses a few pixels of dead space between the button and the popover;
    /// closing on the instant of exit makes the panel flicker as you approach it.
    private func schedulePeekClose() {
        pendingPopoverClose?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.popover?.close()
            self?.popover = nil
        }
        pendingPopoverClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func refreshPeekIfVisible() {
        guard let popover, popover.isShown else { return }
        popover.contentViewController = NSHostingController(rootView: HoverPanelView(rows: rows()))
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let configError {
            let item = NSMenuItem(title: "Config error — using defaults", action: nil, keyEquivalent: "")
            item.toolTip = configError
            menu.addItem(item)
            menu.addItem(.separator())
        }

        for row in rows() {
            let dot = row.isWorkingHours ? "●" : "○"
            let item = NSMenuItem(
                title: "\(row.label)   \(row.time)   \(row.dayAndDate)   \(dot)",
                action: nil,
                keyEquivalent: ""
            )
            item.attributedTitle = NSAttributedString(
                string: item.title,
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)]
            )
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Edit Zones…",
            action: #selector(openConfigFile),
            keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: "Reload Zones",
            action: #selector(reloadZones),
            keyEquivalent: "r"
        ).target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Chili Bar", action: #selector(quit), keyEquivalent: "q").target = self
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Freeze the rotation so rows don't shift while the pointer is over them.
        rotation.pause()
        popover?.close()
        popover = nil
    }

    func menuDidClose(_ menu: NSMenu) {
        rotation.resume()
    }

    // MARK: - Actions

    @objc private func openConfigFile() {
        let url = ZoneStore.defaultURL
        // Ensure the file exists before revealing it, or Finder opens an empty folder.
        _ = try? ZoneStore.loadOrCreateDefaults(at: url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func reloadZones() {
        loadZones()
        render()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
