# 板级功能调试方案（当前执行版）

> 2026-09-07 范围调整：**先在手头的 Air8201G 板子上把项圈所需功能逐项调通**，结构、天线、试戴、Gate 等整机内容全部后置。原方案见 `00_TEST_PLAN_SOURCE.md`，本文件优先。

## 目标

一块 Air8201G（LM 或 BLMQ）+ 官方天线 + SIM + 台式电源/锂电，在桌面上跑通下面 10 项功能，每项有日志证据和一行记录。全部通过后再回到整机方案。

## 硬件事实（来自合宙官方 demo 与出厂工程，详见 06_AIR8201G_HARDWARE_NOTES.md）

| 功能 | 板载资源 | 关键参数 |
|---|---|---|
| 4G Cat.1 | Air780EGH 核心 | `mobile.*`，联网后系统发布 `IP_READY` |
| GNSS | 内置，UART2 115200 | 供电 GPIO21；`exgnss` 或 `libgnss.bind(2)`；AGPS 星历 HTTP 下载 |
| G-sensor | DA267，I2C1 地址 0x26 | 供电 GPIO24，I2C 上拉使能 GPIO28，INT GPIO20（出厂工程）/GPIO39（demo），WHO_AM_I=0x13 |
| 电池电压 | ADC0 | 分压 1 MΩ/300 kΩ，补偿 +140 mV（出厂工程口径，需按自己板子核对） |
| 充电检测 | VBUS → WAKEUP1 | 双边沿中断，1=插入 |
| BLE | LM 板载（BLE 5.2） | 出厂工程用 `bluetooth.init():ble()` 广播；另一路径为 Air5101 经 UART2 `exril_5101` |
| LED | GPIO16（出厂工程红灯）/ PWM4 | 状态灯 |
| 马达 | 任一空闲 GPIO 或 PWM0/PWM1 经 MOSFET | 板上无马达，载板/飞线接 |
| 关机键 | PWRKEY | `pm.shutdown()`，长按 7 s |
| 低功耗 | `pm.power(pm.WORK_MODE, 1)` | 出厂工程用低功耗常驻模式；**开了会关 USB，日志断** |
| USB/烧录 | BTB 引出 USB；BLMQ 无 BOOT 键/USB_BOOT | Luatools 仅 Windows；靠 reset 后立即下载进入下载模式 |
| 供电 | 板载电池 + 拨动开关 | VBUS 不供电，开关断开则整板无反应 |

## 烧录与日志（先解决）

- **Luatools 只有 Windows 版**，不能在 macOS 直接烧录。2026-09-08 改为另一台 Windows 电脑烧录（交接单 `08_WINDOWS_FLASH_HANDOFF.md`），2026-09-09 已完成 V2030_1 + 脚本烧录，F1 通过，实录与板子硬件结论见 `09_WINDOWS_FLASH_REPORT.md`。Mac + UTM 方案（`07_F0_MAC_UTM_FLASHING.md`）保留备用。
- 底层固件：Air780EGH 系列 LuatOS 固件，最新 V2030（2026-03-20），已下载到 `~/petpal-vm-share/core_firmware/`（另备 V2016）。记录版本号到 `records/bringup_log.csv`。
- 烧录内容：`firmware/wearable-evt0/*.lua` + `libs/exgnss.lua` + `libs/lbsLoc2.lua` + `config.lua`（自己填）+ CA 证书文件。Luatools 勾「清除KV分区」「清除FS分区」「添加默认扩展库」。
- 烧完后 Mac 可以直接读 USB 日志：`python3 tools/usb_log.py --auto --device collar-evt-001 --tag F2`（2026-09-10 实测可用，不需要 Luatools）。板子接 Mac 前把电池拨动开关置“通”。Mac 上枚举为 AirM2M Compo USB（VID:PID 19D1:0001）三个 usbmodem 口：`…13` 是 AP 日志口（Luatools 帧格式，Lua 日志为明文，工具已解码并打码 IMEI）、`…15` 是底层二进制 trace（不可读）、`…17` 无输出。`serial_log.py` 只适用于普通文本串口。

