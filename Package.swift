// swift-tools-version:6.0
// This file exists solely for FOSSA dependency scanning.
// The actual project uses Xcode's native SPM integration.

import PackageDescription

let package = Package(
    name: "MiddleDrag",
    platforms: [.macOS("15.0")],
    products: [],
    dependencies: [
        .package(url: "https://github.com/getsentry/sentry-cocoa.git", from: "9.1.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.8.1"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.5"),
        .package(url: "https://github.com/swiftlang/swift-docc-symbolkit", from: "1.0.0")
    ],
    targets: []
)
