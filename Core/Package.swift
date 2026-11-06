// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GlimpseCore",
    // The fallback .lproj for languages the catalog lacks (English for everyone else); the catalog's own
    // source language is zh-Hans, see Resources/Localizable.xcstrings.
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GlimpseCore", targets: ["GlimpseCore"]),
    ],
    targets: [
        .target(name: "GlimpseCore", resources: [.process("Resources")]),
        .testTarget(name: "GlimpseCoreTests", dependencies: ["GlimpseCore"]),
    ]
)
