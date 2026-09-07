# TP-01 模组 Bring-up 与硬件登记

**目的**：确认每块 Air8201G-LM / BLMQ / 基础版板能识别 SIM、注册网络、输出日志、获得 GNSS fix，并建立唯一设备标识与硬件版本记录。
**对应方案**：4.2 到货验收、6 (9/3)、6 (9/4 G0)。
**样本**：所有到货板（LM ×8、BLMQ ×2、基础版 ×2）。

## 前置条件

- Luatools 已安装；固件版本记录在 `firmware/wearable-evt0/README.md`。
- 调试板 + FPC 线；SIM 卡已激活（无专网白名单限制）。
- 供电：限流台式电源 3.8 V / 限流 1.5 A（首次上电不用锂电）。
- 官方天线套件（4G / GNSS / BLE 各一）。
- 室外或窗边可见天空的位置用于 GNSS。

## 步骤

1. **到货外观**：型号丝印、数量、IPEX 座完整、无焊点损伤；拍照存 `records/raw/incoming/`。
2. **登记**：在 `records/device_ledger.csv` 新增一行，分配 `collar-evt-NNN`（BLMQ 用 `dev-blmq-NN`）。IMEI/ICCID 只写台账本地副本。
3. **烧录**：烧最小 bring-up 固件（`firmware/wearable-evt0/main.lua`，`config.lua` 填测试 Broker）。记录固件哈希。
4. **SIM 与网络**：读取 IMEI、ICCID、注册状态、RSRP/RSSI；记录注册耗时。
5. **MQTT/TLS**：发布一条 `state`（retained）并从后端/`mosquitto_sub` 收到；记录往返时间。
6. **GNSS**：冷启动 TTFF（断电 ≥30 min 后）、热启动 TTFF、卫星数、首个 fix 精度；各 ≥3 次。
7. **G-sensor**：静止→轻敲，确认中断/唤醒触发；记录阈值配置。
8. **BLE（LM/BLMQ）**：广播可被手机扫到；记录 RSSI 距离 1 m / 5 m。
9. **充电状态**：接入 4.2 V 充电输入，读取充电状态位；确认 NTC 行为（有/无）。
10. **初始功耗**：PPK2 记录常规在线、低功耗在线、PSM+ 各 ≥5 min 平均；示波器记录 LTE 发射峰值。写入 `records/power_log.csv`。
11. **三天线共存**：在 BLMQ 上按 2.5 节布置试验最小间距，记录 RSRP / TTFF 变化。
12. 所有结果填入 `records/bringup_log.csv`。

## 记录字段

`device_id, board_type, hw_rev, fw_hash, sim_registered_s, rsrp_dbm, mqtt_rtt_ms, gnss_cold_ttff_s, gnss_hot_ttff_s, sats, gsensor_wake_ok, ble_seen_ok, charge_status_ok, ntc_present, idle_ma, lp_online_ma, psm_ua, lte_peak_ma, notes`

## 通过标准

- 每块板：SIM 注册、MQTT/TLS 往返一次、GNSS 有效 fix、G-sensor 可唤醒。
- LTE 峰值 ≤1 A 且不复位（台式电源）。
- 全部板均有唯一 device_id 与硬件版本记录。

## 失败处置

无法注册 / 无 fix / 复位 → 记入 FAE 问题清单（`records/fae_questions.md`），G0 按方案回退路线决策。
