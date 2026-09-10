> 归档说明（2026-09-10，Mac 端）：本文由 Windows 烧录侧 Claude 于 2026-09-09 生成，原件 `~/Downloads/WINDOWS_FLASH_REPORT.md`，正文原样收录，未改动。
> Mac 端已据此更新：`docs/05`（烧录路线/已知坑）、`docs/06`（BLMQ 板实测结论）、`docs/08`（勘误）、`firmware/wearable-evt0/libs/`（补 exgnss/lbsLoc2）、`records/bringup_checklist.md`、`records/bringup_log.csv`、`tools/redact_ids.py`。
> 尚未到手：F2 的 IP_READY 日志、3 分钟 trace 文件、交接表数值——见 §6 与 `records/bringup_checklist.md`。

# PetPal EVT 板 Windows 烧录交付报告

写给 Mac 端会话:本文档是 Windows 侧烧录任务(F1/F2)的完整交付,包含最终状态、板子硬件实测结论、踩坑记录与遗留事项。日期:2026-09-07 ~ 2026-09-09。执行方式:人工操作 + Windows 侧远程指导。

## 1. 任务与结果总览

任务(来自 docs/08_WINDOWS_FLASH_HANDOFF.md):给合宙 Air8201G-BLMQ(核心模组 Air780EGH)烧底层固件 V2030 与 petpal 调试脚本,验证 F1 开机日志、F2 SIM 注册,回传日志。

| 项目 | 状态 |
|---|---|
| 底层固件烧录(LuatOS-SoC_V2030_Air780EGH_1.soc) | ✅ 成功,日志确认 `LuatOS@Air780EGH base 25.11 bsp V2030 32bit` |
| 脚本烧录(8 个 app lua + config.lua + 补充库) | ✅ 成功 |
| F1 开机日志 | ✅ **通过**(证据见 §5) |
| F2 SIM 注册(IP_READY ≤ 60s) | ⏳ **待确认**——烧录后日志停在 `waiting SIM/network`,SIM 插入与 IP_READY 结果以用户最终回传的日志为准 |
| 3 分钟完整日志 | Luatools 自动保存于 Windows 机 `D:\Luatools\log\trace_2026-09-09_062459.txt`(回传前须将 IMEI/ICCID 打码,底层日志打印了**完整 IMEI**) |
| 交接表(VID/PID、IP_READY 秒数、首个 rsrp 等) | ⏳ 待用户补填 |

芯片实测信息:`Air780EGH_A11`,die `EC718HM`,SDK base line `V017_pp23.001`,ROM Build 2026-03-20。firmware 分区:fs 768KB / script 512KB,含 TTS+VOLTE。

## 2. 板子硬件实测结论(重要,后续调试都用得上)

这些是本次实际折腾出来 + 合宙官方文档(Air780EGH 硬件资料已并入 air780epm 页面,官方注明适用 EGH)交叉验证的结论:

1. **按键共 5 个 + 1 个拨动开关**,丝印与真实功能:
   - `pwkey` = 开机键(关机态下降沿开机;开机后只是中断输入,关机行为由软件决定——出厂固件是"累计拉低 7s 关机",petpal 固件行为取决于我们脚本)。
   - `reset` = 硬复位(低有效,PIN15,软件拦不住,任何状态下有效——前提是模组有电)。
   - `wakeup6` = **实为 CHG_DET,官方定义为第二颗开机键**(功能同 PWRKEY,历史命名)。
   - `wakeup0`、`wakeup5` = 休眠唤醒脚(WAKEUP5=GPIO22),仅唤醒用。
   - **拨动开关 = 电池(VBAT)总开关**。
2. **板载电池,且 USB VBUS 不参与模组供电**(官方原文:VBUS 仅作充电与唤醒中断,"无法替代 VBAT")。推论:
   - 拨动开关断开时,插着 USB 板子也完全无反应(按键全部无效),只有充电指示灯亮——**充电红灯与模组状态无关,别用它判断死活**;
   - 拔插 USB **不能**复位模组(电池供电不断),要复位用 `reset` 键。
3. **板上没有 BOOT 键**。进 USB 下载模式需 USB_BOOT(PIN82)在**上电前**上拉至 VDD_EXT,板上未引出该操作。因此烧录只能靠 Luatools 软重启模组进下载模式,前提是 USB 已枚举、模组在运行。
4. **低功耗模式会物理关闭 USB**(pm.WORK_MODE 1/3 关闭 LDO33USB)。出厂固件是 MODE1 低功耗常驻,曾导致 USB 长时间完全不枚举、设备管理器毫无反应(不是驱动问题,Win10/11 本平台免驱)。**petpal 固件 lowpower=false,USB 常在**;后续开发若开 lowpower,USB 会断,serial 抓日志会受影响,切记。
5. 正常运行时 USB 枚举 **2 个串口**:soc log 口(本次 COM12)+ 用户虚拟串口(本次 COM13)。
6. 模组的"红灯"= GPIO16(与 config.lua 中 actuator.led_gpio=16 一致),出厂固件开机闪 3 次;常亮的那颗是充电灯。

