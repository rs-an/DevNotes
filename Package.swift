// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DevNotes",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DevNotes", targets: ["DevNotes"])
    ],
    targets: [
        .executableTarget(
            name: "DevNotes",
            path: "Sources/DevNotes"
        )
    ],
    swiftLanguageModes: [.v5]
)
