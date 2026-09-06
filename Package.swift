// swift-tools-version:5.9
import PackageDescription
import Foundation

// No .package(url:) entries — Chili Bar has zero third-party dependencies by design.
var targets: [Target] = [
    // Pure logic. Must never import AppKit — that boundary is what keeps it testable.
    .target(name: "ChiliBarCore", path: "Sources/ChiliBarCore"),
    // AppKit + SwiftUI shell. Run as a bundled .app, never straight out of .build/ —
    // LSUIElement and notification registration both need a real Info.plist.
    .executableTarget(
        name: "ChiliBar",
        dependencies: ["ChiliBarCore"],
        path: "Sources/ChiliBar"
    ),
]

// The published repository ships only what someone needs to build and run Chili Bar; the test
// suite lives alongside it in development but isn't distributed. SwiftPM fails outright on a
// target whose directory is missing, so the test target is declared only when it's actually
// present — that way `swift build` works from a fresh clone and `./Scripts/test.sh` still works
// in a development checkout.
// Resolved from the manifest's own location rather than the working directory, which
// SwiftPM does not guarantee.
let testPath = "Tests/ChiliBarCoreTests"
let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
if FileManager.default.fileExists(atPath: packageDirectory.appendingPathComponent(testPath).path) {
    targets.append(
        .testTarget(name: "ChiliBarCoreTests", dependencies: ["ChiliBarCore"], path: testPath)
    )
}

let package = Package(
    name: "ChiliBar",
    platforms: [.macOS(.v13)],
    targets: targets
)
