import XCTest
import SceneKit
@testable import PetKit

// MARK: - 素材生成器（不是断言测试，是把 3D 猫烘焙成 2D 素材的工具）
//
// 小组件不能跑实时 SceneKit，App 图标更只能是张图；两者都得把首页那只骨骼猫
// (cat_idle.usdz) 离屏渲染成 PNG。模型/装扮/相机改了就重跑这里，别手动 P 图。
//
//   swift test --filter AssetRenderTests \
//     WIDGET_FRAME_DIR=<小组件 Assets.xcassets 路径> APP_ICON_PATH=<appicon_1024.png 路径>
//
// 取样方式：把 idle 动画切到 sceneTime 时基，再用 snapshot(atTime:) 在一个循环里
// 均匀取 16 帧——按系统时间取样会依赖渲染时刻，跑两次结果不一样。
final class AssetRenderTests: XCTestCase {

    private static let frameCount = 24          // 与 PetProvider.frameCount 一致
    // 帧尺寸上限由 WidgetKit 30MB 硬内存限制反推：真机上 UIImage(named:) 会把
    // 全部帧的解码位图缓存（900px 时 16×3.2MB≈52MB → jetsam 杀进程、小组件全白）。
    // 24 帧 × 400px ≈ 15.4MB，与验证过安全的 16×450px≈13MB 同量级；显示端最大
    // ~155pt@3x≈465px，400 轻微上采样，卡通渲染看不出。
    private static let framePixels = 400
    private static let iconPixels = 1024

    // MARK: 小组件动画帧（透明底 + 脚下接地影）

    @MainActor
    func testRenderWidgetFrames() async throws {
        #if os(macOS)
        guard let dir = ProcessInfo.processInfo.environment["WIDGET_FRAME_DIR"] else {
            throw XCTSkip("未设置 WIDGET_FRAME_DIR，跳过小组件帧渲染")
        }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("无 Metal 设备") }
        let root = URL(fileURLWithPath: dir)

        let coord = RiggedCatSceneView.Coordinator(onPart: { _ in })
        let scene = RiggedCatSceneView.buildScene(coord: coord)
        CatAssetRenderer.retimeToSceneClock(coord)
        CatAssetRenderer.addContactShadow(scene)
        CatAssetRenderer.frameCamera(scene, position: SCNVector3(0, 1.05, 3.35), lookAtY: 0.82, fov: 42)

        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: true)

        // 转台式匀速整圈：每帧固定转 360°/frameCount，帧 15→帧 0 正好接上一圈，
        // 循环无折返。之前用 sin 左顾右盼，角速度忽快忽慢还会掉头，翻页时像抽搐。
        //
        // 朝向不走 overlay/spin 约束：SCNTransformConstraint 的闭包拿到的 m 是上一次
        // 求值后的变换，连拍快照会把旋转一路乘进去滚雪球（yaw 探针实测：设 45/90/135/180
        // 出图是 45/135/270/90 的累积序列）。这里 overlay 全部留 0（rotM(0)=单位阵，
        // 乘不出偏差），改为每帧直接给 spin 节点设绝对角度，确定性出图。
        let spinNode = scene.rootNode.childNode(withName: "spin", recursively: false)
        let loop = coord.players.first?.animation.duration ?? 5
        for i in 0..<Self.frameCount {
            let phase = Double(i) / Double(Self.frameCount)
            let t = loop * phase
            spinNode?.eulerAngles.y = CGFloat(phase * 2 * .pi)
            let img = renderer.snapshot(atTime: t,
                                        with: CGSize(width: Self.framePixels, height: Self.framePixels),
                                        antialiasingMode: .multisampling4X)
            let name = String(format: "cat_anim_%02d", i)
            let dest = root.appendingPathComponent("\(name).imageset/\(name).png")
            try CatAssetRenderer.writePNG(img, to: dest)
            // 帧数扩充时新 imageset 目录没有 Contents.json，Xcode 不认；顺手补上（幂等）
            let contents = """
            {
              "images" : [
                { "idiom" : "universal", "filename" : "\(name).png" }
              ],
              "info" : { "author" : "xcode", "version" : 1 }
            }
            """
            try contents.write(to: dest.deletingLastPathComponent().appendingPathComponent("Contents.json"),
                               atomically: true, encoding: .utf8)
        }
        #endif
    }

    // MARK: App 图标（1024、不透明——带 alpha 的图标 App Store 会拒）

    @MainActor
    func testRenderAppIcon() async throws {
        #if os(macOS)
        guard let path = ProcessInfo.processInfo.environment["APP_ICON_PATH"] else {
            throw XCTSkip("未设置 APP_ICON_PATH，跳过图标渲染")
        }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("无 Metal 设备") }

        let coord = RiggedCatSceneView.Coordinator(onPart: { _ in })
        let scene = RiggedCatSceneView.buildScene(coord: coord)
        CatAssetRenderer.retimeToSceneClock(coord)
        CatAssetRenderer.addContactShadow(scene)
        // 图标是半身特写：相机与猫头齐平（沿用旧图标的构图）。注意猫头在 z≈0.57，
        // 比转轴离相机近半个身位，机位要比"按 FOV 算"再退一点，不然耳朵会被切掉。
        CatAssetRenderer.frameCamera(scene, position: SCNVector3(0, 1.05, 2.9), lookAtY: 1.05, fov: 36)

        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: true)
        // idle 中段，睁眼、姿态最正的一帧
        let cat = renderer.snapshot(atTime: (coord.players.first?.animation.duration ?? 5) * 0.5,
                                    with: CGSize(width: Self.iconPixels, height: Self.iconPixels),
                                    antialiasingMode: .multisampling4X)

        // 背景与 App 首页同一视觉语言（TamagotchiHomeView 实机采样）：
        // 顶 #A2B4D2 → 中 #C5D4F4 → 底 #F0F7FF 的薰衣草蓝渐变 + 白色四角星光。
        let icon = CatAssetRenderer.compositeHomeStage(cat, size: Self.iconPixels)
        try CatAssetRenderer.writePNG(icon, to: URL(fileURLWithPath: path))
        #endif
    }
}

