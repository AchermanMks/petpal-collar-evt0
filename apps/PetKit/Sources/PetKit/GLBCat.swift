import SceneKit
import SwiftUI
import GLTFKit2

// MARK: - Tripo 生成的品种猫（GLB + quadruped walk 动画）
//
// 与 RiggedCatSceneView 同一套场景骨架（spin → container 归一化 → 模型），
// 差异：GLB 走 GLTFKit2 转 SCNScene；glTF 规范是 Y-up，不需要 USDZ 那层 -90°X tilt。
// 动画只有 walk 一段（Tripo 四足预设目前仅 preset:quadruped:walk），
// 行为差异全靠播放速度表达：走路快放、待机慢放、睡觉暂停。
public struct GLBCatSceneView {
    let modelName: String          // PetKit 包资源名（不带 .glb）
    let animationSpeed: Double
    let facingYaw: Double          // 朝向修正：跟生成输入照片的拍摄角度走，逐模型标定
    let offset: SIMD3<Float>       // 位置补偿：蒙皮姿态中心≠bind bbox 中心，逐模型标定
    var onPart: (CatPart) -> Void

    public init(modelName: String,
                animationSpeed: Double = 1.0,
                facingYaw: Double = -.pi / 2,
                offset: SIMD3<Float> = [0, 0.5, 0],
                onPart: @escaping (CatPart) -> Void = { _ in }) {
        self.modelName = modelName
        self.animationSpeed = animationSpeed
        self.facingYaw = facingYaw
        self.offset = offset
        self.onPart = onPart
    }

    func buildView(_ coord: Coordinator) -> SCNView {
        MainActor.assumeIsolated {
            let view = SCNView()
            view.antialiasingMode = .multisampling4X
            view.autoenablesDefaultLighting = false
            view.allowsCameraControl = true
            view.backgroundColor = .clear
            #if canImport(AppKit)
            view.wantsLayer = true
            view.layer?.isOpaque = false
            view.layer?.backgroundColor = PlatformColor.clear.cgColor
            #endif
            view.scene = Self.buildScene(modelName: modelName, facingYaw: facingYaw,
                                         offset: offset, coord: coord)
            coord.setSpeed(animationSpeed)
            let tap = PlatformTapGesture(target: coord, action: #selector(Coordinator.tapped(_:)))
            view.addGestureRecognizer(tap)
            return view
        }
    }

    func refresh(_ view: SCNView, _ coord: Coordinator) {
        MainActor.assumeIsolated {
            coord.onPart = onPart
            coord.setSpeed(animationSpeed)
        }
    }

    func makeCoord() -> Coordinator { MainActor.assumeIsolated { Coordinator(onPart: onPart) } }

    // MARK: 场景搭建

    @MainActor
    static func buildScene(modelName: String, facingYaw: Double,
                           offset: SIMD3<Float>, coord: Coordinator) -> SCNScene {
        let scene = SCNScene()
        let spin = SCNNode()
        spin.name = "spin"
        spin.eulerAngles = SCNVector3(0, Float(facingYaw), 0)
        spin.position = SCNVector3(offset.x, offset.y, offset.z)
        scene.rootNode.addChildNode(spin)
        let container = SCNNode()
        container.name = "glbCat"
        spin.addChildNode(container)

        if let url = Bundle.module.url(forResource: modelName, withExtension: "glb"),
           let asset = try? GLTFAsset(url: url) {
            let source = GLTFSCNSceneSource(asset: asset)
            if let model = source.defaultScene {
                for child in model.rootNode.childNodes {
                    container.addChildNode(child)
                }
            }
            // 动画通道已绑定到上面那批节点，播放器挂 container 上统一控速
            for anim in source.animations {
                let player = anim.animationPlayer
                player.animation.repeatCount = .greatestFiniteMagnitude
                player.animation.usesSceneTimeBase = false
                container.addAnimationPlayer(player, forKey: anim.name)
                player.play()
                coord.players.append(player)
            }
            container.enumerateHierarchy { node, _ in
                if let skinner = node.skinner, coord.bones.isEmpty {
                    coord.bones = skinner.bones
                }
            }
            Self.normalize(container, targetSize: 1.7)   // 比 USDZ 猫(2.0)略小，别压住下方控件
            coord.container = container
        }

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

    /// 归一化：最大边 targetSize、脚底贴 y=0、居中
    @MainActor
    static func normalize(_ container: SCNNode, targetSize: Float) {
        let (bbMin, bbMax) = container.boundingBox
        let maxDim = max(Float(bbMax.x - bbMin.x), Float(bbMax.y - bbMin.y), Float(bbMax.z - bbMin.z))
        guard maxDim > 0 else { return }
        let s = targetSize / maxDim
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

        init(onPart: @escaping (CatPart) -> Void) { self.onPart = onPart }

        func setSpeed(_ speed: Double) {
            for p in players {
                p.speed = CGFloat(speed)
                // 速度归零直接暂停，避免个别设备 speed=0 仍在推帧
                if speed <= 0.01 { p.paused = true } else { p.paused = false }
            }
        }

        // 点击 → 最近骨骼分类部位。Tripo 骨骼命名不保证有语义，
        // 匹配不上一律按 body 处理（挤压反馈），不影响互动闭环。
        @objc func tapped(_ gesture: PlatformTapGesture) {
            guard let view = gesture.view as? SCNView else { return }
            guard let hit = view.hitTest(gesture.location(in: view), options: nil).first else { return }
            let hp = hit.worldCoordinates
            var best: CatPart = .body
            var bestDist = Float.greatestFiniteMagnitude
            for bone in bones {
                let bp = bone.presentation.worldPosition
                let dx = Float(bp.x - hp.x), dy = Float(bp.y - hp.y), dz = Float(bp.z - hp.z)
                let dist = dx * dx + dy * dy + dz * dz
                guard dist < bestDist, let name = bone.name?.lowercased() else { continue }
                bestDist = dist
                if name.contains("tail") { best = .tail }
                else if name.contains("head") || name.contains("neck")
                            || name.contains("skull") || name.contains("jaw")
                            || name.contains("ear") { best = .head }
                else { best = .body }
            }
            container?.runAction(.sequence([.scale(by: 0.95, duration: 0.10),
                                            .scale(by: 1.0 / 0.95, duration: 0.14)]))
            onPart(best)
        }
    }
}

#if canImport(UIKit)
extension GLBCatSceneView: UIViewRepresentable {
    public func makeUIView(context: Context) -> SCNView { buildView(context.coordinator) }
    public func updateUIView(_ view: SCNView, context: Context) { refresh(view, context.coordinator) }
    public func makeCoordinator() -> Coordinator { makeCoord() }
}
#elseif canImport(AppKit)
extension GLBCatSceneView: NSViewRepresentable {
    public func makeNSView(context: Context) -> SCNView { buildView(context.coordinator) }
    public func updateNSView(_ view: SCNView, context: Context) { refresh(view, context.coordinator) }
    public func makeCoordinator() -> Coordinator { makeCoord() }
}
#endif
