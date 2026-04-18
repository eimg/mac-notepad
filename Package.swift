// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Notepad",
    platforms: [
        .macOS(.v13),
    ],
    targets: [
        .executableTarget(
            name: "Notepad",
            resources: [
                .copy("Resources"),
            ]
        ),
        .testTarget(
            name: "NotepadTests",
            dependencies: ["Notepad"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
