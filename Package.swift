// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "hax_pick",
    platforms: [
        .macOS(.v13),
    ],
    // 注意：这里故意不声明 executable product。菜单栏 App 必须以 .app 包裹运行
    // （否则 Bundle.main 没有图标资源，辅助功能授权也会按裸可执行文件另立身份）。
    // 请用 hax_pick.xcodeproj 运行；保留 targets 仅供 `swift build` / `swift test` 使用。
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
