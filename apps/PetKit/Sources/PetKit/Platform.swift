import SwiftUI

// 跨平台别名：让同一份 SceneKit / 渲染代码在 iOS(UIKit) 和 macOS(AppKit) 都能编译。
#if canImport(UIKit)
import UIKit
public typealias PlatformColor = UIColor
public typealias PlatformFont = UIFont
typealias PlatformView = UIView
typealias PlatformTapGesture = UITapGestureRecognizer
#elseif canImport(AppKit)
import AppKit
public typealias PlatformColor = NSColor
public typealias PlatformFont = NSFont
typealias PlatformView = NSView
typealias PlatformTapGesture = NSClickGestureRecognizer
#endif

extension Color {
    /// 从平台原生色构造 SwiftUI Color（两端写法不同，统一封装）。
    init(platform color: PlatformColor) {
        #if canImport(UIKit)
        self.init(uiColor: color)
        #else
        self.init(nsColor: color)
        #endif
    }
}

extension PlatformColor {
    /// 取 RGBA 分量。NSColor 必须先转到 sRGB 色彩空间，否则 getRed 会断言失败。
    func rgbaComponents() -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(AppKit)
        let c = usingColorSpace(.sRGB) ?? self
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return (r, g, b, a)
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
