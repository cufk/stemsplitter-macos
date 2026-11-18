// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StemSplitter",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "StemSplitter", targets: ["StemSplitter"])
    ],
    targets: [
        .target(
            name: "StemSplitterCore",
            path: "Sources/StemSplitterCore"
        ),
        // Ljudkod (AVFoundation) som går att testa utan gränssnittet
        .target(
            name: "StemSplitterAudio",
            dependencies: ["StemSplitterCore"],
            path: "Sources/StemSplitterAudio"
        ),
        .executableTarget(
            name: "StemSplitter",
            dependencies: ["StemSplitterCore", "StemSplitterAudio"],
            path: "Sources/StemSplitter",
            resources: [
                .process("Resources/bootstrap.sh"),
                .process("Resources/appicon.png")
            ]
        ),
        .testTarget(
            name: "StemSplitterCoreTests",
            dependencies: ["StemSplitterCore"],
            path: "Tests/StemSplitterCoreTests"
        ),
        .testTarget(
            name: "StemSplitterAudioTests",
            dependencies: ["StemSplitterAudio", "StemSplitterCore"],
            path: "Tests/StemSplitterAudioTests"
        )
    ]
)
