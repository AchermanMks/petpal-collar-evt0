import SwiftUI
import SceneKit
import QuartzCore

// MARK: - 骨骼绑定真猫（cat_idle.usdz：35 骨骼 + 5s idle 动画）
//
// 形态：idle 循环播放，行为映射播放速度（睡 0.35× / 玩 1.5×）。喂食/抚摸/变装
// 通过操控骨骼实现：
// - 喂食：neck/head 低头到碗 + jaw 咀嚼开合
// - 抚摸：头往手心侧倾 + 双耳抖动
// - 拽尾巴：尾骨链摆动
// - 变装：配饰节点每帧跟随 head/neck 骨骼「动画后」的世界位置
//
// 实现钩子是 SCNTransformConstraint：约束在每帧动画求值「之后」运行，闭包里在骨骼
// 当前变换上左乘修正旋转，与 idle 动画叠加、互不打架（约束不会顶掉动画——早期以为会，
// 实为模型 Z-up 朝向未摆正的误判）。修正量对 overlay 目标值做 EMA，无跳变。
//
// 朝向：cat_idle.usdz 是 Blender Z-up 资产，导入后整只猫竖着（头-尾轴沿世界 +Y、
// 头朝下）。外层 container 下套一个 tilt 节点绕 X 轴 -90° 摆正 → 正常站姿、脸朝 +Z 相机
//（离线扫角实测最佳）。骨骼局部旋转不受 tilt 影响，配饰用世界坐标跟随。

/// 约束闭包（渲染线程）读、互动序列（主线程）写；均为独立标量，撕裂读下一帧自愈，不加锁。
final class BoneOverlayState: @unchecked Sendable {
    var neckPitchTarget = 0.0, neckPitchCurrent = 0.0   // 喂食低头
    var headPitchTarget = 0.0, headPitchCurrent = 0.0
    var headRollTarget = 0.0, headRollCurrent = 0.0     // 抚摸侧倾
    var headYawTarget = 0.0, headYawCurrent = 0.0       // 扭头看鼠标
    var lookPitchTarget = 0.0, lookPitchCurrent = 0.0   // 抬头/低头看鼠标
    var yawTarget = 0.0, yawCurrent = 0.0               // 整只猫的朝向（散步方向 / 转身）
    var walking = false                                  // 走路 bob（上下颠 + 左右晃）
    var chewUntil: CFTimeInterval = 0                    // 咀嚼窗口
    var earFlickUntil: CFTimeInterval = 0               // 耳朵抖动窗口
    var tailBoostUntil: CFTimeInterval = 0              // 尾巴摆动窗口
    static let smoothing = 0.14
    static let yawSmoothing = 0.09                       // 转身比抬头慢一点，才有惯性
}

/// SCNMatrix4MakeRotation 标量类型平台不同（iOS=Float / macOS=CGFloat），统一封装
@inline(__always)
func rotM(_ a: Double, _ x: Double, _ y: Double, _ z: Double) -> SCNMatrix4 {
    #if canImport(UIKit)
    return SCNMatrix4MakeRotation(Float(a), Float(x), Float(y), Float(z))
    #else
    return SCNMatrix4MakeRotation(CGFloat(a), CGFloat(x), CGFloat(y), CGFloat(z))
    #endif
}

@inline(__always)
func transM(_ x: Double, _ y: Double, _ z: Double) -> SCNMatrix4 {
    #if canImport(UIKit)
    return SCNMatrix4MakeTranslation(Float(x), Float(y), Float(z))
    #else
    return SCNMatrix4MakeTranslation(CGFloat(x), CGFloat(y), CGFloat(z))
    #endif
}

public struct RiggedCatSceneView {
    let outfit: Outfit
    let animationSpeed: Double
    let feedNonce: Int
    let petNonce: Int
    let yaw: Double
    let walking: Bool
    let deskMode: Bool
    var onSecondaryClick: () -> Void
    var onZoom: (Double) -> Void
    var onDragEnd: () -> Void
    var onPart: (CatPart) -> Void

