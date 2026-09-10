# 板级功能调试进度

板子：BLMQ（LM / BLMQ / G）  设备号：collar-evt-001（config.lua 所填；台账中该板为 dev-blmq-01）  底层固件版本：V2030_1（LuatOS@Air780EGH base 25.11 bsp V2030 32bit）  脚本版本：evt0.0.1 / VERSION 001.000.001

| # | 功能 | 状态 | 日期 | 日志文件（records/raw/…） | 备注 |
|---|---|---|---|---|---|
| F0 | 烧录环境（Windows/VM + Luatools）可用 | ✅ | 2026-09-09 | | Win11 + Luatools 3.4.9 烧录成功；流程与坑见 docs/09 |
| F1 | 开机、日志、版本、开机原因 | ✅ | 2026-09-09 | Windows 侧 `D:\Luatools\log\trace_2026-09-09_062459.txt`（待回传、打码后放 raw/collar-evt-001/） | 日志：`petpal_evt0 001.000.001 collar-evt-001 evt0.0.1`、`lastReson 0 0 0 cold boot`、`hmeta Air780EGH A11`、features 全 false |
| F2 | SIM 注册、IP_READY、信号 | ⏳ | 2026-09-10 | raw/collar-evt-001/log_F2probe_*.txt | Mac 直读日志：`+CPIN: NOT READY`，`rsrp 0 rssi 0 csq 0 status 0`，SIM 未被识别。需断电插好 SIM（拨动开关断 + 拔 USB）再开机。注册耗时 ___ s，RSRP ___ |
| F3 | MQTT/TLS 单向校验；错误 CA 失败 | ☐ | | | |
| F4 | GNSS 冷/热启动 fix | ☐ | | | 冷 ___ s / 热 ___ s / 卫星 ___ |
| F5 | DA267 WHO_AM_I、震动中断、步数 | ☐ | | | INT 引脚实测 GPIO ___ |
| F6 | ADC 电压、VBUS 充电检测 | ☐ | | | ADC ___ mV vs 万用表 ___ mV |
| F7 | LED / 马达 GPIO 输出，默认关 | ☐ | | | 引脚 ___ |
| F8 | 遥测闭环 100 条通过 validator | ☐ | | | |
| F9 | 命令 ACK 40 条通过 ack_checker；裁剪与冷却 | ☐ | | | |
| F10 | BLE 广播被手机扫到 | ☐ | | | |
| F11 | 低功耗电流（可选） | ☐ | | | |
| F12 | FOTA（可选） | ☐ | | | |
| F13 | 断网缓存补传（可选） | ☐ | | | |

## 问题记录

| 日期 | 功能 | 现象 | 处理 | 状态 |
|---|---|---|---|---|
| 2026-09-07 | F0 | Mac mini 无 Windows 虚拟机，Luatools 无法运行；模组未接 USB（Air8201G 无板载 Type-C，需 BTB 扩展板） | 改为另一台 Windows 电脑烧录（docs/08）；Mac+UTM 方案备用 | 已解决 |
| 2026-09-08 | F0 | Windows 设备管理器完全无 COM | 非驱动问题：出厂固件 MODE1 低功耗关 USB + 电池拨动开关断开。开关置通、按 reset 后枚举 COM12/COM13 | 已解决 |
| 2026-09-09 | F0 | Luatools 合并失败「缺少 exgnss.lua」 | 交接包漏 exgnss/lbsLoc2，从 LuatOS master 补；已入库 firmware/wearable-evt0/libs/ | 已解决 |
| 2026-09-09 | F0 | 「模块重启超时」/ 点全量下载无反应 | 无 BOOT 键：按 reset 后 COM 出现立即点下载；主界面须先选中项目 | 已解决 |
| 2026-09-09 | F0 | 出厂 V2044 整机固件被覆盖，无备份 | 如需恢复找合宙/硬件方要原包 | 记录 |
| 2026-09-09 | F2 | 烧录时未插 SIM，日志停在 waiting SIM/network | 插卡需断电（拨动开关断 + 拔 USB）；等回传 IP_READY 日志 | 待确认 |
| 2026-09-10 | F2 | 板子接 Mac，日志 `+CPIN: NOT READY`、`status 0` | SIM 未识别：确认卡是否插入/插反/卡座未到位；插好后按 reset 看 IP_READY | 待确认 |
| 2026-09-10 | F2 | 断电重插 SIM 后冷启动，仍 `+CPIN: NOT READY`、`status 0`（raw/collar-evt-001/log_F2_20260909_210031.txt） | 排查：卡方向/卡座是否扣紧、是否需要 `mobile.simid(2)` 自动选卡槽、换一张卡 | 待确认 |
| 2026-09-10 | F0 | Mac 上 serial_log.py 读不到日志（USB 日志口是 Luatools 帧格式） | 新增 tools/usb_log.py 解码，13 口可直读 Lua 日志，无需 Luatools | 已解决 |
| 2026-09-10 | F0 | 每改一次 features 都要回 Windows 重烧 | 新增 console_app.lua + tools/usb_cmd.py：功能开关写 KV 覆盖，USB 命令切换后 reboot 生效；flash-kit v3 待烧 | 待烧录验证 |
| 2026-09-10 | F2 | SIM 重插后第三次冷启动仍 NOT READY | net_app 加 `mobile.simid(2)` 自动扫卡槽并每 10 s 打 SIM 诊断；无 SIM 先走 F5/F6/F4/F10 | 待烧录验证 |
| 2026-09-09 | F1 | `W/pins /luadb/pins_air780egh.json not exist!!` | 无害；用 PWM 复用脚时再随包烧 pins json | 记录 |
