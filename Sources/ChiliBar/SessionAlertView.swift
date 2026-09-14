import SwiftUI
import ChiliBarCore

/// A transition worth interrupting for, rendered as a big countdown under the menu bar.
///
/// This exists because notifications can't be relied on. The app is ad-hoc signed, so macOS
/// drops the grant whenever the binary changes and then refuses the next request without
/// prompting; and even when they do work, a Focus mode silences them and a full-screen app
/// hides them. The panel is the app's own channel, and it's the one that was asked for.
struct SessionAlert {
    enum Kind {
        case endingSoon
        case breakStarted
        case breakEnded
        case endedWhileAway
    }

    let kind: Kind
    /// Pre-formatted MM:SS. Empty when there's nothing counting down.
    let countdown: String
    let restOption: TimeInterval?

    var headline: String {
        switch kind {
        case .endingSoon: return "Wrapping up"
        case .breakStarted: return "Break time"
        case .breakEnded: return "Back to work"
        case .endedWhileAway: return "Session ended"
        }
    }

    var detail: String {
        switch kind {
        case .endingSoon: return "Your break is about to start."
        case .breakStarted: return "Step away from the screen."
        case .breakEnded: return "Break's over."
        case .endedWhileAway: return "Your focus session finished while you were away."
        }
    }

    /// The rest quick-pick belongs to the moment a break begins — that's the decision point.
    var showsRestPicker: Bool { kind == .breakStarted }

    /// Offer the next session where one plausibly follows.
    var showsStart: Bool { kind == .breakEnded || kind == .endedWhileAway }

    /// Everything gets out of the way on its own except the one the user already missed
    /// once — that one waits to be acknowledged.
    var dismissesAutomatically: Bool { kind != .endedWhileAway }
}

/// The big-countdown panel.
struct SessionAlertView: View {
    let alert: SessionAlert

    var onChooseRest: (TimeInterval) -> Void
    var onStart: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(alert.headline)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if !alert.countdown.isEmpty {
                Text(alert.countdown)
                    .font(.system(size: 46, weight: .light, design: .monospaced))
                    .monospacedDigit()
            }

            Text(alert.detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if alert.showsRestPicker {
                HStack(spacing: 4) {
                    ForEach(TimerSettings.restOptions, id: \.self) { option in
                        let isCurrent = alert.restOption.map { abs($0 - option) < 1 } ?? false
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

            HStack(spacing: 8) {
                if alert.showsStart {
                    Button("Start Focus", action: onStart)
                        .buttonStyle(.borderedProminent)
                }
                if !alert.dismissesAutomatically {
                    Button("Dismiss", action: onDismiss)
                        .buttonStyle(.bordered)
                }
            }
        }
        .frame(width: 220)
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
    }
}