## 3. 烧录流程实录(Luatools 3.4.9 / Win11,可复现)

1. 解压 petpal-flash-kit.zip 至 `D:\Luatools\petpal-flash-kit\`。
2. `config.example.lua` → 复制为 `config.lua`,改 `device_id="collar-evt-001"`,features 全 false(含 mqtt/lowpower)。
3. Luatools 主界面右上角竖排按钮「项目管理」(窗口要最大化才看得见)→ 创建项目 `petpal-evt` → 选择底层 CORE = 包内 `.soc`(不点"下载最新固件",版本锁 V2030)→「增加脚本或资源文件」加入 8 个 app lua + config.lua。
4. 依赖检查报「合并失败: 缺少 exgnss.lua」→ **交接包缺文件**,从 LuatOS 官方仓库补 `script/libs/exgnss.lua`(其内部还 require `lbsLoc2.lua`,一并补)。补后合并通过。
5. 勾「清除KV分区」「清除FS分区」(清掉出厂程序残留),「添加默认扩展库」勾选,「忽略脚本依赖性」不勾。
6. 点「全量下载(底层+脚本)」。**关键时机**:板子刚复位/开机的头几秒内点下载,Luatools 才能软重启模组进下载模式;模组久跑或休眠时点会报"模块重启超时"。有效手法:插好 USB → 按 reset → COM 出现后立即点全量下载。
7. 烧录后自动重启,进入 §5 的 F1 日志。

## 4. 踩坑记录(时间线摘要)

1. 初期设备管理器完全无 COM → 依次排除:数据线(用手机验证)、驱动(不是,缺驱动会有黄叹号设备,完全无枚举=模组 USB 没电)→ 真因:出厂固件 MODE1 休眠关 USB + 后期拨动开关断了电池。
2. 板子出厂自带 **V2044 整机固件**(电源管理 v2.0 / OTA / EXCLOUD / exgnss / GSENSOR,低功耗常驻)。**已被本次烧录覆盖,无备份**;如需恢复出厂程序,要找合宙或硬件方要原包。
3. 点「全量下载」无反应 → 主界面「当前项目」未选中/固件文件为空,配好项目即可。
4. 「模块重启超时,请断电后上电…」→ 电池板拔 USB 不断电;用 reset 键制造"刚开机"窗口(见 §3.6)。
5. Luatools 出现 `CommError [WinError 22]` 端口卡死 → 重启 Luatools 解决。
6. 烧录当时系统状态显示「SIM卡未插入」→ 插卡需断电操作(拨动开关断电 + 拔 USB)。

## 5. F1 验收证据(IMEI 已打码)

```
main_entry 708:SDK base line V017_pp23.001
am_service_init 1358:Air780EGH_A11   (die: EC718HM)
self_info 128:model Air780EGH_A11 imei 8643170****889
I/main LuatOS@Air780EGH base 25.11 bsp V2030 32bit
I/user.main petpal_evt0 001.000.001 collar-evt-001 evt0.0.1
I/user.main lastReson 0 0 0 cold boot
I/user.main hmeta Air780EGH A11
I/user.main features {"mqtt":false,"gnss":false,"lowpower":false,"ble":false,"power":false,"gsensor":false,"actuator":false}
I/user.net waiting SIM/network ...
```

小警告(无害但记录):`W/pins /luadb/pins_air780egh.json not exist!!`——脚本直接配管脚,可考虑后续是否随包烧一份 pins json。

## 6. 遗留事项 / Mac 端 TODO

1. **确认 F2**:收用户回传的 IP_READY 段日志(要求 ≤60s)与 30s 周期 rsrp/rssi/csq 行;若一直 `waiting SIM/network`,先查 SIM 是否插好、是否无 PIN 锁、是否定向物联网卡(APN)。
2. **收 3 分钟日志文件** `trace_2026-09-09_062459.txt` 及交接表(IP_READY 秒数、首个 rsrp、Luatools 3.4.9、VID/PID、COM12/13、异常栏)。**回传文件须先全文搜索 IMEI/ICCID 打码**——底层日志会打印完整 IMEI,脚本层脱敏管不到它。
3. **把 `exgnss.lua` + `lbsLoc2.lua` 并入 flash kit**(本次从 LuatOS master 补的,建议在 kit 里锁定副本,避免下次换机重踩)。
4. 板子接回 Mac 后:电池拨动开关置于"通",USB 直连;lowpower=false 下 USB 常在,`tools/serial_log.py` 可直接抓(两个串口:soc log + 用户虚拟口,抓日志用 soc log 口对应的设备)。
5. F3 起逐项打开 features 时注意:开 `lowpower` 会关 USB(LDO33USB),须换好日志通道再开;`actuator` 按交接规则暂不开。
6. 记录:出厂 V2044 固件已被覆盖且无备份;板子曾出现"供电开关断开导致假死"现象,硬件文档确认属正常设计而非故障。
