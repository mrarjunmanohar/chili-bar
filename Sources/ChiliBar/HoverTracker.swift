import AppKit

/// Reports mouse enter/exit on the status item button.
///
/// **Must subclass `NSResponder`, not `NSObject`.** An `NSTrackingArea` owner that isn't a
/// responder never receives `mouseEntered(with:)` — the compiler reports it as "method does not
/// override any method from its superclass", which reads like a typo rather than the real cause.
final class HoverTracker: NSResponder {
    private let onEnter: () -> Void
    private let onExit: () -> Void

    init(onEnter: @escaping () -> Void, onExit: @escaping () -> Void) {
        self.onEnter = onEnter
        self.onExit = onExit
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Attaches to a view and keeps tracking correct as the status item resizes.
    func attach(to view: NSView) {
        for existing in view.trackingAreas {
            view.removeTrackingArea(existing)
        }
        view.addTrackingArea(
            NSTrackingArea(
                rect: view.bounds,
                // .inVisibleRect keeps the area in step with the button's changing width.
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) { onEnter() }
    override func mouseExited(with event: NSEvent) { onExit() }
}
