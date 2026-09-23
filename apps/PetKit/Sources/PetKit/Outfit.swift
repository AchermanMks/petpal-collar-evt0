import SwiftUI

public enum Outfit: String, CaseIterable, Identifiable, Sendable {
    case none, beret, crown, bow, glasses, scarf, collar, wizard

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .none: return "无"
        case .beret: return "贝雷帽"
        case .crown: return "皇冠"
        case .bow: return "蝴蝶结"
        case .glasses: return "墨镜"
        case .scarf: return "围巾"
        case .collar: return "铃铛项圈"
        case .wizard: return "巫师帽"
        }
    }

    /// 主色：2D 像素贴图整体着色 + 衣柜按钮用；3D 配饰在此基础上做多色细节。
    public var platformColor: PlatformColor {
        switch self {
        case .none: return .clear
        case .beret: return PlatformColor(red: 0.78, green: 0.22, blue: 0.28, alpha: 1)
        case .crown: return PlatformColor(red: 0.93, green: 0.76, blue: 0.28, alpha: 1)
        case .bow: return PlatformColor(red: 0.94, green: 0.42, blue: 0.62, alpha: 1)
        case .glasses: return PlatformColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1)
        case .scarf: return PlatformColor(red: 0.90, green: 0.45, blue: 0.18, alpha: 1)
        case .collar: return PlatformColor(red: 0.80, green: 0.16, blue: 0.20, alpha: 1)
        case .wizard: return PlatformColor(red: 0.28, green: 0.24, blue: 0.55, alpha: 1)
        }
    }

    public var color: Color { Color(platform: platformColor) }

    /// 帽类在 3D 里整圈包住头部，其它配饰只贴在脸前/身上。
    public var isHat: Bool { self == .beret || self == .crown || self == .wizard }
}
