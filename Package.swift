// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StemSplitter",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "StemSplitter", targets: ["StemSplitter"])
    ],
    targets: [
        .target(
            name: "StemSplitterCore",
            path: "Sources/StemSplitterCore"
        ),
        .executableTarget(
            name: "StemSplitter",
            dependencies: ["StemSplitterCore"],
            path: "Sources/StemSplitter",
            resources: [
                .process("Resources/bootstrap.sh")
            ]
        ),
        .testTarget(
            name: "StemSplitterCoreTests",
            dependencies: ["StemSplitterCore"],
            path: "Tests/StemSplitterCoreTests"
        )
    ]
)