    /// - Parameters:
    ///   - yaw: 猫的基础朝向（弧度，+ 为面向屏幕右侧）。桌宠散步时由行走方向驱动。
    ///   - walking: 走路中——叠一层上下颠 + 左右晃的步态，idle 剪辑也走得像在迈步。
    ///   - deskMode: macOS 桌宠交互（鼠标跟随转头 / 左键拖动挪窝 / 点击互动 / 滚轮缩放 /
    ///               右键菜单），关掉 SceneKit 自带的相机控制——那套是"转相机"，方向反直觉。
    ///   - onSecondaryClick / onZoom / onDragEnd: 仅 deskMode 会触发，交给宿主 App 处理
    ///     （弹菜单、改大小、记位置）；PetKit 不碰 NSMenu 这类平台专有 UI。
    public init(outfit: Outfit = .none,
                animationSpeed: Double = 1.0,
                feedNonce: Int = 0,
                petNonce: Int = 0,
                yaw: Double = 0,
                walking: Bool = false,
                deskMode: Bool = false,
                onSecondaryClick: @escaping () -> Void = {},
                onZoom: @escaping (Double) -> Void = { _ in },
                onDragEnd: @escaping () -> Void = {},
                onPart: @escaping (CatPart) -> Void = { _ in }) {
        self.outfit = outfit
        self.animationSpeed = animationSpeed
        self.feedNonce = feedNonce
        self.petNonce = petNonce
        self.yaw = yaw
        self.walking = walking
        self.deskMode = deskMode
        self.onSecondaryClick = onSecondaryClick
        self.onZoom = onZoom
        self.onDragEnd = onDragEnd
        self.onPart = onPart
    }

