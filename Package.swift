// swift-tools-version:5.9
import PackageDescription

// No .package(url:) entries — Chili Bar has zero third-party dependencies by design.
let package = Package(
    name: "ChiliBar",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic. Must never import AppKit — that boundary is what keeps it testable.
        .target(name: "ChiliBarCore", path: "Sources/ChiliBarCore"),
        // AppKit + SwiftUI shell. Run as a bundled .app, never straight out of .build/ —
        // LSUIElement and notification registration both need a real Info.plist.
        .executableTarget(
            name: "ChiliBar",
            dependencies: ["ChiliBarCore"],
            path: "Sources/ChiliBar"
        ),
        .testTarget(
            name: "ChiliBarCoreTests",
            dependencies: ["ChiliBarCore"],
            path: "Tests/ChiliBarCoreTests"
        ),
    ]
)
