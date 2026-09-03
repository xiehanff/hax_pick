// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "hax_pick",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "hax_pick", targets: ["HaxPickApp"]),
    ],
    targets: [
        .executableTarget(
            name: "HaxPickApp",
            path: "Sources"
        ),
        .testTarget(
            name: "HaxPickAppTests",
            dependencies: ["HaxPickApp"],
            path: "Tests"
        ),
    ]
)
