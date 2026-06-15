// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DocumentProcessor",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "DocumentProcessor", targets: ["DocumentProcessor"]),
    ],
    targets: [
        .executableTarget(
            name: "DocumentProcessor",
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"]),
                .unsafeFlags(["-Xfrontend", "-warn-concurrency", "-Xfrontend", "-enable-upcoming-feature", "-Xfrontend", "StrictConcurrency"]),
            ]
        ),
        .testTarget(
            name: "DocumentProcessorTests",
            dependencies: ["DocumentProcessor"]
        ),
    ]
)
