import SwiftUI
import SceneKit
import simd

// MARK: - 3D 卡通猫（汤姆猫风写实卡通，SceneKit 几何体拼装，无需模型资源）
//
// 从 ios_app 的 TomCatView 抽出，去 UIKit 化：颜色/字体用 PlatformColor/PlatformFont，
// 渲染容器在 iOS 用 UIViewRepresentable、macOS 用 NSViewRepresentable，共用同一 Coordinator。

public enum CatScene {

    // MARK: 卡通猫配色

    static let furColor = PlatformColor(red: 0.97, green: 0.63, blue: 0.28, alpha: 1)    // 暖橘
    static let stripeColor = PlatformColor(red: 0.89, green: 0.52, blue: 0.23, alpha: 1) // 深橘虎斑
    static let creamColor = PlatformColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1)  // 奶白
    static let pinkColor = PlatformColor(red: 0.95, green: 0.62, blue: 0.66, alpha: 1)
    static let blushColor = PlatformColor(red: 0.99, green: 0.78, blue: 0.74, alpha: 1)  // 腮红
    static let eyeGreen = PlatformColor(red: 0.40, green: 0.75, blue: 0.34, alpha: 1)
    static let darkColor = PlatformColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)

    /// gloss: 0=哑光绒毛, 1=水润高光（眼睛/鼻头）
    static func mat(_ color: PlatformColor, gloss: CGFloat = 0.1) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.lightingModel = .blinn
        m.specular.contents = PlatformColor(white: gloss, alpha: 1)
        m.shininess = max(0.05, gloss)
        return m
    }

    static func node(_ geometry: SCNGeometry, _ color: PlatformColor,
                     pos: SCNVector3,
                     scale: SCNVector3 = SCNVector3(1, 1, 1),
                     euler: SCNVector3 = SCNVector3(0, 0, 0),
                     gloss: CGFloat = 0.1) -> SCNNode {
        geometry.materials = [mat(color, gloss: gloss)]
        let n = SCNNode(geometry: geometry)
        n.position = pos
        n.scale = scale
        n.eulerAngles = euler
        return n
    }

    // MARK: 场景构建

    public static func buildScene(outfit: Outfit) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = PlatformColor.clear
        // 转盘层：鼠标环视只旋转 turntable，行为动画只操作其中的 cat/bowl，两者互不打架。
        let turntable = SCNNode()
        turntable.name = "turntable"
        turntable.addChildNode(buildCatNode(outfit: outfit))
        scene.rootNode.addChildNode(turntable)

        let pivot = SCNNode()
        pivot.position = SCNVector3(0, 1.7, 0)
        scene.rootNode.addChildNode(pivot)

        let camNode = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = 40   // 长焦减畸变，更像产品渲染
        camera.screenSpaceAmbientOcclusionIntensity = 0.6
        camera.screenSpaceAmbientOcclusionRadius = 0.8
        camNode.camera = camera
        camNode.position = SCNVector3(3.6, 4.3, 14.2)
        camNode.constraints = [SCNLookAtConstraint(target: pivot)]
        scene.rootNode.addChildNode(camNode)

        // 柔和的卡通三点光 + 真实软阴影
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.color = PlatformColor(white: 1.0, alpha: 1)
        key.light?.castsShadow = true
        key.light?.shadowMode = .deferred
        key.light?.shadowColor = PlatformColor(white: 0, alpha: 0.3)
        key.light?.shadowRadius = 9
        key.light?.shadowSampleCount = 16
        key.eulerAngles = SCNVector3(-Float.pi / 4, -Float.pi / 6, 0)
        scene.rootNode.addChildNode(key)

        // 隐形接影地面：只显示影子不显示自身
        let floorGeo = SCNFloor()
        floorGeo.reflectivity = 0
        let floorMat = SCNMaterial()
        floorMat.lightingModel = .constant
        floorMat.writesToDepthBuffer = true
        floorMat.colorBufferWriteMask = []
        floorGeo.materials = [floorMat]
        let floor = SCNNode(geometry: floorGeo)
        floor.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(floor)

        // 食碗（吃饭行为时显示）
        let bowl = SCNNode()
        bowl.name = "bowl"
        bowl.isHidden = true
        bowl.position = SCNVector3(0, 0, 3.2)
        bowl.addChildNode(node(SCNCylinder(radius: 0.78, height: 0.42),
                               PlatformColor(red: 0.36, green: 0.62, blue: 0.66, alpha: 1),
                               pos: SCNVector3(0, 0.21, 0)))
        bowl.addChildNode(node(SCNTorus(ringRadius: 0.74, pipeRadius: 0.09),
                               PlatformColor(red: 0.30, green: 0.54, blue: 0.58, alpha: 1),
                               pos: SCNVector3(0, 0.43, 0)))
        for (dx, dz, r) in [(Float(0), Float(0), Float(0.17)),
                            (Float(0.25), Float(0.12), Float(0.14)),
                            (Float(-0.22), Float(0.15), Float(0.13)),
                            (Float(0.1), Float(-0.22), Float(0.14)),
                            (Float(-0.15), Float(-0.18), Float(0.12))] {
            bowl.addChildNode(node(SCNSphere(radius: CGFloat(r)),
                                   PlatformColor(red: 0.62, green: 0.42, blue: 0.25, alpha: 1),
                                   pos: SCNVector3(dx, 0.46, dz)))
        }
        turntable.addChildNode(bowl)   // 碗随转盘一起转，环视吃饭姿势不脱节

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.color = PlatformColor(white: 0.35, alpha: 1)
        fill.eulerAngles = SCNVector3(-Float.pi / 8, Float.pi * 0.75, 0)
        scene.rootNode.addChildNode(fill)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.color = PlatformColor(red: 1.0, green: 0.93, blue: 0.82, alpha: 1).withAlphaComponent(0.5)
        rim.eulerAngles = SCNVector3(-Float.pi / 5, Float.pi, 0)
        scene.rootNode.addChildNode(rim)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = PlatformColor(white: 0.52, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        return scene
    }

    /// 放样生成一根渐细弯曲的连续锥形尾巴：虎斑环纹与奶白尾尖用顶点颜色画出。
    static func makeTailNode() -> SCNNode {
        let lengthSegs = 18
        let radialSegs = 12

        func rgba(_ c: PlatformColor) -> simd_float4 {
            let (r, g, b, a) = c.rgbaComponents()
            return simd_float4(Float(r), Float(g), Float(b), Float(a))
        }

        var centers: [simd_float3] = []
        var radii: [Float] = []
        var ringColors: [simd_float4] = []
        for i in 0...lengthSegs {
            let t = Float(i) / Float(lengthSegs)
            let z = 2.2 * t
            let x = 0.30 * sin(t * .pi * 0.7)
            let y = 0.05 * t + (t > 0.6 ? (t - 0.6) * (t - 0.6) * 3.0 : 0)
            centers.append(simd_float3(x, y, z))
            radii.append(0.27 - 0.085 * t - (t > 0.85 ? (t - 0.85) * 0.6 : 0))
            let c: PlatformColor
            if t > 0.9 { c = creamColor }
            else if abs(t - 0.22) < 0.04 || abs(t - 0.44) < 0.04
                 || abs(t - 0.66) < 0.04 || abs(t - 0.85) < 0.04 { c = stripeColor }
            else { c = furColor }
            ringColors.append(rgba(c))
        }

        var verts: [SCNVector3] = []
        var norms: [SCNVector3] = []
        var cols: [simd_float4] = []
        var idx: [Int32] = []
        let n = centers.count

        for i in 0..<n {
            let tangent: simd_float3
            if i == 0 { tangent = simd_normalize(centers[1] - centers[0]) }
            else if i == n - 1 { tangent = simd_normalize(centers[n - 1] - centers[n - 2]) }
            else { tangent = simd_normalize(centers[i + 1] - centers[i - 1]) }
            var up = simd_float3(0, 1, 0)
            if abs(simd_dot(tangent, up)) > 0.9 { up = simd_float3(1, 0, 0) }
            let side = simd_normalize(simd_cross(tangent, up))
            let realUp = simd_normalize(simd_cross(side, tangent))
            for j in 0..<radialSegs {
                let a = Float(j) / Float(radialSegs) * 2 * .pi
                let dir = side * cos(a) + realUp * sin(a)
                let p = centers[i] + dir * radii[i]
                verts.append(SCNVector3(p.x, p.y, p.z))
                norms.append(SCNVector3(dir.x, dir.y, dir.z))
                cols.append(ringColors[i])
            }
        }
        for i in 0..<(n - 1) {
            for j in 0..<radialSegs {
                let j2 = (j + 1) % radialSegs
                let a = Int32(i * radialSegs + j)
                let b = Int32(i * radialSegs + j2)
                let c = Int32((i + 1) * radialSegs + j2)
                let d = Int32((i + 1) * radialSegs + j)
                idx += [a, d, b, b, d, c]
            }
        }
        let tipDir = simd_normalize(centers[n - 1] - centers[n - 2])
        let tip = centers[n - 1] + tipDir * radii[n - 1]
        let tipIdx = Int32(verts.count)
        verts.append(SCNVector3(tip.x, tip.y, tip.z))
        norms.append(SCNVector3(tipDir.x, tipDir.y, tipDir.z))
        cols.append(ringColors[n - 1])
        for j in 0..<radialSegs {
            let j2 = (j + 1) % radialSegs
            idx += [Int32((n - 1) * radialSegs + j), tipIdx, Int32((n - 1) * radialSegs + j2)]
        }

        let vSrc = SCNGeometrySource(vertices: verts)
        let nSrc = SCNGeometrySource(normals: norms)
        let cData = cols.withUnsafeBytes { Data($0) }
        let cSrc = SCNGeometrySource(data: cData, semantic: .color, vectorCount: cols.count,
                                     usesFloatComponents: true, componentsPerVector: 4,
                                     bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                     dataStride: MemoryLayout<simd_float4>.stride)
        let elem = SCNGeometryElement(indices: idx, primitiveType: .triangles)
        let geo = SCNGeometry(sources: [vSrc, nSrc, cSrc], elements: [elem])

        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = PlatformColor.white
        m.specular.contents = PlatformColor(white: 0.12, alpha: 1)
        m.shininess = 0.1
        m.isDoubleSided = true
        geo.materials = [m]
        return SCNNode(geometry: geo)
    }

    // MARK: 卡通猫造型（几何体拼装，无需模型资源）

    public static func buildCatNode(outfit: Outfit) -> SCNNode {
        let container = SCNNode()
        container.name = "cat"

        // ---- 身体（趴姿"长面包"，轴心在地面）----
        let body = SCNNode()
        body.name = "body"
        body.addChildNode(node(SCNSphere(radius: 1.5), furColor,
                               pos: SCNVector3(0, 1.02, -0.45), scale: SCNVector3(1.08, 0.72, 1.52)))
        body.addChildNode(node(SCNSphere(radius: 0.95), furColor,
                               pos: SCNVector3(0, 1.0, 0.55), scale: SCNVector3(1.0, 0.9, 0.9)))
        body.addChildNode(node(SCNSphere(radius: 0.85), creamColor,
                               pos: SCNVector3(0, 1.05, 0.95), scale: SCNVector3(0.85, 0.85, 0.5)))
        body.addChildNode(node(SCNSphere(radius: 1.0), furColor,
                               pos: SCNVector3(0, 1.55, 0.8), scale: SCNVector3(0.92, 0.78, 0.78)))
        body.addChildNode(node(SCNSphere(radius: 0.78), furColor,
                               pos: SCNVector3(-0.92, 0.8, -1.35), scale: SCNVector3(1, 0.8, 1.15)))
        body.addChildNode(node(SCNSphere(radius: 0.78), furColor,
                               pos: SCNVector3(0.92, 0.8, -1.35), scale: SCNVector3(1, 0.8, 1.15)))
        // 趴姿前肢（走路时隐藏）
        let lyingLimbs = SCNNode()
        lyingLimbs.name = "lyingLimbs"
        for sx in [-1.0, 1.0] {
            let x = Float(sx)
            lyingLimbs.addChildNode(node(SCNCapsule(capRadius: 0.24, height: 1.3), furColor,
                                         pos: SCNVector3(x * 0.4, 0.35, 0.95),
                                         euler: SCNVector3(Float.pi / 2, 0, 0)))
            lyingLimbs.addChildNode(node(SCNSphere(radius: 0.34), creamColor,
                                         pos: SCNVector3(x * 0.4, 0.33, 1.6),
                                         scale: SCNVector3(1, 0.8, 1.25)))
        }
        body.addChildNode(lyingLimbs)

        // 站立四肢（走路时长出来）
        let legs = SCNNode()
        legs.name = "legs"
        legs.isHidden = true
        func makeLeg(_ name: String, x: Float, z: Float) -> SCNNode {
            let leg = SCNNode()
            leg.name = name
            leg.position = SCNVector3(x, 1.05, z)
            leg.addChildNode(node(SCNCapsule(capRadius: 0.2, height: 1.5), furColor,
                                  pos: SCNVector3(0, -0.7, 0)))
            leg.addChildNode(node(SCNSphere(radius: 0.27), creamColor,
                                  pos: SCNVector3(0, -1.42, 0), scale: SCNVector3(1, 0.7, 1.25)))
            return leg
        }
        legs.addChildNode(makeLeg("legFL", x: -0.5, z: 0.75))
        legs.addChildNode(makeLeg("legFR", x: 0.5, z: 0.75))
        legs.addChildNode(makeLeg("legBL", x: -0.8, z: -1.2))
        legs.addChildNode(makeLeg("legBR", x: 0.8, z: -1.2))
        body.addChildNode(legs)
        // 呼吸起伏
        let inhale = SCNAction.scale(to: 1.03, duration: 1.6); inhale.timingMode = .easeInEaseOut
        let exhale = SCNAction.scale(to: 1.0, duration: 1.6); exhale.timingMode = .easeInEaseOut
        body.runAction(.repeatForever(.sequence([inhale, exhale])))
        container.addChildNode(body)

        // ---- 头 ----
        let head = SCNNode()
        head.name = "head"
        head.position = SCNVector3(0, 2.35, 1.05)
        head.addChildNode(node(SCNSphere(radius: 1.5), furColor,
                               pos: SCNVector3(0, 0, 0), scale: SCNVector3(1.06, 0.98, 0.94)))
        // 圆短耳：外橘内粉，右耳隔几秒抖一下
        for sx in [-1.0, 1.0] {
            let x = Float(sx)
            let ear = SCNNode()
            ear.position = SCNVector3(x * 0.78, 1.25, 0)
            ear.eulerAngles = SCNVector3(0, 0, -x * 0.32)
            ear.addChildNode(node(SCNCone(topRadius: 0.1, bottomRadius: 0.5, height: 0.62), furColor,
                                  pos: SCNVector3(0, 0, 0)))
            ear.addChildNode(node(SCNCone(topRadius: 0.05, bottomRadius: 0.28, height: 0.4), pinkColor,
                                  pos: SCNVector3(-x * 0.03, -0.05, 0.16)))
            if sx > 0 {
                ear.runAction(.repeatForever(.sequence([
                    .wait(duration: 3.5),
                    .rotateBy(x: 0, y: 0, z: -0.3, duration: 0.07),
                    .rotateBy(x: 0, y: 0, z: 0.3, duration: 0.12),
                    .wait(duration: 5.0),
                    .rotateBy(x: 0, y: 0, z: -0.2, duration: 0.07),
                    .rotateBy(x: 0, y: 0, z: 0.2, duration: 0.1),
                ])))
            }
            head.addChildNode(ear)
        }
        // 额头经典"M"虎斑纹
        for (dx, dy, h) in [(Float(-0.42), Float(0.78), Float(0.55)),
                            (Float(0), Float(0.9), Float(0.65)),
                            (Float(0.42), Float(0.78), Float(0.55))] {
            head.addChildNode(node(SCNSphere(radius: 0.3), stripeColor,
                                   pos: SCNVector3(dx, dy, 0.92),
                                   scale: SCNVector3(0.32, h, 0.42)))
        }
        // 水汪大眼
        for sx in [-1.0, 1.0] {
            let x = Float(sx)
            head.addChildNode(node(SCNSphere(radius: 0.475), stripeColor,
                                   pos: SCNVector3(x * 0.5, 0.12, 1.02), scale: SCNVector3(1, 1.2, 0.55)))
            head.addChildNode(node(SCNSphere(radius: 0.44), creamColor,
                                   pos: SCNVector3(x * 0.5, 0.12, 1.06), scale: SCNVector3(1, 1.2, 0.6),
                                   gloss: 0.55))
            head.addChildNode(node(SCNSphere(radius: 0.25), eyeGreen,
                                   pos: SCNVector3(x * 0.5, 0.1, 1.3), gloss: 0.95))
            head.addChildNode(node(SCNSphere(radius: 0.14), darkColor,
                                   pos: SCNVector3(x * 0.5, 0.09, 1.42), gloss: 0.95))
            let sparkleBig = node(SCNSphere(radius: 0.06), creamColor,
                                  pos: SCNVector3(x * 0.42, 0.22, 1.5))
            sparkleBig.geometry?.firstMaterial?.lightingModel = .constant
            head.addChildNode(sparkleBig)
            let sparkleSmall = node(SCNSphere(radius: 0.03), creamColor,
                                    pos: SCNVector3(x * 0.58, 0.0, 1.5))
            sparkleSmall.geometry?.firstMaterial?.lightingModel = .constant
            head.addChildNode(sparkleSmall)
        }
        // 闭眼皮（睡觉时盖住眼睛）
        let eyelids = SCNNode()
        eyelids.name = "eyelids"
        eyelids.isHidden = true
        for sx in [-1.0, 1.0] {
            let x = Float(sx)
            eyelids.addChildNode(node(SCNSphere(radius: 0.5), furColor,
                                      pos: SCNVector3(x * 0.5, 0.12, 1.12),
                                      scale: SCNVector3(1, 1.25, 0.95)))
        }
        head.addChildNode(eyelids)
        // 粉腮红 + 脸颊绒毛
        for sx in [-1.0, 1.0] {
            let x = Float(sx)
            head.addChildNode(node(SCNSphere(radius: 0.21), blushColor,
                                   pos: SCNVector3(x * 0.98, -0.32, 1.02),
                                   scale: SCNVector3(1.35, 0.68, 0.4)))
            head.addChildNode(node(SCNSphere(radius: 0.52), furColor,
                                   pos: SCNVector3(x * 1.32, -0.42, 0.42),
                                   scale: SCNVector3(0.62, 0.5, 0.62)))
        }
        // 小巧口鼻
        head.addChildNode(node(SCNSphere(radius: 0.4), creamColor,
                               pos: SCNVector3(0, -0.52, 1.05), scale: SCNVector3(1.15, 0.7, 0.55)))
        head.addChildNode(node(SCNSphere(radius: 0.09), pinkColor,
                               pos: SCNVector3(0, -0.32, 1.42), gloss: 0.9))
        // 短胡须
        for sx in [-1.0, 1.0] {
            let x = Float(sx)
            for (dy, tilt) in [(Float(0.1), Float(0.12)), (Float(-0.02), Float(0.0)), (Float(-0.14), Float(-0.12))] {
                head.addChildNode(node(SCNCylinder(radius: 0.013, height: 0.85), darkColor,
                                       pos: SCNVector3(x * 1.05, -0.48 + dy, 1.0),
                                       euler: SCNVector3(0, 0, Float.pi / 2 + x * tilt)))
            }
        }
        if let dress = buildOutfitNode(outfit), dress.name == "outfit-head" {
            head.addChildNode(dress)
        }
        container.addChildNode(head)

        if let dress = buildOutfitNode(outfit), dress.name == "outfit-body" {
            body.addChildNode(dress)
        }

        // ---- 尾巴 ----
        let tail = SCNNode()
        tail.name = "tail"
        tail.position = SCNVector3(0.75, 0.32, -1.5)
        tail.addChildNode(makeTailNode())
        let swishL = SCNAction.rotateBy(x: 0, y: 0.45, z: 0, duration: 1.4); swishL.timingMode = .easeInEaseOut
        let swishR = SCNAction.rotateBy(x: 0, y: -0.45, z: 0, duration: 1.4); swishR.timingMode = .easeInEaseOut
        tail.runAction(.repeatForever(.sequence([swishL, swishR])))
        container.addChildNode(tail)

        // 睡觉 Z 字泡泡
        let zzz = SCNNode()
        zzz.name = "zzz"
        zzz.isHidden = true
        zzz.position = SCNVector3(1.2, 3.9, 1.0)
        for i in 0..<3 {
            let textGeo = SCNText(string: "Z", extrusionDepth: 0.5)
            textGeo.font = PlatformFont.boldSystemFont(ofSize: 10)
            textGeo.flatness = 0.3
            textGeo.materials = [mat(stripeColor)]
            let zNode = SCNNode(geometry: textGeo)
            let s = Float(0.10 + Double(i) * 0.03)
            zNode.scale = SCNVector3(s, s, s)
            let base = SCNVector3(Float(i) * 0.35, Float(i) * 0.5, 0)
            zNode.position = base
            zNode.opacity = 0
            let cycle = SCNAction.sequence([
                .wait(duration: Double(i) * 0.6),
                .run { n in n.position = base; n.opacity = 0 },
                .fadeIn(duration: 0.35),
                .group([
                    .moveBy(x: 0.4, y: 1.4, z: 0, duration: 2.0),
                    .sequence([.wait(duration: 1.0), .fadeOut(duration: 0.9)]),
                ]),
            ])
            zNode.runAction(.repeatForever(cycle))
            zzz.addChildNode(zNode)
        }
        container.addChildNode(zzz)

        // 接地软阴影
        let shadow = node(SCNSphere(radius: 1.0), PlatformColor.black,
                          pos: SCNVector3(0.2, 0.02, -0.2), scale: SCNVector3(2.4, 0.03, 2.7))
        shadow.geometry?.firstMaterial?.lightingModel = .constant
        shadow.geometry?.firstMaterial?.transparency = 0.13
        container.addChildNode(shadow)

        return container
    }

    /// 配饰立体造型：帽类挂头上（跟着点头动），围巾/项圈挂身上。
    /// 与 RiggedCat.buildAccessory 同款设计语言：主色 + 金属/镜片局部配色。
    static func buildOutfitNode(_ outfit: Outfit) -> SCNNode? {
        let group = SCNNode()
        let c = outfit.platformColor
        let gold = PlatformColor(red: 0.93, green: 0.76, blue: 0.28, alpha: 1)
        switch outfit {
        case .none:
            return nil
        case .beret:
            group.name = "outfit-head"
            let darkWine = PlatformColor(red: 0.60, green: 0.15, blue: 0.21, alpha: 1)
            group.addChildNode(node(SCNTorus(ringRadius: 0.82, pipeRadius: 0.16), darkWine,
                                    pos: SCNVector3(0.08, 1.05, 0.05),
                                    euler: SCNVector3(0, 0, -0.15)))
            group.addChildNode(node(SCNSphere(radius: 1.1), c,
                                    pos: SCNVector3(0.12, 1.2, 0.05),
                                    scale: SCNVector3(1.05, 0.4, 1.05),
                                    euler: SCNVector3(0, 0, -0.18)))
            group.addChildNode(node(SCNCapsule(capRadius: 0.08, height: 0.3), darkWine,
                                    pos: SCNVector3(0.2, 1.62, 0.05),
                                    euler: SCNVector3(0, 0, -0.18)))
        case .crown:
            group.name = "outfit-head"
            group.addChildNode(node(SCNCylinder(radius: 0.65, height: 0.42), c,
                                    pos: SCNVector3(0, 1.45, 0), gloss: 0.85))
            group.addChildNode(node(SCNTorus(ringRadius: 0.65, pipeRadius: 0.08), c,
                                    pos: SCNVector3(0, 1.66, 0), gloss: 0.85))
            let gems: [(Float, Float, PlatformColor)] = [
                (0.48, 0, PlatformColor(red: 0.85, green: 0.20, blue: 0.25, alpha: 1)),
                (-0.48, 0, PlatformColor(red: 0.25, green: 0.45, blue: 0.85, alpha: 1)),
                (0, 0.48, PlatformColor(red: 0.30, green: 0.72, blue: 0.40, alpha: 1)),
                (0, -0.48, PlatformColor(red: 0.65, green: 0.35, blue: 0.80, alpha: 1)),
            ]
            for (dx, dz, gemColor) in gems {
                group.addChildNode(node(SCNCone(topRadius: 0.01, bottomRadius: 0.14, height: 0.36), c,
                                        pos: SCNVector3(dx, 1.83, dz), gloss: 0.85))
                group.addChildNode(node(SCNSphere(radius: 0.08), gemColor,
                                        pos: SCNVector3(dx, 2.05, dz), gloss: 0.95))
            }
            group.addChildNode(node(SCNSphere(radius: 0.11),
                                    PlatformColor(red: 0.85, green: 0.20, blue: 0.25, alpha: 1),
                                    pos: SCNVector3(0, 1.45, 0.63), gloss: 0.95))
        case .bow:
            group.name = "outfit-head"
            let lightPink = PlatformColor(red: 0.99, green: 0.68, blue: 0.80, alpha: 1)
            for sx in [-1.0, 1.0] {
                group.addChildNode(node(SCNSphere(radius: 0.3), c,
                                        pos: SCNVector3(0.78 + Float(sx) * 0.32, 1.12, 0.42),
                                        scale: SCNVector3(1, 0.72, 0.55), gloss: 0.4))
                group.addChildNode(node(SCNCapsule(capRadius: 0.09, height: 0.34), c,
                                        pos: SCNVector3(0.78 + Float(sx) * 0.12, 0.84, 0.42),
                                        euler: SCNVector3(0, 0, Float(sx) * -0.4), gloss: 0.4))
            }
            group.addChildNode(node(SCNSphere(radius: 0.16), lightPink,
                                    pos: SCNVector3(0.78, 1.12, 0.5), gloss: 0.5))
        case .glasses:
            // 脸面椭球在眼位 z≈1.34，镜片平面要顶到 z≈1.42 才不被埋
            group.name = "outfit-head"
            let dark = PlatformColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1)
            for sx in [-1.0, 1.0] {
                group.addChildNode(node(SCNSphere(radius: 0.40), dark,
                                        pos: SCNVector3(Float(sx) * 0.5, 0.12, 1.42),
                                        scale: SCNVector3(1, 1, 0.30), gloss: 0.95))
                group.addChildNode(node(SCNTorus(ringRadius: 0.42, pipeRadius: 0.045), gold,
                                        pos: SCNVector3(Float(sx) * 0.5, 0.12, 1.45),
                                        euler: SCNVector3(Float.pi / 2, 0, 0), gloss: 0.8))
                group.addChildNode(node(SCNCylinder(radius: 0.04, height: 0.8), gold,
                                        pos: SCNVector3(Float(sx) * 0.98, 0.16, 0.85),
                                        euler: SCNVector3(Float.pi / 2, Float(sx) * -0.18, 0), gloss: 0.8))
            }
            group.addChildNode(node(SCNCylinder(radius: 0.04, height: 0.28), gold,
                                    pos: SCNVector3(0, 0.16, 1.45),
                                    euler: SCNVector3(0, 0, Float.pi / 2), gloss: 0.8))
        case .scarf:
            // 脖围在头球与身体球交界（趴姿身体球前沿 z≈1.83），要围大圈并前压
            group.name = "outfit-body"
            group.addChildNode(node(SCNTorus(ringRadius: 1.15, pipeRadius: 0.24), c,
                                    pos: SCNVector3(0, 1.85, 0.95),
                                    euler: SCNVector3(0.55, 0, 0)))
            group.addChildNode(node(SCNTorus(ringRadius: 1.15, pipeRadius: 0.11), creamColor,
                                    pos: SCNVector3(0, 2.02, 0.88),
                                    euler: SCNVector3(0.55, 0, 0)))
            group.addChildNode(node(SCNCapsule(capRadius: 0.18, height: 0.8), c,
                                    pos: SCNVector3(0.40, 1.05, 1.95),
                                    euler: SCNVector3(0.30, 0, 0.12)))
            for (i, fx) in [Float(0.26), 0.40, 0.54].enumerated() {
                group.addChildNode(node(SCNCylinder(radius: 0.045, height: 0.22), creamColor,
                                        pos: SCNVector3(fx, 0.62, 2.06 + Float(i % 2) * 0.04),
                                        euler: SCNVector3(0.30, 0, 0)))
            }
        case .collar:
            group.name = "outfit-body"
            group.addChildNode(node(SCNTorus(ringRadius: 1.08, pipeRadius: 0.14), c,
                                    pos: SCNVector3(0, 1.85, 1.02),
                                    euler: SCNVector3(0.58, 0, 0), gloss: 0.35))
            group.addChildNode(node(SCNTorus(ringRadius: 0.09, pipeRadius: 0.03), gold,
                                    pos: SCNVector3(0, 1.44, 1.92),
                                    euler: SCNVector3(Float.pi / 2, 0, 0), gloss: 0.8))
            group.addChildNode(node(SCNSphere(radius: 0.18), gold,
                                    pos: SCNVector3(0, 1.28, 1.95), gloss: 0.9))
            group.addChildNode(node(SCNCapsule(capRadius: 0.02, height: 0.12),
                                    darkColor, pos: SCNVector3(0, 1.22, 2.12)))
        case .wizard:
            group.name = "outfit-head"
            group.addChildNode(node(SCNCylinder(radius: 0.88, height: 0.10), c,
                                    pos: SCNVector3(0, 1.30, 0)))
            group.addChildNode(node(SCNCone(topRadius: 0.05, bottomRadius: 0.54, height: 1.15), c,
                                    pos: SCNVector3(0, 1.90, 0)))
            group.addChildNode(node(SCNCylinder(radius: 0.56, height: 0.16), gold,
                                    pos: SCNVector3(0, 1.42, 0), gloss: 0.8))
            group.addChildNode(node(SCNSphere(radius: 0.10), gold,
                                    pos: SCNVector3(0.18, 2.46, 0), gloss: 0.8))
            for (sx, sy, sz) in [(Float(0.24), Float(1.72), Float(0.26)),
                                 (Float(-0.20), Float(1.98), Float(0.17)),
                                 (Float(0.08), Float(2.22), Float(0.12))] {
                group.addChildNode(node(SCNSphere(radius: 0.055), gold,
                                        pos: SCNVector3(sx, sy, sz), gloss: 0.9))
            }
        }
        return group
    }
}