    func buildView(_ coord: Coordinator) -> SCNView {
        MainActor.assumeIsolated {
            #if canImport(AppKit)
            let view: SCNView = deskMode ? PetDeskSCNView() : SCNView()
            #else
            let view = SCNView()
            #endif
            view.antialiasingMode = .multisampling4X
            view.autoenablesDefaultLighting = false
            view.allowsCameraControl = !deskMode
            view.backgroundColor = .clear
            #if canImport(AppKit)
            view.wantsLayer = true
            view.layer?.isOpaque = false
            view.layer?.backgroundColor = PlatformColor.clear.cgColor
            #endif
            view.scene = Self.buildScene(coord: coord)
            coord.setSpeed(animationSpeed)
            coord.applyOutfit(outfit)
            coord.setBaseYaw(yaw)
            coord.setWalking(walking)
            coord.lastFeedNonce = feedNonce
            coord.lastPetNonce = petNonce
            #if canImport(AppKit)
            if let desk = view as? PetDeskSCNView {
                desk.coord = coord     // 点击由 desk view 自己判（要和拖拽区分开）
                desk.bind(self)
                return view
            }
            #endif
            let tap = PlatformTapGesture(target: coord, action: #selector(Coordinator.tapped(_:)))
            view.addGestureRecognizer(tap)
            return view
        }
    }

    func refresh(_ view: SCNView, _ coord: Coordinator) {
        MainActor.assumeIsolated {
            coord.onPart = onPart
            coord.setSpeed(animationSpeed)
            coord.applyOutfit(outfit)
            coord.setBaseYaw(yaw)
            coord.setWalking(walking)
            #if canImport(AppKit)
            (view as? PetDeskSCNView)?.bind(self)   // 闭包每次重建，回调要跟着换新
            #endif
            if coord.lastFeedNonce != feedNonce {
                coord.lastFeedNonce = feedNonce
                coord.feedReaction()
            }
            if coord.lastPetNonce != petNonce {
                coord.lastPetNonce = petNonce
                coord.petReaction()
            }
        }
    }

    func makeCoord() -> Coordinator { MainActor.assumeIsolated { Coordinator(onPart: onPart) } }

    // MARK: 场景搭建

    @MainActor
    static func buildScene(coord: Coordinator) -> SCNScene {
        let scene = SCNScene()
        // spin(朝向 + 步态) → container（归一化 + 互动缩放）→ tilt(-90°X 摆正) → 模型
        //
        // 朝向单独一层的原因：container 的 position 是"把模型摆到世界原点"的补偿量，
        // 转 container 会绕它自己的原点（偏离猫身）画圈；spin 在世界原点上转，猫才是
        // 原地转身。归一化保证猫的中轴就在 x=0/z=0。
        let spin = SCNNode()
        spin.name = "spin"
        scene.rootNode.addChildNode(spin)
        let container = SCNNode()
        container.name = "riggedCat"
        spin.addChildNode(container)
        let tilt = SCNNode()
        tilt.name = "tilt"
        tilt.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        container.addChildNode(tilt)

        if let url = Bundle.module.url(forResource: "cat_idle", withExtension: "usdz"),
           let model = try? SCNScene(url: url, options: nil) {
            for child in model.rootNode.childNodes {
                tilt.addChildNode(child)
            }
            tilt.enumerateHierarchy { node, _ in
                for key in node.animationKeys {
                    if let player = node.animationPlayer(forKey: key) {
                        player.animation.repeatCount = .greatestFiniteMagnitude
                        player.animation.usesSceneTimeBase = false
                        player.play()
                        coord.players.append(player)
                    }
                }
                if let skinner = node.skinner {
                    coord.bones = skinner.bones
                }
            }
            Self.normalize(container)
            coord.container = container
            coord.installBoneConstraints()
        }
        coord.installSpinConstraint(spin)

        let camera = SCNCamera()
        camera.fieldOfView = 42
        camera.zNear = 0.1
        let camNode = SCNNode()
        camNode.camera = camera
        camNode.name = "camera"
        camNode.position = SCNVector3(0, 1.15, 4.6)
        let target = SCNNode()
        target.position = SCNVector3(0, 0.9, 0)
        scene.rootNode.addChildNode(target)
        camNode.constraints = [SCNLookAtConstraint(target: target)]
        scene.rootNode.addChildNode(camNode)

        let key = SCNNode()
        key.light = SCNLight()
        key.light!.type = .directional
        key.light!.intensity = 900
        key.light!.castsShadow = true
        key.light!.shadowMode = .deferred
        key.light!.shadowColor = PlatformColor.black.withAlphaComponent(0.25)
        key.eulerAngles = SCNVector3(-0.9, 0.5, 0)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light!.type = .directional
        fill.light!.intensity = 350
        fill.eulerAngles = SCNVector3(-0.3, -1.8, 0)
        scene.rootNode.addChildNode(fill)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 420
        scene.rootNode.addChildNode(ambient)

        return scene
    }

    /// 归一化：最大边 2.0、脚底贴 y=0、居中（对含 tilt 子树的 container 包围盒）
    @MainActor
    static func normalize(_ container: SCNNode) {
        let (bbMin, bbMax) = container.boundingBox
        let maxDim = max(Float(bbMax.x - bbMin.x), Float(bbMax.y - bbMin.y), Float(bbMax.z - bbMin.z))
        guard maxDim > 0 else { return }
        let s = 2.0 / maxDim
        container.scale = SCNVector3(s, s, s)
        let cx = Float(bbMin.x + bbMax.x) / 2 * s
        let by = Float(bbMin.y) * s
        let cz = Float(bbMin.z + bbMax.z) / 2 * s
        container.position = SCNVector3(-cx, -by, -cz)
    }

    // MARK: Coordinator

    @MainActor
    public final class Coordinator: NSObject {
        var onPart: (CatPart) -> Void
        var players: [SCNAnimationPlayer] = []
        var bones: [SCNNode] = []
        var container: SCNNode?
        var lastFeedNonce = 0
        var lastPetNonce = 0
        let overlay = BoneOverlayState()
        private var currentOutfit: Outfit?
        private var outfitNode: SCNNode?
        private var feedTask: Task<Void, Never>?
        private var petTask: Task<Void, Never>?

        init(onPart: @escaping (CatPart) -> Void) { self.onPart = onPart }

        func setSpeed(_ speed: Double) { for p in players { p.speed = CGFloat(speed) } }
        func bone(_ name: String) -> SCNNode? { bones.first { $0.name == name } }

        // MARK: 朝向（散步方向 / 鼠标跟随 / 拖拽转身）

        private var baseYaw = 0.0
        private var lookYaw: Double?

        /// 当前生效的朝向，拖拽转身要接着它继续拧
        var currentYaw: Double { lookYaw ?? baseYaw }

        /// 基础朝向：桌宠散步时 = 行走方向；停下来时归零（面向用户）
        func setBaseYaw(_ y: Double) {
            guard baseYaw != y else { return }
            baseYaw = y
            if lookYaw == nil { applyYaw() }
        }

        /// 鼠标跟随 / 拖拽转身。yaw = nil 表示放手，朝向交还给散步逻辑。
        func setLook(yaw: Double?, pitch: Double = 0) {
            lookYaw = yaw
            overlay.lookPitchTarget = yaw == nil ? 0 : pitch
            applyYaw()
        }

        /// 身体转大半、脑袋补剩下的一小半：看人时是「扭头看你」，不是整只猫平移旋转
        private func applyYaw() {
            guard let look = lookYaw else {
                overlay.yawTarget = baseYaw
                overlay.headYawTarget = 0
                return
            }
            overlay.yawTarget = look * 0.62
            overlay.headYawTarget = (look * 0.38).clamped(to: -0.55...0.55)
        }

        func setWalking(_ on: Bool) { overlay.walking = on }

        /// 朝向 + 步态都挂在 spin 上：每帧朝目标角度缓动，走路时再叠上下颠和左右晃。
        func installSpinConstraint(_ spin: SCNNode) {
            let st = overlay
            spin.constraints = [SCNTransformConstraint(inWorldSpace: false) { _, m in
                st.yawCurrent += (st.yawTarget - st.yawCurrent) * BoneOverlayState.yawSmoothing
                var t = rotM(st.yawCurrent, 0, 1, 0)
                if st.walking {
                    let now = CACurrentMediaTime()
                    // 猫步：每步一颠（~2.4 步/秒），身子跟着半频左右晃
                    t = SCNMatrix4Mult(rotM(sin(now * 7.6) * 0.035, 0, 0, 1), t)
                    t = SCNMatrix4Mult(t, transM(0, abs(sin(now * 7.6)) * 0.035, 0))
                }
                return SCNMatrix4Mult(t, m)
            }]
        }

        // MARK: 骨骼约束（动画后每帧叠加修正）

        func installBoneConstraints() {
            let st = overlay
            func addRot(_ node: SCNNode?, _ make: @escaping () -> SCNMatrix4) {
                node?.constraints = [SCNTransformConstraint(inWorldSpace: false) { _, m in
                    SCNMatrix4Mult(make(), m)
                }]
            }
            addRot(bone("neck")) {
                st.neckPitchCurrent += (st.neckPitchTarget - st.neckPitchCurrent) * BoneOverlayState.smoothing
                return rotM(st.neckPitchCurrent, 1, 0, 0)   // 趴卧是 sphinx 姿，头抬着不低头
            }
            addRot(bone("head")) {
                st.headPitchCurrent += (st.headPitchTarget - st.headPitchCurrent) * BoneOverlayState.smoothing
                st.headRollCurrent += (st.headRollTarget - st.headRollCurrent) * BoneOverlayState.smoothing
                st.headYawCurrent += (st.headYawTarget - st.headYawCurrent) * BoneOverlayState.smoothing
                st.lookPitchCurrent += (st.lookPitchTarget - st.lookPitchCurrent) * BoneOverlayState.smoothing
                // 头骨局部轴：X=点头 / Y=扭头 / Z=侧倾（喂食低头与看鼠标共用 X，直接相加）
                let pitch = rotM(st.headPitchCurrent + st.lookPitchCurrent, 1, 0, 0)
                let yaw = rotM(st.headYawCurrent, 0, 1, 0)
                return SCNMatrix4Mult(SCNMatrix4Mult(pitch, yaw), rotM(st.headRollCurrent, 0, 0, 1))
            }
            addRot(bone("jaw")) {
                let now = CACurrentMediaTime()
                guard now < st.chewUntil else { return SCNMatrix4Identity }
                return rotM(max(0, sin(now * 9)) * 0.3, 1, 0, 0)
            }
            for (name, dir) in [("ear_L", 1.0), ("ear_R", -1.0)] {
                addRot(bone(name)) {
                    let now = CACurrentMediaTime()
                    guard now < st.earFlickUntil else { return SCNMatrix4Identity }
                    return rotM(sin(now * 22) * 0.35 * dir, 0, 0, 1)
                }
            }
            for (i, name) in ["tail_01", "tail_02", "tail_03"].enumerated() {
                let phase = Double(i) * 0.9
                addRot(bone(name)) {
                    let now = CACurrentMediaTime()
                    guard now < st.tailBoostUntil else { return SCNMatrix4Identity }
                    return rotM(sin(now * 8 + phase) * 0.3, 0, 1, 0)
                }
            }
        }

        // MARK: 互动序列（改目标值，约束平滑跟随）

        /// 喂食：低头到碗 + 咀嚼 ~2s，再抬头
        func feedReaction() {
            feedTask?.cancel()
            overlay.neckPitchTarget = 0.5
            overlay.headPitchTarget = 0.3
            overlay.chewUntil = CACurrentMediaTime() + 1.9
            feedTask = Task { [overlay] in
                try? await Task.sleep(for: .seconds(2.1))
                guard !Task.isCancelled else { return }
                overlay.neckPitchTarget = 0
                overlay.headPitchTarget = 0
            }
        }

        /// 抚摸：头往手心侧倾 + 耳朵抖动
        func petReaction() {
            petTask?.cancel()
            overlay.headRollTarget = 0.35
            overlay.earFlickUntil = CACurrentMediaTime() + 1.0
            petTask = Task { [overlay] in
                try? await Task.sleep(for: .seconds(1.1))
                guard !Task.isCancelled else { return }
                overlay.headRollTarget = 0
            }
        }

        /// 拽尾巴：尾骨链摆动
        func tailReaction() { overlay.tailBoostUntil = CACurrentMediaTime() + 1.3 }

        // MARK: 变装（配饰约束跟随骨骼动画后世界位置）

        func applyOutfit(_ outfit: Outfit) {
            guard currentOutfit != outfit else { return }
            currentOutfit = outfit
            outfitNode?.removeFromParentNode()
            outfitNode = nil
            guard outfit != .none, let container else { return }

            let anchorName = (outfit == .scarf || outfit == .collar) ? "neck001" : "head"
            guard let anchor = bone(anchorName), let accessory = Self.buildAccessory(outfit) else { return }
            let off = Self.accessoryOffset(outfit)
            let st = overlay
            // 注：只跟身体 yaw，不叠扭头 yaw——头骨世界位已经含了大半扭头量，
            // 再乘一次会把墨镜甩到脸外面（离屏渲染实测）。
            // 配饰挂在 spin 外层（不受 container 缩放）；约束每帧把它放到骨骼动画后世界位置 + 世界偏移。
            // 偏移量和配饰自身都要跟着猫的朝向转——否则猫一侧身，墨镜/围巾还钉在原来的正面，
            // 会飘到脸外面去（骨骼世界位已含朝向，只有这份「世界偏移」是我们自己加的）。
            accessory.constraints = [SCNTransformConstraint(inWorldSpace: true) { [weak anchor] _, m in
                guard let anchor else { return m }
                let p = anchor.presentation.worldPosition
                let yaw = st.yawCurrent
                let ox = Double(off.x) * cos(yaw) + Double(off.z) * sin(yaw)
                let oz = -Double(off.x) * sin(yaw) + Double(off.z) * cos(yaw)
                return SCNMatrix4Mult(rotM(yaw, 0, 1, 0),
                                      transM(Double(p.x) + ox, Double(p.y) + Double(off.y), Double(p.z) + oz))
            }]
            container.parent?.addChildNode(accessory)
            outfitNode = accessory
        }

        /// 世界偏移（tilt+归一化后探针实测：head≈y1.01/z0.57，头顶面≈y+0.47，
        /// 眼位脸面≈z+0.47~0.50（吻部凸出，z 太小会整个埋进头里），耳根前侧≈(0.2, 0.3, 0.26)）
        static func accessoryOffset(_ outfit: Outfit) -> SCNVector3 {
            switch outfit {
            case .beret:   return SCNVector3(0, 0.50, 0.05)
            case .crown:   return SCNVector3(0, 0.52, -0.03)
            case .glasses: return SCNVector3(0, 0.15, 0.50)
            case .bow:     return SCNVector3(0.19, 0.34, 0.26)
            case .scarf:   return SCNVector3(0, 0.0, 0.05)
            case .collar:  return SCNVector3(0, 0.02, 0.05)
            case .wizard:  return SCNVector3(0, 0.50, 0)
            case .none:    return SCNVector3(0, 0, 0)
            }
        }

        /// 配饰几何（世界单位：猫高约 1.65，头宽约 0.4）。
        /// 多材质细节款：主色调来自 outfit.platformColor，金属/镜片等用局部配色 + blinn 高光。
        static func buildAccessory(_ outfit: Outfit) -> SCNNode? {
            func part(_ g: SCNGeometry, _ color: PlatformColor,
                      pos: SCNVector3 = SCNVector3(0, 0, 0),
                      scale: SCNVector3 = SCNVector3(1, 1, 1),
                      euler: SCNVector3 = SCNVector3(0, 0, 0),
                      gloss: CGFloat = 0.15) -> SCNNode {
                let m = SCNMaterial()
                m.diffuse.contents = color
                m.lightingModel = .blinn
                m.specular.contents = PlatformColor(white: gloss, alpha: 1)
                m.shininess = max(0.05, gloss)
                g.materials = [m]
                let n = SCNNode(geometry: g); n.position = pos; n.scale = scale; n.eulerAngles = euler
                return n
            }
            let c = outfit.platformColor
            let gold = PlatformColor(red: 0.93, green: 0.76, blue: 0.28, alpha: 1)
            let dark = PlatformColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)
            let cream = PlatformColor(red: 0.97, green: 0.93, blue: 0.85, alpha: 1)
            let group = SCNNode(); group.name = "outfit"
            switch outfit {
            case .none:
                return nil
            case .beret:
                // 画家贝雷帽：软塌帽体 + 深色包边 + 帽蒂，整体歪戴
                let darkWine = PlatformColor(red: 0.60, green: 0.15, blue: 0.21, alpha: 1)
                group.addChildNode(part(SCNTorus(ringRadius: 0.155, pipeRadius: 0.035), darkWine,
                                        pos: SCNVector3(0.01, -0.03, 0),
                                        euler: SCNVector3(0, 0, -0.12)))
                group.addChildNode(part(SCNSphere(radius: 0.20), c,
                                        pos: SCNVector3(0.03, 0.02, 0),
                                        scale: SCNVector3(1.15, 0.45, 1.15),
                                        euler: SCNVector3(0, 0, -0.15)))
                group.addChildNode(part(SCNCapsule(capRadius: 0.018, height: 0.07), darkWine,
                                        pos: SCNVector3(0.05, 0.10, 0),
                                        euler: SCNVector3(0, 0, -0.15)))
            case .crown:
                // 金冠：抛光冠体 + 顶圈 + 四尖彩宝 + 正面红宝石
                group.addChildNode(part(SCNCylinder(radius: 0.145, height: 0.10), gold, gloss: 0.85))
                group.addChildNode(part(SCNTorus(ringRadius: 0.145, pipeRadius: 0.018), gold,
                                        pos: SCNVector3(0, 0.05, 0), gloss: 0.85))
                let gems: [(Float, Float, PlatformColor)] = [
                    (0.105, 0, PlatformColor(red: 0.85, green: 0.20, blue: 0.25, alpha: 1)),
                    (-0.105, 0, PlatformColor(red: 0.25, green: 0.45, blue: 0.85, alpha: 1)),
                    (0, 0.105, PlatformColor(red: 0.30, green: 0.72, blue: 0.40, alpha: 1)),
                    (0, -0.105, PlatformColor(red: 0.65, green: 0.35, blue: 0.80, alpha: 1)),
                ]
                for (dx, dz, gemColor) in gems {
                    group.addChildNode(part(SCNCone(topRadius: 0.004, bottomRadius: 0.035, height: 0.11), gold,
                                            pos: SCNVector3(dx, 0.10, dz), gloss: 0.85))
                    group.addChildNode(part(SCNSphere(radius: 0.018), gemColor,
                                            pos: SCNVector3(dx, 0.17, dz), gloss: 0.95))
                }
                group.addChildNode(part(SCNSphere(radius: 0.025),
                                        PlatformColor(red: 0.85, green: 0.20, blue: 0.25, alpha: 1),
                                        pos: SCNVector3(0, 0, 0.145), gloss: 0.95))
            case .bow:
                // 缎带蝴蝶结：双翼 + 浅色结心 + 垂下的两条飘带
                let lightPink = PlatformColor(red: 0.99, green: 0.68, blue: 0.80, alpha: 1)
                for sx in [-1.0, 1.0] {
                    group.addChildNode(part(SCNSphere(radius: 0.075), c,
                                            pos: SCNVector3(Float(sx) * 0.075, 0, 0),
                                            scale: SCNVector3(1, 0.68, 0.5), gloss: 0.4))
                    group.addChildNode(part(SCNCapsule(capRadius: 0.022, height: 0.09), c,
                                            pos: SCNVector3(Float(sx) * 0.03, -0.07, 0),
                                            euler: SCNVector3(0, 0, Float(sx) * -0.4), gloss: 0.4))
                }
                group.addChildNode(part(SCNSphere(radius: 0.04), lightPink,
                                        pos: SCNVector3(0, 0, 0.02), gloss: 0.5))
            case .glasses:
                // 墨镜：真实深色镜片 + 金丝框 + 鼻梁 + 镜腿
                for sx in [-1.0, 1.0] {
                    group.addChildNode(part(SCNSphere(radius: 0.082), dark,
                                            pos: SCNVector3(Float(sx) * 0.10, 0, 0),
                                            scale: SCNVector3(1, 1, 0.32), gloss: 0.95))
                    group.addChildNode(part(SCNTorus(ringRadius: 0.085, pipeRadius: 0.011), gold,
                                            pos: SCNVector3(Float(sx) * 0.10, 0, 0.01),
                                            euler: SCNVector3(Float.pi / 2, 0, 0), gloss: 0.8))
                    group.addChildNode(part(SCNCylinder(radius: 0.009, height: 0.30), gold,
                                            pos: SCNVector3(Float(sx) * 0.20, 0.01, -0.14),
                                            euler: SCNVector3(Float.pi / 2, Float(sx) * -0.12, 0), gloss: 0.8))
                }
                group.addChildNode(part(SCNCylinder(radius: 0.010, height: 0.055), gold,
                                        pos: SCNVector3(0, 0.01, 0.01),
                                        euler: SCNVector3(0, 0, Float.pi / 2), gloss: 0.8))
            case .scarf:
                // 双色针织围巾：主圈 + 奶白绞花 + 垂带 + 三缕流苏
                group.addChildNode(part(SCNTorus(ringRadius: 0.20, pipeRadius: 0.062), c,
                                        euler: SCNVector3(0.25, 0, 0)))
                group.addChildNode(part(SCNTorus(ringRadius: 0.20, pipeRadius: 0.030), cream,
                                        pos: SCNVector3(0, 0.045, 0),
                                        euler: SCNVector3(0.25, 0, 0)))
                group.addChildNode(part(SCNCapsule(capRadius: 0.048, height: 0.20), c,
                                        pos: SCNVector3(0.10, -0.14, 0.14),
                                        euler: SCNVector3(0.3, 0, 0.1)))
                for (i, fx) in [Float(0.085), 0.115, 0.145].enumerated() {
                    group.addChildNode(part(SCNCylinder(radius: 0.012, height: 0.055), cream,
                                            pos: SCNVector3(fx, -0.25, 0.175 + Float(i % 2) * 0.01),
                                            euler: SCNVector3(0.3, 0, 0)))
                }
            case .collar:
                // 铃铛项圈：红色皮质环带 + 金属环扣 + 金铃铛（带响缝）
                group.addChildNode(part(SCNTorus(ringRadius: 0.165, pipeRadius: 0.030), c,
                                        euler: SCNVector3(0.22, 0, 0), gloss: 0.35))
                group.addChildNode(part(SCNTorus(ringRadius: 0.022, pipeRadius: 0.007), gold,
                                        pos: SCNVector3(0, -0.055, 0.165),
                                        euler: SCNVector3(Float.pi / 2, 0, 0), gloss: 0.8))
                group.addChildNode(part(SCNSphere(radius: 0.045), gold,
                                        pos: SCNVector3(0, -0.105, 0.165), gloss: 0.9))
                group.addChildNode(part(SCNCapsule(capRadius: 0.005, height: 0.03), dark,
                                        pos: SCNVector3(0, -0.112, 0.207)))
            case .wizard:
                // 巫师帽：宽檐尖顶 + 金色帽带 + 尖上金球 + 散落小星
                group.addChildNode(part(SCNCylinder(radius: 0.235, height: 0.025), c))
                group.addChildNode(part(SCNCone(topRadius: 0.014, bottomRadius: 0.15, height: 0.38), c,
                                        pos: SCNVector3(0, 0.19, 0)))
                group.addChildNode(part(SCNCylinder(radius: 0.152, height: 0.04), gold,
                                        pos: SCNVector3(0, 0.035, 0), gloss: 0.8))
                group.addChildNode(part(SCNSphere(radius: 0.028), gold,
                                        pos: SCNVector3(0.05, 0.375, 0), gloss: 0.8))
                for (sx, sy, sz) in [(Float(0.06), Float(0.12), Float(0.075)),
                                     (Float(-0.045), Float(0.20), Float(0.052)),
                                     (Float(0.02), Float(0.28), Float(0.033))] {
                    group.addChildNode(part(SCNSphere(radius: 0.015), gold,
                                            pos: SCNVector3(sx, sy, sz), gloss: 0.9))
                }
            }
            return group
        }

        // MARK: 点击 → 最近骨骼分类部位

        @objc func tapped(_ gesture: PlatformTapGesture) {
            guard let view = gesture.view as? SCNView else { return }
            tap(at: gesture.location(in: view), in: view)
        }

        func tap(at point: CGPoint, in view: SCNView) {
            guard let hit = view.hitTest(point, options: nil).first else { return }
            let hp = hit.worldCoordinates
            var best: CatPart = .body
            var bestDist = Float.greatestFiniteMagnitude
            for bone in bones {
                let bp = bone.presentation.worldPosition
                let dx = Float(bp.x - hp.x), dy = Float(bp.y - hp.y), dz = Float(bp.z - hp.z)
                let dist = dx * dx + dy * dy + dz * dz
                guard dist < bestDist, let name = bone.name else { continue }
                bestDist = dist
                if name.hasPrefix("tail") { best = .tail }
                else if name.hasPrefix("head") || name.hasPrefix("jaw")
                            || name.hasPrefix("neck") || name.hasPrefix("ear") { best = .head }
                else { best = .body }
            }
            switch best {
            case .head: petReaction()
            case .tail: tailReaction()
            case .body:
                container?.runAction(.sequence([.scale(by: 0.95, duration: 0.10),
                                                .scale(by: 1.0 / 0.95, duration: 0.14)]))
                tailReaction()
            }
            onPart(best)
        }
    }
}

