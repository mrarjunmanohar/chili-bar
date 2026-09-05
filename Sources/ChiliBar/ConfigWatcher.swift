import Foundation

/// Watches the config files and reports when any of them changes.
///
/// Polls modification dates rather than using a `DispatchSource` file watcher. Config files get
/// saved two different ways and a single kqueue watch can only catch one of them:
///
///   - Atomic saves (write a temp file, then rename) replace the inode, so a watch on the
///     file's own descriptor goes deaf after the first save.
///   - In-place saves (truncate and rewrite) don't touch the directory, so a watch on the
///     *directory* never fires.
///
/// A two-second stat of two files costs nothing and catches both, plus deletion and recreation.
final class ConfigWatcher {
    private var timer: Timer?
    private var lastSeen: [URL: Date] = [:]

    private let files: [URL]
    private let onChange: () -> Void

    private static let pollInterval: TimeInterval = 2

    init(files: [URL], onChange: @escaping () -> Void) {
        self.files = files
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        // Seed with current state so the first poll doesn't report a spurious change.
        lastSeen = currentModificationDates()

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let current = currentModificationDates()
        guard current != lastSeen else { return }
        lastSeen = current
        onChange()
    }

    private func currentModificationDates() -> [URL: Date] {
        var dates: [URL: Date] = [:]
        for file in files {
            let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
            // A missing file simply has no entry, so deletion and recreation both register.
            if let modified = attributes?[.modificationDate] as? Date {
                dates[file] = modified
            }
        }
        return dates
    }
}
