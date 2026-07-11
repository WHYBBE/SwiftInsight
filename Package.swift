// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftInsight",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SwiftInsight", targets: ["SwiftInsight"])
    ],
    targets: [
        .executableTarget(
            name: "SwiftInsight",
            path: "Sources/SwiftInsight",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
