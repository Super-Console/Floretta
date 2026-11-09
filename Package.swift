// swift-tools-version: 6.0

import PackageDescription

// FlorettaCore links only the toolchain Foundation module.
// Foundation is not an SPM product, so this target's dependency list stays empty:
// SwiftUI, AppKit, UIKit, and SwiftData are not linked.
// FlorettaUI depends on FlorettaCore. Core does not depend on FlorettaUI.
let package = Package(
    name: "Floretta",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "FlorettaCore", targets: ["FlorettaCore"]),
        .library(name: "FlorettaUI", targets: ["FlorettaUI"]),
    ],
    targets: [
        .target(
            name: "FlorettaCore",
            dependencies: [],
            path: "FlorettaCore"
        ),
        .target(
            name: "FlorettaUI",
            dependencies: ["FlorettaCore"],
            path: "FlorettaUI"
        ),
        .testTarget(
            name: "FlorettaCoreTests",
            dependencies: ["FlorettaCore"],
            path: "Tests/FlorettaCoreTests",
            // Markdown fixtures are loaded from the source tree with #filePath.
            exclude: ["Fixtures"]
        ),
    ]
)
