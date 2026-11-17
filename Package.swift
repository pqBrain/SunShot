// swift-tools-version: 6.0
import PackageDescription

// Module rules (enforced by scripts/check-architecture.sh):
// - SunshotCore: pure Swift model + logic. Foundation only. No UI, no CoreGraphics drawing.
// - SunshotRender: CoreGraphics / CoreImage / ImageIO rendering. Depends on Core. No AppKit/SwiftUI.
// - SunshotApp: thin SwiftUI/AppKit shell. All logic lives in Core/Render.
let strictSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "Sunshot",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Sunshot", targets: ["SunshotApp"])
    ],
    targets: [
        .target(
            name: "SunshotCore",
            resources: [.process("Resources")],
            swiftSettings: strictSettings
        ),
        .target(
            name: "SunshotRender",
            dependencies: ["SunshotCore"],
            swiftSettings: strictSettings
        ),
        .executableTarget(
            name: "SunshotApp",
            dependencies: ["SunshotCore", "SunshotRender"],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "SunshotCoreTests",
            dependencies: ["SunshotCore"],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "SunshotRenderTests",
            dependencies: ["SunshotCore", "SunshotRender"],
            exclude: ["__Snapshots__"],
            swiftSettings: strictSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
