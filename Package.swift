// swift-tools-version: 6.2
import PackageDescription

// Module rules (enforced by scripts/check-architecture.sh):
// - SunshotCore: pure Swift model + logic. Foundation only. No UI, no CoreGraphics drawing.
// - SunshotRender: CoreGraphics / CoreImage / ImageIO rendering. Depends on Core. No AppKit/SwiftUI.
// - SunshotPlatform: AppKit integration + observable editor state (pasteboard, palette). Testable; no views.
// - SunshotApp: thin SwiftUI shell (views, menus, panels). All logic lives in the modules above.
let strictSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
]
// Release builds optimise for size everywhere except the renderer, whose per-pixel loops keep -O (speed). Cuts the
// shipped binary by ~1 MB with no measurable cost: model, UI and platform code are not hot paths.
let sizeOptimised: [SwiftSetting] = strictSettings + [.unsafeFlags(["-Osize"], .when(configuration: .release))]

let package = Package(
    name: "Sunshot",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Sunshot", targets: ["SunshotApp"])
    ],
    targets: [
        .target(
            name: "SunshotCore",
            resources: [.process("Resources")],
            swiftSettings: sizeOptimised
        ),
        .target(
            name: "SunshotRender",
            dependencies: ["SunshotCore"],
            swiftSettings: strictSettings
        ),
        .target(
            name: "SunshotPlatform",
            dependencies: ["SunshotCore", "SunshotRender"],
            swiftSettings: sizeOptimised
        ),
        .executableTarget(
            name: "SunshotApp",
            dependencies: ["SunshotCore", "SunshotRender", "SunshotPlatform"],
            swiftSettings: sizeOptimised
        ),
        .testTarget(
            name: "SunshotCoreTests",
            dependencies: ["SunshotCore"],
            resources: [.copy("fixtures")],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "SunshotRenderTests",
            dependencies: ["SunshotCore", "SunshotRender"],
            exclude: ["__Snapshots__"],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "SunshotPlatformTests",
            dependencies: ["SunshotCore", "SunshotRender", "SunshotPlatform"],
            swiftSettings: strictSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
