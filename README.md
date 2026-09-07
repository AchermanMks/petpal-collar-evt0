# petpal-collar-evt0 — 可佩戴宠物项圈 EVT0 硬件测试项目

> 迭代版本：Air8201G-LM 成品 PCBA + 功能载板 + 300 mAh 锂电 + 独立天线 + 3D 打印外壳
> 上一版本：`~/pet-collar`（ESP32 + A7670E 开发板 Demo、iOS App、Linux 后端）
> 测试方案来源：飞书《宠物项圈MPV方案》→ `docs/00_TEST_PLAN_SOURCE.md`
> 周期：2026-09-01 ～ 2026-09-30；本项目建立于 2026-09-07（Week 2 起点）

> **2026-09-07 范围调整**：当前阶段只做 **板级功能调试**，目标是在手头 Air8201G 板子上把 10 项功能调通。执行方案见 `docs/05_BOARD_BRINGUP_PLAN.md`，硬件/API 事实见 `docs/06_AIR8201G_HARDWARE_NOTES.md`，烧录环境（Mac + UTM Windows）见 `docs/07_F0_MAC_UTM_FLASHING.md`，进度记在 `records/bringup_checklist.md`。整机测试规程 TP-05/06/08/09/10 与 Gate 暂缓。

本仓库只做一件事：**按测试方案，对迭代版本的项圈硬件产出可信的工程证据。**
固件、后端、App 的正式代码仍在 `pet-collar` 仓库演进；这里放的是测试规程、记录模板、分析工具、接口契约（schema）和硬件参考资料。

## 目录

| 目录 | 内容 |
|---|---|
| `docs/` | 测试方案原文、与上一版的差异、验收标准、安全停止条件、Gate 定义 |
| `test_procedures/` | TP-01～TP-10 测试规程，每份含前置条件、步骤、记录字段、通过标准 |
| `records/` | 台账与记录模板（CSV/Markdown）；`raw/` 放仪器原始数据（不入 git） |
| `schemas/` | MQTT telemetry / event / state / cmd / ack 的 JSON Schema |
| `tools/` | 遥测校验、功耗分析、命令 ACK 统计、GNSS 精度、MQTT 模拟器 |
| `firmware/wearable-evt0/` | LuatOS 板级调试固件（模块化，按 `config.lua` 开关功能），凭据不入库 |
| `firmware/reference/` | 合宙官方 Air8201 demo 与出厂工程副本（MIT），只读参考 |
| `hardware/` | BOM v0.1、载板/外壳要求、Air8201G 3D 模型参考 |

## 测试规程索引

| 编号 | 名称 | 对应方案章节 | 关联 Gate |
|---|---|---|---|
| TP-01 | 模组 Bring-up 与硬件登记 | 6 (9/3)、4.2 到货验收 | G0 |
| TP-02 | 电池到货抽检 | 2.4、4.3 | G0/G1 |
| TP-03 | 功耗测试（八态 + 续航外推） | 2.4、7.2 | G1 |
| TP-04 | 遥测 / 命令 / 状态机 / 缓存功能测试 | 3.x、7.1 | G1 |
| TP-05 | 天线、射频与佩戴模拟 | 2.5、6 (9/16)、7.3 | G2 |
| TP-06 | 电源完整性与热测试 | 6 (9/15)、7.3 | G2/G3 |
| TP-07 | FOTA 与故障注入恢复 | 6 (9/18)、7.1 | G2 |
| TP-08 | 结构可靠性与安全专项 | 6 (9/23)、7.3、8 | G3 |
| TP-09 | 户外定位与弱网 | 6 (9/21) | G3/G4 |
| TP-10 | 受控试戴 | 6 (9/28～9/29)、8 停止条件 | G4 |

## 工作流

1. 每台样机到货或装配完成后，先在 `records/device_ledger.csv` 登记，取得 `collar-evt-NNN` 编号。
2. 按 TP 规程执行，原始数据放 `records/raw/<device_id>/<TP>_<date>/`，汇总写入对应 CSV。
3. 用 `tools/` 脚本生成统计，结果粘贴到 `records/gate_records/Gx.md`。
4. Gate 评审只看数据；不通过按 `docs/04_GATES.md` 的动作执行。
5. 每日进展写 `records/daily/YYYY-MM-DD.md`（沿用 pet-collar 的 daily_report 格式）。

## 快速开始

```bash
cd ~/petpal-collar-evt0
python3 -m venv .venv && source .venv/bin/activate
pip install -r tools/requirements.txt

# 校验一份遥测 JSONL（schema + 业务规则 + seq 去重）
python3 tools/telemetry_validator.py records/raw/collar-evt-001/TP-04_2026-09-08/telemetry.jsonl

# 分析 PPK2 导出的电流 CSV，外推 300 mAh 续航
python3 tools/power_analyzer.py records/raw/collar-evt-001/TP-03_2026-09-10/routine.csv --scenario routine

# 统计命令 ACK 率、P95 延迟、重复执行
python3 tools/ack_checker.py commands.jsonl acks.jsonl

# 抓取板子 USB 日志到 records/raw（烧录后在 Mac 上直接用）
python3 tools/serial_log.py /dev/cu.usbmodem1101 --device collar-evt-001

# 模拟一台项圈接入 Broker（后端 soak 测试用，凭据用环境变量）
MQTT_HOST=... MQTT_USER=... MQTT_PASS=... python3 tools/mqtt_sim.py --device collar-sim-001
```

## 硬性规则（来自方案 1.3 / 8）

- 动物版构建中不得存在电弧模块、电弧 GPIO/API 及任何入口。
- 凭据、SIM/IMEI 等设备标识不进 git、不进公开日志。
- 震动固件硬上限：单脉冲 ≤500 ms、单命令 ≤3 次、命令间隔 ≥30 s。
- 25°C 环境下可触表面 >42°C 或电芯 >45°C，立即停止。
- 锂电样机不得无人值守运行；充电时摘下项圈。
- 任何续航 / 精度 / 防水 / 安全数据，只认完整整机实测。

## 与上一版工程的衔接

| 旧仓库文件 | 在本项目中的用法 |
|---|---|
| `pet-collar/COLLAR_EVT_30_DAY_PLAN_2026-09.md` | 上一版方案，差异见 `docs/01_CHANGES_FROM_PREVIOUS.md` |
| `pet-collar/HARDWARE_BOM_POWER_BUDGET_v1.md` | 重量、续航、电源完整性约束，已并入 TP-03 / TP-06 |
| `pet-collar/JIELI_VS_AIR8201_COLLAR_COMPARISON_2026-09.md` | 模组选型依据；G0 回退路线参考 |
| `pet-collar/backend/docs/API_CONTRACT_v0.1.md` | collar 端点基线；本项目 `schemas/` 是 MQTT 侧契约 |
| `pet-collar/esp32_firmware/` | 仅提取 GPS / 马达 / 状态机思路，不复用摄像头与 Wi-Fi 架构 |
