# 宠宝 Air8201G · 独立 iOS 版本

旧 ESP32 项目 `/Users/mantashark/pet-collar` 未修改。此处从用户当前工作文件复制 UI/资源，保留包括未提交改动在内的界面；`ESP32_SOURCE_SNAPSHOT.json` 是原文件的 SHA-256 快照。

新 Xcode 工程 `PetPalAir8201G.xcodeproj`，兼容原 target/scheme 名 `PetCollar`。独立 Bundle ID `com.petpal.air8201g`、App Group `group.com.petpal.air8201g`、URL scheme `petpalair`，显示名“宠宝 Air8201G”。不会替换 ESP32 App、覆盖其设置或共享旧小组件存档。PetKit 副本在 `../PetKit`，也不改旧工程。

按用户要求，**不改变原有 App 界面**：启动流程、导航、摄像头、灯光、声音、马达、电弧、GPS 等页面均保留原版，没有新增 Air 页面或设置页。只在 Core 中替换底层通信：原 ESPClient 的调用由 AirHardwareProtocol 转成 Air 服务 API，不再访问旧 ESP32 硬件。电弧/高压输出不实现，原按钮通过既有错误提示返回不支持。

## 运行（模拟器台架）

1. 用 LuaTools 烧录 **完整的** 台架脚本包，所有 Lua 文件均加入项目。摄像头使用专用 AIR 003 包（见 `docs/13_CAMERA_LIVE.md`），勿混用旧 config.lua。当前未完成烧录时，App 会显示未连接，不伪造数据。
2. Windows LuaTools 停止串口占用，在 UTM USB 菜单 Disconnect AirM2M，交回 macOS。
3. 项目根运行 `.venv/bin/python apps/bridge/air_bridge.py`。默认仅监听 `127.0.0.1:8210`，无模拟数据/无外网暴露。可用环境变量 `PETPAL_BRIDGE_TOKEN` 增加鉴权；不输出密钥。
4. Xcode 打开此工程，选择 iPhone 模拟器并运行。原默认 `esp32-led.local` 在模拟器底层自动转向 `http://127.0.0.1:8210`；也可在原有地址输入框填写服务地址。没有新增连接界面。设备 ID 默认 `collar-evt-001`；部署时通过 `PETPAL_AIR_DEVICE_ID`、`PETPAL_AIR_SERVICE_URL`、`PETPAL_BRIDGE_TOKEN` 配置底层，Token 不写入代码或存档。

真机不能访问电脑的 127.0.0.1。本台架桥不提供公开监听；真机/4G 需另接 HTTPS API → TLS MQTT 服务、真实 SIM/broker/证书/ACL。没有修改或部署原项目远端后端。

## 诚实的能力边界

已使用 Xcode 26.4.1 / iPhone 17 Pro iOS 26.4 模拟器编译、安装并启动新 Bundle ID。旧 `com.petcollar.PetCollar` 未卸载；原源文件哈希核对零变化。已通过真实本机HTTP访问确认未烧录新固件时显示503错误、控制不可用，未伪报连接成功。旧界面的 SceneKit/Swift并发兼容警告仍保留，未升级成Swift6或宣称清零。

已有代码不等于板上验收：GNSS/DA267/电池/LED 需新固件烧录后验证。摄像头已实现按需 JPEG 采集、USB 分块校验及原实况页 MJPEG 适配，尚未烧录/收到真实画面；不是成熟4G视频推流方案。马达默认没有引脚且未验证，温度未知会拒绝震动。RGB/喇叭/音频文件/BLE 测距/FOTA/耗电与唤醒未完成。历史轨迹需服务端存储。活动峰值不是校准步数，更不是健康测量。原界面里的虚拟宠物/商城等演示数据不是来自开发板。

HTTP 协议：`GET /v1/devices/{id}/snapshot`；`POST /v1/devices/{id}/commands` 使用 schemas/command 的信封；`GET .../commands/{command_id}` 获取同一指令 ID 的持久化回执。只在 `executed` 时显示已执行；断线/超时不自动创建新的动作 ID。停止指令可在另一指令等待回执期间发出。
