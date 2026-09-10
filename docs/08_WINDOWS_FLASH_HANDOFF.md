# 交接：在 Windows 电脑上给 Air8201G-BLMQ 烧录并跑通 F1/F2

> 给另一台 Windows 机器上的 Claude 的任务说明。自包含，不需要访问 Mac 或本仓库。
> 配套文件包：`petpal-flash-kit.zip`（脚本、底层固件、本说明、记录表头）。

> **勘误（2026-09-10，根据 docs/09 实际烧录结果）**
> - §3/§4.5：BLMQ 调试板**没有 BOOT 键**，USB_BOOT 未引出。“等待设备”时不要找 BOOT；正确做法是插好 USB → 按 `reset` → COM 口出现后**立即**点全量下载（模组刚开机的头几秒才能被 Luatools 软重启进下载模式）。
> - §3：板载电池由拨动开关控制，USB VBUS 不给模组供电。拨动开关必须置“通”，否则插 USB 也不枚举（只亮充电灯）；拔插 USB 不能复位模组。
> - §2：文件包缺 `exgnss.lua` 与 `lbsLoc2.lua`（gnss_app 依赖，Luatools 合并会报缺文件），已补到 `firmware/wearable-evt0/libs/`，烧录时一并加入。
> - §4.5：烧录时勾「清除KV分区」「清除FS分区」；出厂 V2044 程序已被覆盖且无备份。
> - §5：本次 `features` 全部 false（含 mqtt），F1 已通过；F2 待日志。

## 1. 背景与目标

PetPal 宠物项圈 EVT0，用合宙 **Air8201G-BLMQ** 板（核心是 Air780EGH，Cat.1 + GNSS + BLE，LuatOS 脚本运行时）。
现阶段只做板级功能调试。烧录工具 Luatools 只有 Windows 版，所以烧录这一步在 Windows 上做，其余调试在 Mac 上做。

这次要做的只有三件事：

1. 把 **底层固件** 和 **调试脚本** 烧进板子。
2. 看到 **F1**：开机日志打印 `petpal_evt0 001.000.001`、`lastReson`、`features`。
3. 看到 **F2**：`IP_READY after N s`（要求 ≤ 60 s），后面每 30 s 一行 `rsrp/rssi/csq`。

把日志和几项记录值交回来即完成。**不要**往后做 F3 以后的功能，除非另外给了 MQTT 参数。

## 2. 文件包内容

| 文件 | 用途 |
|---|---|
| `LuatOS-SoC_V2030_Air780EGH_1.soc` | 底层固件，最新 V2030（2026-03-20）标准版 `_1`，11 MB，sha256 `0254182b72465409097c3f17186f8c4867eb175f9ed1da6d5b23b3e8eaa334eb` |
| `wearable-evt0/*.lua`（8 个） | 调试脚本：`main.lua` `net_app.lua` `mqtt_app.lua` `gnss_app.lua` `gsensor_app.lua` `power_app.lua` `actuator_app.lua` `ble_app.lua` |
| `wearable-evt0/config.example.lua` | 配置模板，要复制成 `config.lua` 一起烧（见第 5 节） |
| `bringup_log_header.csv` | 回传记录的字段 |
| 本文件 | |

不在包里、需要联网下载的：

- Luatools：`https://luatos.com/luatools/download/last`（302 到 `Luatools_v3.exe`，约 73 MB）。
- 备用底层固件 V2016 全后缀包：`https://cdn6.vue2.cn/Luat_tool_src/v2tools/LuatOS_Air780EGH/LuatOS-SoC_V2016_Air780EGH.zip`（248 MB），仅在 V2030 异常时对比用。
- V2030 全部后缀目录：`https://cdn18.luatos.com/files/Air780EGH/LuatOS_Air780EGH/LuatOS-SoC_V2030_Air780EGH/`。

## 3. 硬件连接