#if canImport(UIKit)
extension RiggedCatSceneView: UIViewRepresentable {
    public func makeUIView(context: Context) -> SCNView { buildView(context.coordinator) }
    public func updateUIView(_ view: SCNView, context: Context) { refresh(view, context.coordinator) }
    public func makeCoordinator() -> Coordinator { makeCoord() }
}
#elseif canImport(AppKit)
extension RiggedCatSceneView: NSViewRepresentable {
    public func makeNSView(context: Context) -> SCNView { buildView(context.coordinator) }
    public func updateNSView(_ view: SCNView, context: Context) { refresh(view, context.coordinator) }
    public func makeCoordinator() -> Coordinator { makeCoord() }
}

// MARK: - 桌宠鼠标交互（macOS）
//
// SceneKit 自带的 allowsCameraControl 转的是「相机」：往右拖，猫看着像往左转，
// 桌面上一只巴掌大的猫这样很别扭。这里全部换成桌宠该有的手感：
// - 悬停   → 扭头看向光标（身体转大半、脑袋补一小半，上下小幅抬头/低头）
// - 左键拖 → 整只桌宠跟手挪窝（拖哪都行，猫身也算）
// - 左键点 → 命中猫身才算「戳它一下」：摸头/戳肚/拽尾反应 + 宿主 App 的互动动作
// - 滚轮   → 缩放（宿主 App 决定怎么改尺寸）
// - 右键   → 交给宿主 App 弹菜单（PetKit 不碰 NSMenu 这类平台专有 UI）
final class PetDeskSCNView: SCNView {
    weak var coord: RiggedCatSceneView.Coordinator?
    private var onSecondaryClick: () -> Void = {}
    private var onZoom: (Double) -> Void = { _ in }
    private var onDragEnd: () -> Void = {}