// MARK: - 渲染辅助（独立 enum：XCTestCase 是 ObjC 类，同名重载会撞 selector）

#if os(macOS)
private enum CatAssetRenderer {
/// idle 动画默认跟系统时钟走（桌宠要的）；离屏取样必须换成 sceneTime，
/// 否则 snapshot(atTime:) 的参数不起作用，16 帧会渲成一模一样。
@MainActor
static func retimeToSceneClock(_ coord: RiggedCatSceneView.Coordinator) {
    for p in coord.players {
        p.animation.usesSceneTimeBase = true
        p.animation.repeatCount = .greatestFiniteMagnitude
    }
}

/// 相机重新构图：骨骼猫场景的默认机位是给全屏舞台用的，素材要更满一点
@MainActor
static func frameCamera(_ scene: SCNScene, position: SCNVector3, lookAtY: Float, fov: CGFloat) {
    guard let cam = scene.rootNode.childNode(withName: "camera", recursively: true) else { return }
    cam.position = position
    cam.camera?.fieldOfView = fov
    // buildScene 给相机挂了 SCNLookAtConstraint，改目标节点的高度即可重新对准
    if let target = (cam.constraints?.first as? SCNLookAtConstraint)?.target {
        target.position = SCNVector3(0, lookAtY, 0)
    }
}

/// 脚下接地影：场景里没有地面，直接给一张径向渐变贴图铺在 y≈0，比真实阴影稳
@MainActor
static func addContactShadow(_ scene: SCNScene) {
    let plane = SCNPlane(width: 2.1, height: 1.5)
    let m = SCNMaterial()
    m.diffuse.contents = shadowTexture()
    m.lightingModel = .constant
    m.writesToDepthBuffer = false
    m.isDoubleSided = true
    plane.materials = [m]
    let node = SCNNode(geometry: plane)
    node.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
    node.position = SCNVector3(0, 0.004, 0.05)
    node.renderingOrder = -10
    scene.rootNode.addChildNode(node)
}

// 注意：所有位图都走显式 CGContext，不用 NSImage.lockFocus——lockFocus 会跟着
// 主屏的 backingScaleFactor 走，在 Retina 上 1024 的图会画成 2048，且这里拿不到
// 有效的绘图上下文，出图是全黑的（实测踩过）。
static func shadowTexture(size: Int = 256) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let colors = [PlatformColor(white: 0, alpha: 0.32).cgColor,
                  PlatformColor(white: 0, alpha: 0).cgColor] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: colors, locations: [0, 1])!
    let c = CGPoint(x: size / 2, y: size / 2)
    ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0,
                           endCenter: c, endRadius: CGFloat(size) / 2, options: [])
    return ctx.makeImage()!
}

