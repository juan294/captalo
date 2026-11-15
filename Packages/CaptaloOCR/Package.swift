// swift-tools-version: 6.2
import PackageDescription

// The Vision recognition step of region OCR (plan phase 5, unit 5B). The app
// and the Release-built `captalo-ocr-probe` run the same code.
let package = Package(
    name: "CaptaloOCR",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "CaptaloOCR", targets: ["CaptaloOCR"]),
        .executable(name: "captalo-ocr-probe", targets: ["CaptaloOCRProbe"]),
    ],
    dependencies: [.package(path: "../CaptaloCore")],
    targets: [
        .target(name: "CaptaloOCR", dependencies: ["CaptaloCore"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(name: "CaptaloOCRProbe", dependencies: ["CaptaloOCR", "CaptaloCore"],
                          swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
