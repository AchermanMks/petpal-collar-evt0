import XCTest
import SceneKit
@testable import PetKit

/// 离屏渲染各配饰的检查图（非断言测试，产物写到 OUTFIT_RENDER_DIR）。
/// 用法：OUTFIT_RENDER_DIR=/path/to/dir swift test --filter OutfitRenderTests
final class OutfitRenderTests: XCTestCase {

    @MainActor
    func testRenderAllOutfits() async throws {
        #if os(macOS)
        guard let dirPath = ProcessInfo.processInfo.environment["OUTFIT_RENDER_DIR"] else {
            throw XCTSkip("未设置 OUTFIT_RENDER_DIR，跳过渲染")
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("无 Metal 设备")
        }
        let outDir = URL(fileURLWithPath: dirPath)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        for outfit in Outfit.allCases where outfit != .none {
            let coord = RiggedCatSceneView.Coordinator(onPart: { _ in })
            let scene = RiggedCatSceneView.buildScene(coord: coord)
            scene.background.contents = NSColor(white: 0.96, alpha: 1)
            coord.applyOutfit(outfit)

            let renderer = SCNRenderer(device: device, options: nil)
            renderer.scene = scene
            renderer.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: true)

            let img = renderer.snapshot(atTime: 0.4,
                                        with: CGSize(width: 480, height: 560),
                                        antialiasingMode: .multisampling4X)
            guard let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                XCTFail("\(outfit.rawValue) 快照编码失败"); continue
            }
            try png.write(to: outDir.appendingPathComponent("rigged_\(outfit.rawValue).png"))
        }
        #endif
    }

    @MainActor
    func testRenderVoxelOutfits() async throws {
        #if os(macOS)
        guard let dirPath = ProcessInfo.processInfo.environment["OUTFIT_RENDER_DIR"] else {
            throw XCTSkip("未设置 OUTFIT_RENDER_DIR，跳过渲染")
        }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("无 Metal 设备") }
        let outDir = URL(fileURLWithPath: dirPath)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        for outfit in Outfit.allCases where outfit != .none {
            let scene = CatScene.buildScene(outfit: outfit)
            scene.background.contents = NSColor(white: 0.96, alpha: 1)
            let renderer = SCNRenderer(device: device, options: nil)
            renderer.scene = scene
            renderer.pointOfView = scene.rootNode.childNodes.first { $0.camera != nil }

            let img = renderer.snapshot(atTime: 0.2,
                                        with: CGSize(width: 480, height: 560),
                                        antialiasingMode: .multisampling4X)
            guard let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                XCTFail("\(outfit.rawValue) 快照编码失败"); continue
            }
            try png.write(to: outDir.appendingPathComponent("voxel_\(outfit.rawValue).png"))
        }
        #endif
    }
}
