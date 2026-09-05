import AppKit

/// The menu bar chili, in its two session states.
///
/// Full colour means working, dimmed means resting. The design originally called for an
/// outline chili for rest, but the logo is solid pixel art — an outline of it reads as a
/// different icon rather than the same one in a different state.
///
/// Not a template image: the chili is the brand, and template rendering would flatten it
/// to a monochrome silhouette.
enum ChiliIcon {
    /// Menu bar icons are 16pt tall. `chili.png` and `chili@2x.png` both ship in the bundle,
    /// so AppKit picks the right representation per display.
    private static let size = NSSize(width: 16, height: 16)

    static let working: NSImage? = base()
    static let resting: NSImage? = base().map { dimmed($0, to: 0.35) }

    private static func base() -> NSImage? {
        guard let image = NSImage(named: "chili") else {
            // Only happens if the bundle was assembled without the icon resources, which is
            // silent otherwise — the session would just run with no chili at all.
            NSLog("Chili Bar: chili.png missing from the bundle; running without a session icon.")
            return nil
        }
        image.size = size
        image.isTemplate = false
        return image
    }

    /// Redraws at a lower opacity.
    ///
    /// The drawing-handler initialiser re-runs per display scale, so the dimmed version stays
    /// as crisp on Retina as the original — flattening it into a single bitmap here would
    /// bake in whatever scale happened to be current.
    private static func dimmed(_ image: NSImage, to alpha: CGFloat) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            // Pixel art: never let the compositor smooth it.
            NSGraphicsContext.current?.imageInterpolation = .none
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
            return true
        }
    }
}
