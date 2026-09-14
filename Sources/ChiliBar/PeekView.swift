import SwiftUI

/// What the peek popover is currently showing.
///
/// One popover serves both because AppKit leaves the old window on screen when you swap the
/// `contentViewController` of a visible `NSPopover`, and a freshly allocated `NSPopover` is
/// orphaned with nothing holding a reference to close it. Switching on an enum inside a
/// single `rootView` sidesteps both.
enum PeekContent {
    case zones([ZoneRow])
    case alert(SessionAlert)
}

struct PeekView: View {
    let content: PeekContent

    var onChooseRest: (TimeInterval) -> Void = { _ in }
    var onStart: () -> Void = {}
    var onDismiss: () -> Void = {}

    var body: some View {
        switch content {
        case .zones(let rows):
            HoverPanelView(rows: rows)
        case .alert(let alert):
            SessionAlertView(
                alert: alert,
                onChooseRest: onChooseRest,
                onStart: onStart,
                onDismiss: onDismiss
            )
        }
    }
}
