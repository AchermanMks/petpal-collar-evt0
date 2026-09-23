import SwiftUI

// 深链接路由：小组件点「打开桌宠」会拉起 petpalair://pet，
// 视图层监听 openPetNonce（每次请求自增）跳到首页并进 3D 桌宠模式。
@MainActor
@Observable
final class PetRouter {
    private(set) var openPetNonce = 0
    func requestOpenPet() { openPetNonce += 1 }

    /// 「我的」页点等级卡 → 跳排行榜
    private(set) var openRatingNonce = 0
    func requestOpenRating() { openRatingNonce += 1 }

    /// 首页上滑 → 切到「发现」页并直接选中商城栏目（不再另开 ShopView 页面）
    private(set) var openShopNonce = 0
    func requestOpenShop() { openShopNonce += 1 }
}

@main
struct PetCollarApp: App {
    @State private var state = AppState()
    @State private var engine = AlertEngine()
    @State private var router = PetRouter()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("lastBaseURL") private var lastBaseURL: String = ""
    @AppStorage("themeMode") private var themeMode: ThemeMode = .dark   // 默认深色，用户可在「我的」切换

    var body: some Scene {
        WindowGroup {
            RootView()
                // 全局加粗：没写死 weight 的文字（.subheadline/.caption 等）一律 bold；
                // 写死 weight 的已在源码里统一提到 bold/heavy。放在根上，登录/引导/入口流一起覆盖
                .fontWeight(.bold)
                .preferredColorScheme(themeMode.colorScheme)   // 浅/深/跟随系统：所有动态色与材质一起切换
                .environment(state)
                .environment(engine)
                .environment(router)
                .onOpenURL { url in
                    // petpalair://pet —— 小组件「打开桌宠」深链接
                    if url.scheme == "petpalair" { router.requestOpenPet() }
                }
                .task {
                    await engine.requestAuthorization()
                    // AIR version: no silent connections to the legacy ESP32/backend.
                    // Collar transport is adapted below the unchanged UI.
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task { await state.refreshOnForeground() }
                    }
                }
                .onChange(of: state.status) { _, newStatus in
                    switch newStatus {
                    case .connected:
                        if let api = state.api {
                            engine.start(api: api, vlmEnabled: state.systemInfo?.capabilities.vlm ?? false)
                        }
                    case .disconnected, .failed:
                        engine.stop()
                    case .connecting, .reconnecting:
                        break
                    }
                }
        }
    }
}