- 板子：Air8201G-BLMQ，自带 BTB 调试板，上面有 Type-C。
- 插 SIM（可上网的 Cat.1 卡），接 4G 天线（没有天线不要测 F2，射频功放空载有风险，且不会注册）。
- Type-C 直接接电脑机箱 USB 口，用带数据线芯的线，**不要经无源 hub**，4G 注册瞬间电流会超过 hub 的供电能力。
- 插上后设备管理器应出现若干个 "USB 串行设备 (COMx)"（一般 2～4 个）。记下 VID/PID 和 COM 号。
- 若带黄色叹号：Luatools 自带驱动安装入口（工具菜单里）；装完重插。仍不行就把 VID/PID 和错误截图回传，停在这里。

## 4. Luatools 操作

1. 运行 `Luatools_v3.exe`，首次会自解压并联网更新，等它完成。记录 Luatools 版本号。
2. 顶部 **项目管理测试** → **创建项目**，项目名 `wearable-evt0`。
3. **选择底层固件**：浏览到包里的 `LuatOS-SoC_V2030_Air780EGH_1.soc`（不要点“下载最新固件”，我们要固定版本）。
4. **添加脚本/资源文件**：加入 8 个 `.lua` 和填好的 `config.lua`（`config.example.lua` 不要加）。
5. 板子已插好，点 **下载底层和脚本**。Luatools 会通过 USB 自动让模组进下载模式；如果一直“等待设备”，按住板上 BOOT 键再重新上电/重插 USB。
6. 下载完成板子自动重启，Luatools 日志窗口开始滚动。**不要关窗口**，看第 6 节。
7. 用 Luatools 的“保存日志”把整段日志存成文本文件（或从 Luatools 目录下的日志文件夹拷出来）。

## 5. config.lua 怎么填

把 `config.example.lua` 复制为 `config.lua`，只改这几处，其余保持默认：

```lua
device_id = "collar-evt-001",
fw = "evt0.0.1",
features = {
    mqtt = false,      -- 没有 MQTT 参数时必须关，否则会连不上 broker.example.com 一直重试刷屏
    gnss = false, gsensor = false, power = false, actuator = false, ble = false, lowpower = false,
},
```

只有另外拿到了 MQTT 的 host/user/pass 和 CA 证书文件，才把 `mqtt = true` 并把 `ca.crt` 一起加入烧录列表。

## 6. 通过标准与要回传的东西

日志里要能找到（示例）：

```
I/user.main petpal_evt0 001.000.001 collar-evt-001 evt0.0.1
I/user.main lastReson 0 0 0 cold boot
I/user.main hmeta Air780EGH ...
I/user.main features {"mqtt":false,...}
I/user.net waiting SIM/network ...
I/user.net IP_READY after 12.3 s status 1
I/user.net imei 861***********234 iccid 898***************56
I/user.net rsrp -85 rssi -60 csq 22 status 1
```

回传：

1. 完整日志文本文件（至少覆盖开机后 3 分钟）。
2. 按 `bringup_log_header.csv` 填一行：`date, device_id=collar-evt-001, board_type=BLMQ, fw_hash=V2030_1+evt0.0.1, sim_registered_s=<IP_READY 秒数>, rsrp_dbm=<第一次 rsrp>, tester, notes=<Luatools 版本、VID/PID、COM 号、有无异常>`，其余字段留空。
3. 任何异常：Luatools 报错截图、设备管理器截图、`E/` 或 `W/` 开头的日志行。

不通过的判定：

- 日志没有 `petpal_evt0` → 脚本没烧进去或 `config.lua` 语法错，看日志开头是否有 `main.lua` 报错。
- 60 s 内没有 `IP_READY` → 先看 `mobile.status()` 值、天线和 SIM，再换一张卡试；把日志回传即可，不用自己调。

## 7. 硬性规则

- IMEI / ICCID / SIM 号 只能以日志里的脱敏形式出现在回传内容里，不要额外读取和抄录完整值。
- `config.lua` 里若填了任何凭据，不要回传、不要放进任何仓库。
- 不要打开 `actuator`（马达/LED）和 `lowpower`，不要动其它后缀的底层固件，除非记录了原因。
- 板子不要无人值守长时间通电。

## 8. 参考

- 合宙 Luatools 教程：`https://docs.openluat.com/common/Luatools/`
- Air780EGH 固件版本页：`https://docs.openluat.com/air780egh/luatos/firmware/version/`
- 脚本源码与官方 demo 参考在 Mac 上的仓库 `~/petpal-collar-evt0/`（本任务不需要）。
