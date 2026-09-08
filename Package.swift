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
    dependencies: [
        // Down 为本地包（LocalPackages/Down）：上游 DownLayoutManager 的代码块
        // 背景逐行满宽直角填充，已本地修补为整块圆角卡片 + 两侧留边。
        .package(path: "LocalPackages/Down"),
        .package(url: "https://github.com/JohnSundell/Splash.git", from: "0.16.0"),
    ],
    targets: [
        .executableTarget(
            name: "HaxPickApp",
            dependencies: [
                .product(name: "Down", package: "Down"),
                .product(name: "Splash", package: "Splash"),
            ],
            path: "Sources",
            resources: [
                .copy("Resources/HaxIcons"),
            ]
        ),
        .testTarget(
            name: "HaxPickAppTests",
            dependencies: ["HaxPickApp"],
            path: "Tests"
        ),
    ]
)
