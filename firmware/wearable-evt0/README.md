# wearable-evt0 板级调试固件（LuatOS / Air8201G）

按 `config.lua` 的 `features` 逐项打开模块。每个模块只依赖 `_G.CFG` 与 `_G.STATE`，可单独验证。

| 文件 | 功能 | 对应清单 |
|---|---|---|
| `main.lua` | 入口：版本、开机原因、errDump、看门狗、按开关 require 模块 | F1 |
| `net_app.lua` | 等 IP_READY，打印脱敏 IMEI/ICCID，周期刷新 RSRP/RSSI | F2 |
| `mqtt_app.lua` | MQTT/TLS 单向校验，telemetry/state/ack，cmd 去重/过期/硬上限 | F3 F8 F9 |
| `gnss_app.lua` | exgnss 定时或成功即关；开机一次，之后按模式周期 | F4 |
| `gsensor_app.lua` | DA267 原始寄存器初始化、震动中断、三轴读取 | F5 |
| `power_app.lua` | ADC0 电压、CH_VBAT 对照、VBUS 充电检测、PWRKEY 长按关机 | F6 |
| `actuator_app.lua` | LED/马达 GPIO，上电默认关，≤500 ms×3、30 s 冷却 | F7 |
| `ble_app.lua` | 板载蓝牙 iBeacon 广播 | F10 |
| `console_app.lua` | USB 用户虚拟串口命令台：`set <feature> 0/1` 写 KV 覆盖功能开关、`status`、`reboot` 等，配合 `tools/usb_cmd.py`，切功能不用重烧 | F0 |
| `config.example.lua` | 配置模板，复制为 `config.lua`（gitignore） | |
| `libs/` | `exgnss.lua`、`lbsLoc2.lua` 官方扩展库副本，随包烧录 | F4 |

## 烧录包

`main.lua` `console_app.lua` `net_app.lua` `mqtt_app.lua` `gnss_app.lua` `gsensor_app.lua` `power_app.lua` `actuator_app.lua` `ble_app.lua` `config.lua` `ca.crt`
加 `libs/exgnss.lua` `libs/lbsLoc2.lua`（gnss_app 依赖，底层不内置，见 `libs/README.md`），
外加底层固件（Air780EGH 系列 LuatOS，版本记录到 `records/bringup_log.csv`）。用 PWM 引脚时再加 LuatIO 生成的 pins json。

## 与官方参考的对应

| 本模块 | 参考 |
|---|---|
| gnss_app | `reference/luatos-air8201/project/Air8201G/factory/code/mygps.lua`、`demo/gnss/Air8201G/libgnss/gnss.lua` |
| gsensor_app | `.../factory/code/gsensor.lua`、`demo/gsensor/da267_app.lua` |
| power_app | `.../factory/code/mypower.lua` |
| ble_app | `.../factory/code/myble.lua` |
| mqtt_app | `demo/mqtt/mqtts_ca/mqtts_ca_main.lua` |

## 功能开关的两层来源

1. `config.lua` 的 `features`（烧录时固定）。
2. KV 键 `feat_override`（`console_app` 通过 USB 命令写入，优先级更高）。Mac 上：

```bash
python3 tools/usb_cmd.py get              # 看当前生效值与覆盖
python3 tools/usb_cmd.py set gsensor 1    # 写覆盖
python3 tools/usb_cmd.py reboot           # 重启生效
python3 tools/usb_cmd.py clear            # 回到 config.lua
```

Luatools 烧录勾了「清除KV分区」会一并清掉覆盖。

## 未实现（功能都通后再加）

离线 ring buffer 持久化补传、FOTA（`libfota3`，参考 `factory/code/ota_manegement.lua`）、stationary 判定与 PSM+。