// MARK: - 跨平台渲染容器

public struct CatSceneView {
    let outfit: Outfit
    let behavior: PetState.Behavior
    var onPart: (CatPart) -> Void

    public init(outfit: Outfit, behavior: PetState.Behavior,
                onPart: @escaping (CatPart) -> Void = { _ in }) {
        self.outfit = outfit
        self.behavior = behavior
        self.onPart = onPart
    }

    // 这三个辅助方法由 SwiftUI 的 make/updateNSView(UIView) 在主线程调用；但在 macOS
    // 上 NSViewRepresentable 的 witness 被推断为 nonisolated，直接访问 @MainActor 的
    // Coordinator 会报隔离错。用 assumeIsolated 显式声明「确在主线程」（SwiftUI 已保证）。
    func buildView(_ coord: Coordinator) -> SCNView {
        MainActor.assumeIsolated {
            #if canImport(UIKit)
            let view = SCNView()
            #else
            let view = HoverOrbitSCNView()
            #endif
            view.antialiasingMode = .multisampling4X
            view.autoenablesDefaultLighting = false
            view.allowsCameraControl = true
            view.scene = CatScene.buildScene(outfit: outfit)
            #if canImport(UIKit)
            view.backgroundColor = .clear
            #else
            // macOS 的 SCNView 走 CAMetalLayer，layer.backgroundColor 管不到渲染器的
            // 清屏色（那块不透明底就是它画的）；必须设 SCNView.backgroundColor 才真透明。
            view.backgroundColor = .clear
            view.wantsLayer = true
            view.layer?.isOpaque = false
            view.layer?.backgroundColor = PlatformColor.clear.cgColor
            #endif
            let tap = PlatformTapGesture(target: coord, action: #selector(Coordinator.tapped(_:)))
            view.addGestureRecognizer(tap)
            coord.apply(behavior: behavior, in: view)
            return view
        }
    }

    func refresh(_ view: SCNView, _ coord: Coordinator) {
        MainActor.assumeIsolated {
            coord.onPart = onPart
            if coord.outfit != outfit {
                coord.outfit = outfit
                view.scene?.rootNode.childNode(withName: "cat", recursively: true)?.removeFromParentNode()
                let host = view.scene?.rootNode.childNode(withName: "turntable", recursively: false)
                    ?? view.scene?.rootNode
                host?.addChildNode(CatScene.buildCatNode(outfit: outfit))
                coord.lastBehavior = nil
            }
            if coord.lastBehavior != behavior {
                coord.apply(behavior: behavior, in: view)
            }
        }
    }

    func makeCoord() -> Coordinator { MainActor.assumeIsolated { Coordinator(onPart: onPart, outfit: outfit) } }

    @MainActor
    public final class Coordinator: NSObject {
        var onPart: (CatPart) -> Void
        var outfit: Outfit
        var lastBehavior: PetState.Behavior?

        init(onPart: @escaping (CatPart) -> Void, outfit: Outfit) {
            self.onPart = onPart
            self.outfit = outfit
        }

        /// 命中测试：摸头 / 戳肚子 / 拽尾巴，各有各的反应。
        @objc func tapped(_ gesture: PlatformTapGesture) {
            guard let view = gesture.view as? SCNView else { return }
            let point = gesture.location(in: view)
            guard let hit = view.hitTest(point, options: nil).first else { return }
            var node: SCNNode? = hit.node
            while let nd = node {
                let part: CatPart?
                switch nd.name {
                case "head", "outfit-head": part = .head
                case "body", "outfit-body": part = .body
                case "tail": part = .tail
                default: part = nil
                }
                if let part {
                    animate(part, in: view)
                    onPart(part)
                    return
                }
                node = nd.parent
            }
        }

        private func animate(_ part: CatPart, in view: SCNView) {
            let name: String
            switch part {
            case .head: name = "head"
            case .body: name = "body"
            case .tail: name = "tail"
            }
            guard let node = view.scene?.rootNode.childNode(withName: name, recursively: true) else { return }
            switch part {
            case .head:
                node.runAction(.sequence([
                    .rotateBy(x: 0.3, y: 0, z: 0, duration: 0.12),
                    .rotateBy(x: -0.3, y: 0, z: 0, duration: 0.12),
                    .rotateBy(x: 0.3, y: 0, z: 0, duration: 0.12),
                    .rotateBy(x: -0.3, y: 0, z: 0, duration: 0.12),
                ]))
            case .body:
                node.runAction(.sequence([
                    .scale(to: 0.88, duration: 0.10),
                    .scale(to: 1.08, duration: 0.12),
                    .scale(to: 1.0, duration: 0.10),
                ]))
            case .tail:
                node.runAction(.repeat(.sequence([
                    .rotateBy(x: 0, y: 0.6, z: 0, duration: 0.08),
                    .rotateBy(x: 0, y: -0.6, z: 0, duration: 0.08),
                ]), count: 3))
            }
        }

        func apply(behavior: PetState.Behavior, in view: SCNView) {
            lastBehavior = behavior
            guard let scene = view.scene,
                  let cat = scene.rootNode.childNode(withName: "cat", recursively: true) else { return }
            let head = cat.childNode(withName: "head", recursively: false)
            let bowl = scene.rootNode.childNode(withName: "bowl", recursively: true)
            let zzz = cat.childNode(withName: "zzz", recursively: false)
            let eyelids = head?.childNode(withName: "eyelids", recursively: false)

            cat.removeAllActions()
            cat.position = SCNVector3(0, 0, 0)
            cat.eulerAngles = SCNVector3(0, 0, 0)
            cat.scale = SCNVector3(1, 1, 1)
            head?.removeAllActions()
            head?.runAction(.rotateTo(x: 0, y: 0, z: 0, duration: 0.2))

            bowl?.isHidden = behavior != .eating
            eyelids?.isHidden = behavior != .sleeping
            zzz?.isHidden = behavior != .sleeping

            func eased(_ a: SCNAction) -> SCNAction { a.timingMode = .easeInEaseOut; return a }

            let tail = cat.childNode(withName: "tail", recursively: false)
            let walking = behavior == .walking
            let legs = cat.childNode(withName: "legs", recursively: true)
            let lyingLimbs = cat.childNode(withName: "lyingLimbs", recursively: true)
            cat.position = SCNVector3(0, walking ? 0.6 : 0, 0)
            legs?.isHidden = !walking
            lyingLimbs?.isHidden = walking
            if !walking {
                for name in ["legFL", "legFR", "legBL", "legBR"] {
                    if let leg = cat.childNode(withName: name, recursively: true) {
                        leg.removeAllActions()
                        leg.eulerAngles = SCNVector3(0, 0, 0)
                    }
                }
            }
            if walking {
                tail?.runAction(eased(.rotateTo(x: -0.9, y: 0, z: 0, duration: 0.4)), forKey: "tailUp")
            } else {
                tail?.runAction(.rotateTo(x: 0, y: 0, z: 0, duration: 0.3), forKey: "tailDown")
            }

            switch behavior {
            case .idle:
                cat.runAction(.repeatForever(.sequence([
                    eased(.moveBy(x: 0, y: 0.18, z: 0, duration: 1.2)),
                    eased(.moveBy(x: 0, y: -0.18, z: 0, duration: 1.2)),
                ])), forKey: "float")
                cat.runAction(Self.idleVignettes(head: head, tail: tail), forKey: "vignettes")

            case .walking:
                let patrol = SCNAction.sequence([
                    eased(.rotateTo(x: 0, y: 0.85, z: 0, duration: 0.35)),
                    .moveBy(x: 2.3, y: 0, z: 0, duration: 2.4),
                    eased(.rotateTo(x: 0, y: -0.85, z: 0, duration: 0.6)),
                    .moveBy(x: -4.6, y: 0, z: 0, duration: 4.8),
                    eased(.rotateTo(x: 0, y: 0.85, z: 0, duration: 0.6)),
                    .moveBy(x: 2.3, y: 0, z: 0, duration: 2.4),
                ])
                cat.runAction(.repeatForever(patrol), forKey: "patrol")
                cat.runAction(.repeatForever(.sequence([
                    .moveBy(x: 0, y: 0.1, z: 0, duration: 0.18),
                    .moveBy(x: 0, y: -0.1, z: 0, duration: 0.18),
                ])), forKey: "trot")
                cat.runAction(.repeatForever(.sequence([
                    .rotateBy(x: 0, y: 0, z: 0.05, duration: 0.18),
                    .rotateBy(x: 0, y: 0, z: -0.10, duration: 0.36),
                    .rotateBy(x: 0, y: 0, z: 0.05, duration: 0.18),
                ])), forKey: "waddle")
                head?.runAction(eased(.rotateTo(x: -0.12, y: 0, z: 0, duration: 0.3)), forKey: "headUp")
                for (name, phase) in [("legFL", true), ("legBR", true),
                                      ("legFR", false), ("legBL", false)] {
                    guard let leg = cat.childNode(withName: name, recursively: true) else { continue }
                    let amp: CGFloat = 0.55
                    let swingF = eased(.rotateTo(x: amp, y: 0, z: 0, duration: 0.36))
                    let swingB = eased(.rotateTo(x: -amp, y: 0, z: 0, duration: 0.36))
                    let loop = SCNAction.repeatForever(.sequence(phase ? [swingF, swingB] : [swingB, swingF]))
                    leg.runAction(.sequence([
                        eased(.rotateTo(x: phase ? -amp : amp, y: 0, z: 0, duration: 0.18)),
                        loop,
                    ]), forKey: "swing")
                }

            case .eating:
                cat.runAction(eased(.moveBy(x: 0, y: 0, z: 0.5, duration: 0.5)))
                let chew = SCNAction.sequence([
                    .rotateBy(x: -0.07, y: 0, z: 0, duration: 0.09),
                    .rotateBy(x: 0.07, y: 0, z: 0, duration: 0.09),
                ])
                head?.runAction(.repeatForever(.sequence([
                    eased(.rotateBy(x: 0.5, y: 0, z: 0, duration: 0.35)),
                    .repeat(chew, count: 3),
                    eased(.rotateBy(x: -0.5, y: 0, z: 0, duration: 0.4)),
                    .wait(duration: 0.3, withRange: 0.4),
                ])), forKey: "eat")

            case .happy:
                cat.runAction(.repeatForever(.sequence([
                    eased(.scale(to: 0.93, duration: 0.1)),
                    eased(.scale(to: 1.0, duration: 0.08)),
                    eased(.moveBy(x: 0, y: 2.2, z: 0, duration: 0.2)),
                    eased(.moveBy(x: 0, y: -2.2, z: 0, duration: 0.22)),
                    .wait(duration: 0.2),
                ])))

            case .sleeping:
                head?.runAction(eased(.rotateTo(x: 0.22, y: 0, z: 0, duration: 0.6)), forKey: "settle")
                cat.runAction(.repeatForever(.sequence([
                    eased(.scale(to: 1.04, duration: 1.6)),
                    eased(.scale(to: 1.0, duration: 1.6)),
                ])))
            }
        }

        /// 待机随机小剧场：每隔 2~4 秒随机演一个，全部以 rotateTo 收尾保证回正。
        private static func idleVignettes(head: SCNNode?, tail: SCNNode?) -> SCNAction {
            func eased(_ a: SCNAction) -> SCNAction { a.timingMode = .easeInEaseOut; return a }
            return .repeatForever(.sequence([
                .wait(duration: 2.2, withRange: 2.0),
                .run { node in
                    guard let head, let tail else { return }
                    switch Int.random(in: 0..<5) {
                    case 0:
                        head.runAction(.sequence([
                            eased(.rotateTo(x: 0, y: 0.55, z: 0, duration: 0.4)),
                            .wait(duration: 0.5),
                            eased(.rotateTo(x: 0, y: -0.5, z: 0, duration: 0.55)),
                            .wait(duration: 0.45),
                            eased(.rotateTo(x: 0, y: 0, z: 0, duration: 0.4)),
                        ]), forKey: "vig")
                    case 1:
                        head.runAction(.sequence([
                            eased(.rotateTo(x: 0, y: 0, z: 0.3, duration: 0.35)),
                            .wait(duration: 0.8),
                            eased(.rotateTo(x: 0, y: 0, z: 0, duration: 0.35)),
                        ]), forKey: "vig")
                    case 2:
                        let lick = SCNAction.sequence([
                            .rotateBy(x: 0.1, y: 0, z: 0, duration: 0.11),
                            .rotateBy(x: -0.1, y: 0, z: 0, duration: 0.11),
                        ])
                        head.runAction(.sequence([
                            eased(.rotateTo(x: 0.35, y: 0.35, z: 0.1, duration: 0.3)),
                            .repeat(lick, count: 3),
                            eased(.rotateTo(x: 0, y: 0, z: 0, duration: 0.35)),
                        ]), forKey: "vig")
                    case 3:
                        tail.runAction(.repeat(.sequence([
                            .rotateBy(x: 0, y: 0.7, z: 0, duration: 0.09),
                            .rotateBy(x: 0, y: -0.7, z: 0, duration: 0.09),
                        ]), count: 4), forKey: "vig")
                    default:
                        node.runAction(.sequence([
                            eased(.moveBy(x: 0, y: 0.7, z: 0, duration: 0.16)),
                            eased(.moveBy(x: 0, y: -0.7, z: 0, duration: 0.16)),
                            .repeat(.sequence([
                                .rotateBy(x: 0, y: 0, z: 0.05, duration: 0.06),
                                .rotateBy(x: 0, y: 0, z: -0.05, duration: 0.06),
                            ]), count: 4),
                        ]), forKey: "vigBody")
                    }
                },
            ]))
        }
    }
}

#if canImport(UIKit)
extension CatSceneView: UIViewRepresentable {
    public func makeUIView(context: Context) -> SCNView { buildView(context.coordinator) }
    public func updateUIView(_ view: SCNView, context: Context) { refresh(view, context.coordinator) }
    public func makeCoordinator() -> Coordinator { makeCoord() }
}
#elseif canImport(AppKit)
extension CatSceneView: NSViewRepresentable {
    public func makeNSView(context: Context) -> SCNView { buildView(context.coordinator) }
    public func updateNSView(_ view: SCNView, context: Context) { refresh(view, context.coordinator) }
    public func makeCoordinator() -> Coordinator { makeCoord() }
}

// MARK: - 鼠标环视（macOS 桌宠）
//
// 鼠标在猫区域内移动即可环视：光标水平位置映射转盘 yaw（左右边缘接近看到背面）、
// 垂直位置映射小幅俯仰；移出后自动转回正面。只旋转 "turntable" 层，
// 行为动画（巡逻/浮动等）都挂在其中的 "cat" 节点上，两者叠加不冲突。
final class HoverOrbitSCNView: SCNView {
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero,
                               options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    private var turntable: SCNNode? {
        scene?.rootNode.childNode(withName: "turntable", recursively: false)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard bounds.width > 0, bounds.height > 0, let turntable else { return }
        let p = convert(event.locationInWindow, from: nil)
        let ux = min(1, max(0, p.x / bounds.width))
        let uy = min(1, max(0, p.y / bounds.height))   // AppKit y 轴向上
        let yaw = (0.5 - ux) * 4.4        // 全宽 ≈ ±126°，边缘能看到背面和尾巴
        let pitch = (uy - 0.5) * 0.5      // 上下小幅俯仰
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.12
        turntable.eulerAngles = SCNVector3(pitch, yaw, 0)
        SCNTransaction.commit()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        guard let turntable else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.55
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
        turntable.eulerAngles = SCNVector3(0, 0, 0)
        SCNTransaction.commit()
    }
}
#endif