    func bind(_ view: RiggedCatSceneView) {
        onSecondaryClick = view.onSecondaryClick
        onZoom = view.onZoom
        onDragEnd = view.onDragEnd
    }

    private var trackingArea: NSTrackingArea?
    /// 拖窗起点：(按下时的鼠标屏幕坐标, 当时的窗口原点)。用屏幕坐标差算位移，
    /// 不能用 view 内坐标——窗口一动，view 内坐标跟着动，会自激振荡。
    private var dragAnchor: (mouse: NSPoint, origin: NSPoint)?
    private var dragged = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero,
                               options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    // MARK: 悬停跟随

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard dragAnchor == nil else { return }
        look(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        guard dragAnchor == nil else { return }
        coord?.setLook(yaw: nil)     // 鼠标走了 → 转回散步/正面朝向
    }

    /// 光标在右 → 猫朝右（+yaw）；在上 → 抬头。纵向中性点取猫头所在高度（约 62%），
    /// 光标平视猫头时不抬也不低。
    private func look(at p: NSPoint) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let ux = Double(p.x / bounds.width).clamped(to: 0...1)
        let uy = Double(p.y / bounds.height).clamped(to: 0...1)
        coord?.setLook(yaw: (ux - 0.5) * 1.9, pitch: (uy - 0.62) * -0.45)
    }

    // MARK: 左键：拖动挪窝 / 点击互动

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        dragAnchor = (NSEvent.mouseLocation, window.frame.origin)
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor = dragAnchor, let window else { return }
        let m = NSEvent.mouseLocation
        let dx = m.x - anchor.mouse.x, dy = m.y - anchor.mouse.y
        if abs(dx) + abs(dy) > 3 { dragged = true }
        guard dragged else { return }
        window.setFrameOrigin(NSPoint(x: anchor.origin.x + dx, y: anchor.origin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let wasDragging = dragAnchor != nil
        dragAnchor = nil
        guard wasDragging else { return }
        if dragged {
            onDragEnd()                       // 记住新位置、缓一会儿再自己溜达
        } else if let coord {
            coord.tap(at: p, in: self)        // 命中猫身才算戳它（空白处点击不响应）
            look(at: p)
        }
    }

    // MARK: 滚轮缩放 / 右键菜单

    override func scrollWheel(with event: NSEvent) {
        // 触控板的精确滚动一格才几点，鼠标滚轮一格好几十，除掉差异再交给宿主
        let raw = Double(event.scrollingDeltaY)
        let delta = event.hasPreciseScrollingDeltas ? raw / 6 : raw
        guard delta != 0 else { return }
        onZoom(delta)
    }

    override func rightMouseDown(with event: NSEvent) {
        FileHandle.standardError.write(Data("[desk] rightMouseDown\n".utf8))
        onSecondaryClick()
    }

    override func rightMouseUp(with event: NSEvent) {
        FileHandle.standardError.write(Data("[desk] rightMouseUp\n".utf8))
    }

    /// 右键交给 onSecondaryClick 自己 popUp，别让 AppKit 再走一遍默认菜单流程
    override func menu(for event: NSEvent) -> NSMenu? {
        FileHandle.standardError.write(Data("[desk] menu(for:) 被问了\n".utf8))
        return nil
    }
}
#endif
