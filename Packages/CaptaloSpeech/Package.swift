// swift-tools-version: 6.2
import PackageDescription

// The FluidAudio adapter and the model store (plan phase 3, review R5). The
// same production code runs in the app and in the Release-built probe.
let package = Package(
    name: "CaptaloSpeech",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "CaptaloSpeech", targets: ["CaptaloSpeech"]),
        .executable(name: "captalo-speech-probe", targets: ["CaptaloSpeechProbe"]),
    ],
    dependencies: [
        .package(path: "../CaptaloCore"),
        // Pinned, patched FluidAudio v0.18.3 (Scripts/prepare-fluidaudio, notes D9).
        .package(path: "../../.local/vendor/FluidAudio"),
    ],
    targets: [
        .target(
            name: "CaptaloSpeech",
            dependencies: ["CaptaloCore", .product(name: "FluidAudio", package: "FluidAudio")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "CaptaloSpeechProbe",
            dependencies: ["CaptaloSpeech", "CaptaloCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CaptaloSpeechTests",
            dependencies: ["CaptaloSpeech"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
