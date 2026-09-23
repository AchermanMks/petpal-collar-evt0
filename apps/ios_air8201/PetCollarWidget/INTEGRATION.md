# iOS 小组件接入指南

源码已就位，但 WidgetKit 扩展必须作为一个独立 **App Extension target** 存在于
Xcode 工程里（无法只靠源文件生效，也不该手改 `.pbxproj` 去拼一个扩展 target——
那一堆互相关联的 UUID 极易把工程改坏）。按下面 5 步在 Xcode 里点几下即可，约 3 分钟。

代码侧已经做好的部分：
- `PetCollarWidget/PetCollarWidget.swift` — 小组件全部逻辑（读 `PetSnapshot` 渲染，
  支持主屏 small/medium + 锁屏 rectangular/circular）。
- `PetCollarWidget/Info.plist`、`PetCollarWidget/PetCollarWidget.entitlements`。
- `PetCollar/PetCollar.entitlements` — 主 App 的 App Group。
- 主 App `TamagotchiView.swift` 已在主循环里 `PetSnapshotStore.save(...)` +
  `WidgetCenter.reloadAllTimelines()`（依赖 `import PetKit`）。

## 1. 把 PetKit 作为本地包加入工程

File ▸ Add Package Dependencies… ▸ Add Local… ▸ 选 `pet-collar/PetKit`。
加完把 **PetKit** 库链接到 **主 App target**（让 `TamagotchiView` 的 `import PetKit` 通过）。

## 2. 新建 Widget Extension target

File ▸ New ▸ Target… ▸ **Widget Extension** ▸ 命名 `PetCollarWidget`
（取消勾选 “Include Configuration Intent”）。Xcode 会生成一个模板文件夹——

- 删掉模板自动生成的 `.swift` / `Info.plist` / entitlements；
- 把本目录已写好的 `PetCollarWidget.swift`、`Info.plist`、
  `PetCollarWidget.entitlements` 加进这个新 target（Target Membership 勾 PetCollarWidget）；
- target 的 Build Settings 里 `INFOPLIST_FILE` 指向本目录的 `Info.plist`，
  `CODE_SIGN_ENTITLEMENTS` 指向本目录的 `PetCollarWidget.entitlements`。

## 3. 给 Widget target 链接 PetKit

选中 PetCollarWidget target ▸ General ▸ Frameworks and Libraries ▸ + ▸ **PetKit**。
（小组件要用 `PetSnapshot` / `PetSnapshotStore` / `Outfit`。）

## 4. 两个 target 都开 App Group

主 App target 和 PetCollarWidget target，各自 Signing & Capabilities ▸
+ Capability ▸ **App Groups** ▸ 勾选（或新增）`group.com.petcollar.PetCollar`。

> 必须与 `PetSnapshotStore.appGroupID`（`group.com.petcollar.PetCollar`）逐字一致，
> 否则主 App 写的快照小组件读不到。两个 target 用同一个 Team `BYYK5SMM2Y` 签名。

主 App 的 `CODE_SIGN_ENTITLEMENTS` 指向已建好的 `PetCollar/PetCollar.entitlements`。

## 5. 跑起来

1. Run 主 App，进电子宠物页停几秒——它会把 `PetSnapshot` 写进 App Group。
2. 回桌面长按 ▸ 添加小组件 ▸ 找「电子宠物」▸ 选 small/medium；锁屏同理加
   矩形/圆形小组件。
3. 小组件显示的饱食/心情/活力与 App 内一致即「同源」成功。喂食/互动后约 10s
   内小组件自动刷新（主 App 在前台时 `reloadAllTimelines` 推送）。

## 素材（猫的 16 帧 / App 图标）怎么重新生成

两者都是首页那只骨骼真猫 `cat_idle.usdz` 的离屏渲染产物，模型/装扮/机位改了就重跑，
别手工 P 图：

```bash
cd pet-collar/PetKit
WIDGET_FRAME_DIR=../ios_app/PetCollarWidget/Assets.xcassets \
APP_ICON_PATH=../ios_app/PetCollar/Assets.xcassets/AppIcon.appiconset/appicon_1024.png \
  swift test --filter AssetRenderTests
```

- 帧：900×900 透明底 + 脚下接地影，`cat_anim_00…15`，帧数须与 `PetProvider.frameCount` 一致。
- 图标：1024×1024 **不带 alpha**（带了 App Store 会打回），奶油→天蓝渐变底 + 半身特写。

## 故障排查

- **小组件一直是占位「喵喵 72/88/64」**：主 App 没成功写快照——多半 App Group 名
  没对齐，或主 App target 没勾 App Group / 没链接 PetKit。
- **编译报 `No such module 'PetKit'`**：第 1/3 步的库没链接到对应 target。
- **快照不更新**：确认主 App 进过电子宠物页（写快照在该页 `.task` 的循环里）。