## 功能清单与通过标准

| # | 功能 | 固件开关 | 通过标准 | 证据 |
|---|---|---|---|---|
| F1 | 开机、日志、版本 | 总是 | 日志打印 PROJECT/VERSION、`pm.lastReson()`、硬件信息 | 日志 |
| F2 | SIM 注册与 4G | 总是 | `IP_READY`；打印 IMEI（脱敏）、ICCID、RSRP/RSSI；≤60 s | 日志 + bringup_log |
| F3 | MQTT/TLS 连接 | `features.mqtt` | 单向校验 CA 成功；错误 CA 必须失败；发布 `state`（retained）后端收到 | 日志 + Broker 侧 |
| F4 | GNSS 定位 | `features.gnss` | 窗边/室外冷启动 ≤ 90 s fix，热启动 ≤ 15 s；打印 lat/lng/卫星数；无 0,0 | 日志 3 次 |
| F5 | G-sensor | `features.gsensor` | WHO_AM_I=0x13；静止/敲击触发 `GSENSOR_MOTION`；步数递增 | 日志 |
| F6 | 电池与充电 | `features.power` | ADC 电压与万用表差 ≤ 50 mV；插拔 USB 触发 CHARGING_START/STOP | 日志 + 万用表 |
| F7 | LED / 马达 | `features.actuator` | 上电默认关；命令触发 LED 闪、马达脉冲；示波器/万用表看到电平 | 日志 + 照片 |
| F8 | 遥测闭环 | F2+F3+F4+F6 | 每 30 s 发 `telemetry`，`tools/telemetry_validator.py` 通过 100 条 | JSONL |
| F9 | 命令与 ACK | F3 | `VIBRATE`/`LED`/`SET_MODE`/`LOCATE_NOW` 各 10 条，`tools/ack_checker.py` 通过；超限参数被裁剪；30 s 冷却生效 | JSONL |
| F10 | BLE 广播 | `features.ble` | 手机 nRF Connect 扫到设备名/iBeacon；不影响 F2/F4 | 截图 |

可选（功能都通了再做）：F11 低功耗模式电流（PPK2）、F12 FOTA、F13 断网缓存补传。

## 执行顺序

1. F1→F2→F3 用 `config.lua` 只开 mqtt。
2. 加 gnss、gsensor、power 各自单独开，逐个确认，避免互相干扰。
3. 全开，跑 F8/F9 一小时，导出 JSONL 跑工具。
4. 最后开 ble，看是否影响 GNSS/4G。

每项通过在 `records/bringup_checklist.md` 打钩并写日志文件名。

## 已知坑（来自出厂工程更新日志）

- DA267 上电后要等 ≥200 ms 再读 WHO_AM_I，否则 I2C NACK；失败重试 5 次。
- `pm.lastReson()` 拼写就是少一个 R。
- `exgnss.open()` 无返回值；定位结果必须在回调里立即读 `exgnss.is_fix()` / `exgnss.rmc(0)`，回调返回后 GNSS 会被关掉。
- TLS 校验前必须先对时（sntp 或基站时间）。
- PWRKEY 内部上拉到 VBAT，必须 PULLUP，防抖要在 `gpio.setup` 之前。
- PWM4 等复用引脚需要 LuatIO 生成的 pins json 一起烧录。

## 已知坑（来自 2026-09-09 实际烧录，详见 docs/09）

- `features.lowpower=true` 会关 LDO33USB，USB 串口消失。开 lowpower 前先换好日志通道（UART 或 MQTT 上报），否则看不到日志。
- USB VBUS 不给模组供电；拔插 USB 不复位。复位按 `reset`；进下载模式的窗口只有刚复位后几秒。
- 拨动开关是电池总开关，断开后整板假死（只亮充电灯），属正常设计。
- `exgnss` 是脚本层扩展库，V2030 底层不内置；漏烧会在 Luatools 合并阶段就失败。
- 底层日志打印完整 IMEI，脚本层的脱敏管不到它。
