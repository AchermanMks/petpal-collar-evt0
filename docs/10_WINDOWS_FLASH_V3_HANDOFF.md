# 交接：Windows 上烧录 flash-kit v3 并验证 USB 命令台 / SIM 诊断

> 给 Windows 机器上的 Claude 的任务说明，自包含。上一轮交付见同目录 `WINDOWS_FLASH_REPORT.md`（你 2026-09-09 写的），本轮是它的续集。
> 配套文件包：`petpal-flash-kit-v3.zip`（底层固件不变，脚本更新，本说明在包内为 `README_HANDOFF_V3.md`）。

## 1. 背景与目标

板子还是那块 Air8201G-BLMQ（Air780EGH_A11），上次烧的 V2030_1 + petpal 脚本在跑，F1 通过。之后 Mac 端发现两件事：

1. SIM 断电重插两次，冷启动后仍 `+CPIN: NOT READY`、`status 0`，模组读不到卡。
2. 功能开关写死在 `config.lua`，每开一项都要回 Windows 重烧，太慢。

v3 脚本解决这两件事：`net_app.lua` 加了 `mobile.simid(2)` 自动扫两个卡槽并每 10 s 打 SIM 诊断；新增 `console_app.lua`，通过 USB 用户虚拟串口收命令，把功能开关写进 KV，重启生效。**本轮只要做一次烧录、看三组日志、测一次命令口、回传结果。** 之后所有功能调试都在 Mac 上做，不再需要 Windows。

## 2. 文件包内容（petpal-flash-kit-v3.zip）

| 文件 | 用途 |
|---|---|
| `LuatOS-SoC_V2030_Air780EGH_1.soc` | 底层固件，与上次相同，sha256 `0254182b…334eb`，**不要点“下载最新固件”** |
| `wearable-evt0/*.lua`（9 个 app） | `main.lua` `console_app.lua`(新) `net_app.lua`(改) `mqtt_app.lua` `gnss_app.lua` `gsensor_app.lua` `power_app.lua` `actuator_app.lua` `ble_app.lua` |
| `wearable-evt0/libs/exgnss.lua` `lbsLoc2.lua` | 上次缺的两个扩展库，已带上 |
| `wearable-evt0/config.example.lua` | 复制成 `config.lua`，填法同上次（见 §4） |
| `redact_ids.py` | 回传日志前打码 IMEI/ICCID |
| `CHANGES_v3.md` | 改动清单 |
| `README_HANDOFF.md` | 上一轮交接单（含勘误），流程细节可查 |

## 3. 硬件要点（上次实测，直接沿用）

- 拨动开关是电池总开关，必须置“通”，否则插 USB 也不枚举。USB 不给模组供电，拔插 USB 不能复位，复位按 `reset`。
- **没有 BOOT 键**。进下载模式的做法：插好 USB → 按 `reset` → COM 口出现后**立即**点「全量下载」。
- 正常运行 USB 枚举 2 个 COM：soc log 口（上次 COM12）+ 用户虚拟串口（上次 COM13）。命令台用的就是用户虚拟串口。
- 板子现在应插着 SIM（Mac 端插的），不要拔。若要重插，先拨断开关并拔 USB。

## 4. 操作步骤

1. 解压到 `D:\Luatools\petpal-flash-kit-v3\`。
2. `config.example.lua` → 复制为 `config.lua`，改：`device_id = "collar-evt-001"`，`fw = "evt0.0.1"`，`features` 全部 `false`（含 mqtt、lowpower）。其余不动。
3. Luatools 3.4.9「项目管理」：可以沿用上次的 `petpal-evt` 项目，把脚本列表**清空后重新加入** 12 个文件：9 个 app lua + `libs/exgnss.lua` + `libs/lbsLoc2.lua` + `config.lua`。底层 CORE 仍选包内 `.soc`。
4. 勾「清除KV分区」「清除FS分区」「添加默认扩展库」；「忽略脚本依赖性」不勾。依赖检查应通过（不再报缺 exgnss）。
5. 按 §3 的时机点「全量下载(底层+脚本)」。
6. 烧完自动重启，让日志跑满 **3 分钟**，保存日志文件。

## 5. 要看到的日志

开机段（F1，和上次一样）：

```
I/user.main petpal_evt0 001.000.001 collar-evt-001 evt0.0.1
I/user.main lastReson 0 0 0 cold boot
I/user.main features {"mqtt":false,...}
```

v3 新增的三行，缺一行就是没烧对：

```
I/user.console listening on VUART_0; commands: ping get set clear status locate reboot
I/user.net simid auto true ...
I/user.net still waiting 10 s status <n> simid <n> iccid <nil 或 898***...> csq <n>
```

`still waiting` 每 10 s 一行。重点看 `simid` 和 `iccid`：
- iccid 有值 → 卡读到了，等 `IP_READY after N s`。
- iccid 一直 nil → 卡仍未识别，记下 status/simid 的值即可，**不用自己调**。

## 6. 命令台测试（用户虚拟串口）

用任意串口工具（Luatools 自带的串口调试、或 Python `pyserial`）打开**用户虚拟串口**（非 soc log 口），115200，发送一行文本（结尾 `\n`）：

| 发送 | 期望回复 |
|---|---|
| `ping` | `pong petpal_evt0 001.000.001` |
| `get` | `ok features {...} override {}` |
| `status` | `ok status <n> simid <n> iccid <…> csq <n> rsrp <n> online false mem …` |

Python 写法（有 pyserial 时）：

```python
import serial, time
s = serial.Serial("COM13", 115200, timeout=1)   # 换成实际的用户虚拟串口
for c in ("ping", "get", "status"):
    s.write((c + "\n").encode()); time.sleep(1); print(c, "->", s.read(500).decode(errors="replace").strip())
```

**不要发 `set` 和 `reboot`**，功能开关留给 Mac 端按顺序开。ping 无回复时，先确认打开的是用户虚拟串口而不是 log 口，再看日志里有没有 `console listening` 那行。

## 7. 回传

1. 3 分钟日志文件，先打码：`python redact_ids.py trace_xxx.txt`，回传生成的 `*.redacted.txt`。
2. §5 三行新增日志的原文（打码后）+ 最后几行 `still waiting` 或 `IP_READY`。
3. §6 三条命令的实际回复。
4. 一行记录：Luatools 版本、COM 号（log 口 / 用户口）、有无异常、`E/` `W/` 行。

## 8. 硬性规则

- IMEI/ICCID 只能以打码形式出现在回传内容里；底层日志会打印完整 IMEI，所以必须先跑 `redact_ids.py`。
- 不改脚本、不换底层固件版本、不点「下载最新固件」。
- 不开 `actuator`、`lowpower`；不发 `set`/`reboot`。
- 不做 F3 以后的功能；板子不要无人值守长时间通电。
- 遇到「模块重启超时」「缺少 xxx.lua」「CommError」按 `README_HANDOFF.md` 勘误与 `WINDOWS_FLASH_REPORT.md` §4 处理，还是不行就截图回传，停在那里。
