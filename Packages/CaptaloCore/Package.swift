// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CaptaloCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "CaptaloCore", targets: ["CaptaloCore"]),
    ],
    targets: [
        .target(
            name: "CaptaloCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(name: "ExplainQualificationProbe", dependencies: ["CaptaloCore"]),
        .testTarget(
            name: "CaptaloCoreTests",
            dependencies: ["CaptaloCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
