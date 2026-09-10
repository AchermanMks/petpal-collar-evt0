# 备选开发板评估（2026-09-10）

> 问题：Air8201G-BLMQ 调试板的开发体验不好（Luatools 只有 Windows、板上无 BOOT 键、拨动开关/电池供电反直觉、SIM 未识别、低功耗关 USB）。若继续恶化，用什么板子顶上？
> 依据：`docs/00`（P0：中国大陆 4G Cat.1 + GNSS + LBS 回退 + BLE + G-sensor + 震动/LED + 300 mAh ≥5 天 + ≤30 g + MQTT/TLS + FOTA）、`docs/02` 验收线、`pet-collar/JIELI_VS_AIR8201_COLLAR_COMPARISON_2026-09.md` 的一票否决规则。
> 证据等级沿用对比报告：E1 官方资料/实测，E3 推断，U 未知。

## 0. 结论

1. **主路线不换。** 体验差的根源有两个：Luatools 只能在 Windows 跑（合宙、移远全系都一样，换模组厂也逃不掉），以及 BLMQ 这块调试板本身（无 BOOT、电池总开关、VBUS 不供电）。前者已用 `tools/usb_log.py` + `console_app.lua`（Mac 直读日志、USB 命令切功能）把重烧次数压到最低；后者用一块几十元的官方核心板就能解决。
2. **立即买的备份（≤100 元）：合宙 Core_Air780EGH 开发板。** 同一颗 Air780EGH，脚本零改动，板上有 BOOT 键和开机键、USB 供电，专门解决"进不了下载模式/板子假死"这两类浪费时间的坑。缺 BLE（Air780EGH 本身无蓝牙，LM 的蓝牙是另一颗芯片），F10 仍在 Air8201G 上做。
3. **Mac 原生的并行开发板（约 300 元）：LILYGO T-SIM7670G-S3。** ESP32-S3 + SIM7670G（Cat.1 + GNSS），BLE 由 ESP32 提供，Arduino/PlatformIO/ESP-IDF 在 Mac 上直接编译烧录，不需要 Windows。用来把 MQTT/命令/ACK/缓存/后端/App 的闭环先跑通，与硬件解耦。它不能当产品板（重、功耗高、两颗芯片）。上一版 `pet-collar` 的 ESP32 + A7670E 固件可直接复用。
4. **下一代候选（等 LM 决策时再评）：合宙 Air8000 核心板。** 单模组集成 4G + WiFi + BLE + GNSS + G-sensor + 电源管理，LuatOS API 与现在几乎相同，官方应用场景含宠物定位。但仍是 Luatools/Windows，不解决工具链问题；只在 Air8201G-LM 供货或 BLE 路径出问题时切。
5. **不推荐**：移远 QuecPython（EC800G-CN）——同样只有 Windows 工具（QPYcom），换了语言没换掉痛点；nRF91 系列——LTE-M/NB，中国大陆 Cat.1 覆盖要求不满足；杰理路线——见对比报告，一票否决。

## 1. 先分清楚"体验差"的来源

| 痛点 | 根源 | 换板能不能解决 | 现状 |
|---|---|---|---|
| 烧录只能在 Windows | Luatools 闭源、仅 Windows；合宙 `ectool2py` 虽支持 macOS/Linux，但只支持 EC618（Air780E/EG），不支持我们的 EC718（Air780EGH），且还不能刷脚本 | 换合宙/移远任何模组都一样；只有换 ESP32 路线能彻底摆脱 | 已把重烧需求压到"改底层/加文件"时才需要：功能开关走 USB 命令 |
| 板上无 BOOT 键，靠 reset 时机进下载 | BLMQ 调试板设计 | **能**：Core_Air780EGH 有 BOOT 键 | 有可复现手法（reset 后立即点下载） |
| 拨动开关/VBUS 不供电/拔 USB 不复位 | BLMQ 板载电池设计 | **能**：核心板 USB 供电 | 已记录在 docs/06 |
| 看不到日志 | 日志口是 Luatools 私有帧格式 | 不需要换板 | `tools/usb_log.py` 已解决 |
| SIM NOT READY | 卡/卡座/卡槽选择，未定位 | 换板可作对照（同一张卡插核心板看是否识别） | v3 固件加 simid 自动扫描待验 |
| 低功耗关 USB | Air780E 系列共性 | 换板不解决（Air8000 同） | F11 前换 UART 日志通道 |

