import Foundation

/// Shared JSON file IO for the hand-editable config files.
enum JSONFile {
    static func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    static func save<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        // Pretty-printed with stable key order because a human edits these files by hand.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    /// Loads, seeding the file with `defaults` the first time.
    ///
    /// A malformed file is *not* silently replaced — that would throw away hand-written
    /// config on a typo. The error propagates so the app can say what is wrong.
    static func loadOrCreate<T: Codable>(_ type: T.Type, defaults: @autoclosure () -> T, at url: URL) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else {
            let value = defaults()
            try save(value, to: url)
            return value
        }
        return try load(type, from: url)
    }

    /// `~/Library/Application Support/Chili Bar/<name>`
    static func applicationSupportURL(_ name: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("Chili Bar", isDirectory: true)
            .appendingPathComponent(name)
    }
}
