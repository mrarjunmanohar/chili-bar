import SwiftUI
import ChiliBarCore

/// Everything the panel needs to draw itself, so the view stays free of app wiring.
struct PanelState {
    let phase: PomodoroTimer.Phase
    let isPaused: Bool
    let countdown: String
    let completedSessions: Int
    let currentRestLength: TimeInterval?
    let rows: [ZoneRow]
    /// Set when zones.json couldn't be read. Shown rather than swallowed — the app is
    /// running on defaults at that point, and silently ignoring the file the user edited
    /// is worse than saying so.
    let configError: String?
    /// Set when macOS is refusing to deliver notifications. Shown for the same reason: a
    /// timer that has quietly stopped telling you anything is the exact failure this app
    /// was reported for.
    let notificationsBlocked: Bool
}

/// The panel shown on click: session controls on top, world clock below.
struct MenuPanelView: View {
    let state: PanelState

    var onStart: () -> Void
    var onPauseResume: () -> Void
    var onSkip: () -> Void
    var onChooseRest: (TimeInterval) -> Void
    var onEditZones: () -> Void
    var onOpenSettings: () -> Void
    var onOpenNotificationSettings: () -> Void
    var onQuit: () -> Void

    private var configError: String? { state.configError }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            session
            Divider()
            if let configError {
                configWarning(configError)
                Divider()
            }
            if state.notificationsBlocked {
                notificationWarning
                Divider()
            }
            clocks
            Divider()
            footer
        }
        .frame(width: 260)
    }

    // MARK: - Session

    @ViewBuilder
    private var session: some View {
        VStack(spacing: 10) {
            if state.phase == .idle {
                Text("Ready")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Button("Start Focus", action: onStart)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                Text(state.countdown)
                    .font(.system(size: 34, weight: .light, design: .monospaced))
                    .monospacedDigit()

                Text(phaseLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                HStack(spacing: 8) {
                    Button(state.isPaused ? "Resume" : "Pause", action: onPauseResume)
                    Button(state.phase == .work ? "Skip to Break" : "End Break", action: onSkip)
                }
                .buttonStyle(.bordered)

                // Rest length is chosen in the moment — this is that choice, offered exactly
                // when it's relevant rather than buried in settings.
                if state.phase == .rest {
                    restPicker
                }
            }

            if state.completedSessions > 0 {
                Text("\(state.completedSessions) session\(state.completedSessions == 1 ? "" : "s") today")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 14)
    }

    private var phaseLabel: String {
        if state.isPaused { return "Paused" }
        return state.phase == .work ? "Focus" : "Break"
    }

    private var restPicker: some View {
        HStack(spacing: 4) {
            ForEach(TimerSettings.restOptions, id: \.self) { option in
                let isCurrent = state.currentRestLength.map { abs($0 - option) < 1 } ?? false
                Button {
                    onChooseRest(option)
                } label: {
                    Text("\(Int(option / 60))")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 26)
                }
                .buttonStyle(.bordered)
                .tint(isCurrent ? Color.accentColor : Color.secondary)
            }
        }
    }

    private func configWarning(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Using defaults")
                    .font(.system(size: 11, weight: .medium))
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var notificationWarning: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "bell.slash.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications are off")
                    .font(.system(size: 11, weight: .medium))
                Text("Chili Bar still shows its own panel, but it can't reach you in a full-screen app.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open System Settings", action: onOpenNotificationSettings)
                    .buttonStyle(.link)
                    .font(.system(size: 10))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Clocks

    private var clocks: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(state.rows) { row in
                HStack(spacing: 8) {
                    Text(row.label)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .frame(width: 34, alignment: .leading)
                    Text(row.time)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 40, alignment: .leading)
                    Text(row.dayAndDate)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    WorkingHoursDot(isWorkingHours: row.isWorkingHours)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Settings…", action: onOpenSettings)
            Button("Reveal Config", action: onEditZones)
            Spacer()
            Button("Quit", action: onQuit)
        }
        .buttonStyle(.link)
        .font(.system(size: 11))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
