// swift-tools-version:5.9
import PackageDescription

// PetKit — 三端(iOS App / iOS 小组件 / Mac App / Mac 桌宠)共享的电子宠物内核。
// 「数据同源」的物理保证：模型 + APIClient + 状态机 + 3D 猫渲染只有这一份。
let package = Package(
    name: "PetKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "PetKit", targets: ["PetKit"])
    ],
    dependencies: [
        // 直接播 Tripo 生成的带动画 GLB（跳过 GLB→USDZ 转换的骨骼动画劣化）
        .package(url: "https://github.com/warrenm/GLTFKit2", from: "0.5.0")
    ],
    targets: [
        .target(
            name: "PetKit",
            dependencies: [
                .product(name: "GLTFKit2", package: "GLTFKit2")
            ],
            path: "Sources/PetKit",
            resources: [
                // 骨骼绑定猫模型（35 骨 + idle 动画），SceneKit 原生加载
                .copy("Resources/cat_idle.usdz"),
                // Tripo3D 生成的品种猫（40k 面 + quadruped walk 动画）
                .copy("Resources/breed_lihua.glb"),
                .copy("Resources/breed_orange.glb"),
                .copy("Resources/breed_sanhua.glb")
            ]
        ),
        .testTarget(
            name: "PetKitTests",
            dependencies: ["PetKit"],
            path: "Tests/PetKitTests"
        )
    ]
)