/// App 图标：首页风格舞台（薰衣草蓝三段渐变 + 白色四角星光），猫压在上面。
/// 不透明输出（App 图标不能带 alpha）。星光位置手写死：出图可复现，且避开猫脸区。
static func compositeHomeStage(_ cat: NSImage, size: Int) -> CGImage {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // 三段渐变。CG 原点在左下：0=底(近白) → 1=顶(深一档的薰衣草蓝)
    let colors = [PlatformColor(red: 0.941, green: 0.969, blue: 1.000, alpha: 1).cgColor,  // #F0F7FF
                  PlatformColor(red: 0.773, green: 0.831, blue: 0.957, alpha: 1).cgColor,  // #C5D4F4
                  PlatformColor(red: 0.635, green: 0.706, blue: 0.824, alpha: 1).cgColor]  // #A2B4D2
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: colors as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: s), options: [])

    // 四角星（凹边 twinkle，控制点收在中心）+ 圆点，比例坐标 → 像素。
    // 布局呼应首页：上部与两肩外侧亮星，下部零星小点；中带避开猫脸。
    func star(_ fx: CGFloat, _ fy: CGFloat, _ fr: CGFloat, _ alpha: CGFloat) {
        let c = CGPoint(x: fx * s, y: fy * s), r = fr * s
        let p = CGMutablePath()
        p.move(to: CGPoint(x: c.x, y: c.y + r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: c)
        ctx.setFillColor(PlatformColor(white: 1, alpha: alpha).cgColor)
        ctx.addPath(p)
        ctx.fillPath()
    }
    func dot(_ fx: CGFloat, _ fy: CGFloat, _ fr: CGFloat, _ alpha: CGFloat) {
        ctx.setFillColor(PlatformColor(white: 1, alpha: alpha).cgColor)
        let r = fr * s
        ctx.fillEllipse(in: CGRect(x: fx * s - r, y: fy * s - r, width: r * 2, height: r * 2))
    }
    star(0.14, 0.86, 0.040, 0.95); star(0.86, 0.90, 0.028, 0.85)
    star(0.92, 0.72, 0.045, 0.95); star(0.07, 0.64, 0.026, 0.80)
    star(0.90, 0.42, 0.024, 0.75); star(0.10, 0.34, 0.034, 0.85)
    star(0.26, 0.94, 0.020, 0.70); star(0.68, 0.96, 0.030, 0.80)
    star(0.05, 0.13, 0.022, 0.65); star(0.94, 0.12, 0.028, 0.70)
    dot(0.22, 0.76, 0.008, 0.75); dot(0.80, 0.82, 0.006, 0.65)
    dot(0.12, 0.48, 0.007, 0.60); dot(0.88, 0.57, 0.006, 0.60)
    dot(0.30, 0.06, 0.007, 0.55); dot(0.76, 0.05, 0.008, 0.60)

    if let cg = cat.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: s, height: s))
    }
    return ctx.makeImage()!
}

/// 把透明底的猫压到渐变背景上（App 图标不能带 alpha，带了 App Store 会打回）
static func composite(_ cat: NSImage,
                      onGradient colors: (top: PlatformColor, bottom: PlatformColor),
                      size: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [colors.bottom.cgColor, colors.top.cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: size), options: [])
    if let cg = cat.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
    }
    return ctx.makeImage()!
}

static func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
        throw NSError(domain: "AssetRender", code: 1)
    }
    try writePNG(rep, to: url)
}

static func writePNG(_ cg: CGImage, to url: URL) throws {
    try writePNG(NSBitmapImageRep(cgImage: cg), to: url)
}

static func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "AssetRender", code: 2)
    }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try png.write(to: url)
}
}
#endif