## 2. 候选板逐项对比

| 项 | A. Core_Air780EGH 开发板 | B. Air8000 核心板 / Air8000A | C. LILYGO T-SIM7670G-S3 | D. QuecPython EC800G-CN EVB |
|---|---|---|---|---|
| 4G Cat.1 中国大陆 | ✅ 同现役模组 (E1) | ✅ (E1) | ✅ SIM7670G 全球频段含 B1/3/5/8/34/38/39/40/41 (E1) | ✅ (E1) |
| GNSS | ✅ 同现役 (E1) | ✅ 内置，低功耗 GNSS 备份+Gsensor 约 88 µA (E1) | ✅ GPS/GLONASS/北斗 (E1) | ✅ EC800G 带 GNSS (E1) |
| BLE | ❌ 无（需外挂 Air5101S） | ✅ 内置 (E1) | ✅ ESP32-S3 BLE 5.0 (E1) | U，需确认 |
| G-sensor | ❌ 需自接 DA267 | ✅ 内置 (E1) | ❌ 需自接 | ❌ 需自接 |
| 电池/充电 | USB 供电，无充电管理 | 内置电源管理 (E1) | LiPo 接口 + 充电 + DW01 保护 (E1)；USB/电池切换会复位 (E1) | USB/DC 切换开关 (E1) |
| 烧录/调试工具 | Luatools，Windows | Luatools，Windows | Arduino / PlatformIO / ESP-IDF，**Mac 原生** (E1) | QPYcom，Windows (E1) |
| BOOT / 复位键 | ✅ BOOT + 开机键 (E1) | ✅ 开发板有 (E3) | ✅ ESP32 标准 BOOT/RST | PWRKEY，无独立 BOOT (E1) |
| 现有脚本迁移 | **零改动** | 小改（引脚/库名） | 重写为 C/C++，可复用 pet-collar ESP32 固件 | 重写为 Python |
| 尺寸/重量适合上项圈 | 否（开发板），模组同 | 模组 22×22×2.3 mm (E1)，可 | 否，仅台架 | 否，仅台架 |
| 价格量级 | 几十元 | 核心板约百元级 (E3) | 约 300 元 (E3) | 百元级 (E3) |
| 采购渠道 | 合宙官方店/淘宝 | 合宙官方店 | LILYGO 官方店/淘宝/Amazon | 移远开发者商城 |
| 适合的用途 | 替代 BLMQ 做全部台架功能调试（除 BLE） | LM 之后的下一代主路线候选 | Mac 上并行跑通协议/后端/App 闭环；硬件盲区期不停工 | 不建议 |

## 3. 建议动作

| 时机 | 动作 | 花费 | 目的 |
|---|---|---|---|
| 现在 | 下单 1 块 **Core_Air780EGH 开发板** + 1 根 GNSS 天线 | <100 元 | 台架备份；同一张 SIM 插上去做对照，快速判定"卡的问题"还是"BLMQ 板的问题" |
| 现在（可选） | 下单 1 块 **LILYGO T-SIM7670G-S3** | ~300 元 | Windows 环节再卡住时，Mac 上继续跑 F3/F8/F9 的软件闭环 |
| Gate G1 前 | 向合宙 FAE 问：Air8201G-LM 供货、Air8000 是否有可穿戴 PCBA、Luatools 是否有 Mac/CLI 计划 | 0 | 记入 `records/fae_questions.md` |
| 触发条件 | 以下任一发生才切主路线：LM 缺货 >2 周；Air8201G BLE 路径无法在 F10 通过；Air780EGH SIM/GNSS 在核心板上也复现故障 | | 切到 B（Air8000） |

## 4. 一票否决核对（对 A/B/C）

| 规则 | A | B | C |
|---|---|---|---|
| 不依赖手机/家庭 Wi-Fi 联网 | ✅ | ✅ | ✅ |
| 有 GNSS | ✅ | ✅ | ✅ |
| 1 A 级瞬态供电 | 开发板由 USB 供，台架无问题 | ✅ | LiPo + 板载电源，需实测 |
| SDK/烧录/样板/FAE 可得 | ✅ | ✅ | ✅（社区为主） |
| 设备身份 / TLS / 安全 FOTA | ✅ LuatOS 同现役 | ✅ | ✅ ESP-IDF 有 mbedTLS + OTA |
| 30 天内拿到可穿戴样机 | 不适用（台架） | 需 PCBA，风险 | 不适用（台架） |

## 6. 购买链接（2026-09-10 核实）

**合宙（官方淘宝店 https://luat.taobao.com ）**

| 商品 | 链接 | 说明 |
|---|---|---|
| Air780EGG 开发板（Turnkey，定位版） | https://item.taobao.com/item.htm?id=1020704393672 | 合宙官方文档「购买链接」一节列出的链接。Air780EGG = Air780EGH + 内置 G-sensor，软件与 EGH 同系列；套件含摄像头/LCD/传感器/4G 天线/流量卡，比裸核心板贵，但 F5 也能顺便在它上面做 |
| Air780EHM 开发板（Turnkey，无 GNSS） | https://item.taobao.com/item.htm?id=1021480484619 | 仅对照用，不推荐 |
| Core_Air780EGH 核心板 | 在 https://luat.taobao.com 店内搜「Air780EGH」或「Air780EGG 核心板」 | 官方文档未直接给核心板链接；几十元级 |

**LILYGO T-SIM7670G-S3**

| 渠道 | 链接 | 备注 |
|---|---|---|
| LILYGO 官网 | https://lilygo.cc/en-us/products/t-sim-7670g-s3 | 标价 $39.45，两个版本：H707 基础版；H802 Standard（无缝供电切换、QWIIC、摄像头口），**选 Standard**（基础版在 USB/电池切换时会复位）。核实时官网显示 Sold out |
| LILYGO 淘宝店 | https://shop140839766.taobao.com | 官网页脚给出的国内店 |
| AliExpress 官方店 | https://www.aliexpress.com/item/1005007058444056.html | |
| Amazon | https://www.amazon.com/dp/B0D6K75W57 （基础版）；https://www.amazon.com/dp/B0GJCGZX3Y （Standard） | 海外仓 |

## 5. 来源

- Air780EGH 产品页与硬件手册：https://docs.openluat.com/air780egh/product/ ；开发板 BOOT 进下载模式说明：https://wiki.luatos.com/chips/air780e/index.html
- Air8000 产品手册：https://docs.openluat.com/air8000/ ；核心板 22×22×2.3 mm、四合一集成：https://www.besovideo.com/detail?t=2&i=1917 ；低功耗 GNSS/Gsensor 约 88 µA：https://docs.openluat.com/air8000a/luatos/app/gnss/agps/
- ectool2py（macOS/Linux，仅 EC618，脚本烧录未实现）：https://github.com/openLuat/ectool2py/
- LuatOS 工具大全：https://wiki-zh.luatos.org/pages/tools.html
- LILYGO T-SIM7670G-S3 文档：https://wiki.lilygo.cc/products/t-sim-series/t-sim7670g-s3/
- QuecPython EC800X EVB：https://developer.quectel.com/doc/quecpython/Dev_board_guide/zh/ec800x-evb.html ；QPYcom 烧录（Windows）：https://python.quectel.com/doc/quecpython/Application_guide/zh/firmware-upgrade/firmware-burning.html
