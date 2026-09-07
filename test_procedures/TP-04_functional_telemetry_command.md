# TP-04 遥测 / 命令 / 状态机 / 缓存功能测试

**目的**：验证项圈 → Broker → 后端 → App 全链路及反向命令链路，以及五态状态机与离线缓存。
**对应方案**：3.2～3.5、6 (9/7～9/11)、7.1。
**样本**：每台样机独立执行。

## 前置条件

- Broker 已按 3.2 配置：每设备独立凭据、ACL、TLS 1.2+、Last Will。
- 后端 MQTT Bridge 运行，能提供 `GET /api/collar/devices`、`GET /api/collar/{id}/telemetry`、`POST /api/collar/{id}/commands`。
- 后端将收到的原始消息按 topic 落盘为 JSONL（用于工具校验）。

## A. 遥测发布（≥500 条 / 台）

1. 设 routine 模式，遥测周期临时调为 30 s，运行 ≥5 h。
2. 从后端导出 `telemetry.jsonl`，运行 `tools/telemetry_validator.py`。
3. 检查：schema 通过率 100%；seq 连续（缺口需能解释：断网补传/重启）；无 `0,0` 坐标；`position=null` 时保留 last_fix。
4. 人为发送重复 seq（用 `tools/mqtt_sim.py --dup`），确认后端去重。

## B. 命令与 ACK（≥100 条 / 台）

1. 依次下发 `SET_MODE`、`LOCATE_NOW`、`VIBRATE`、`LED` 各 ≥25 条，间隔满足 30 s 冷却。
2. 记录 `commands.jsonl` / `acks.jsonl`，运行 `tools/ack_checker.py`。
3. 检查：≥99% 得到最终 ACK（executed / rejected）；0 次重复执行（同 id 重发不重复震动，用示波器/马达电流确认）；P95 延迟 ≤10 s。
4. **安全上限**：后端下发 `duration_ms=2000, count=10` → 固件必须裁剪或拒绝并返回原因；`expires_at` 已过 → rejected；低电量/充电中 → rejected。
5. 目标设备错误 / 时间异常的命令 → 拒绝且不执行。

## C. 状态机（每模式 ≥20 次切换）

| 转换 | 触发方法 | 检查 |
|---|---|---|
| stationary ↔ routine | 静置 / 摇动（G-sensor） | 上报周期、GNSS 开关、UI 状态一致 |
| routine → lost | App 启用寻宠 / 模拟围栏触发 | 15～30 s 上报，GNSS 连续，2 h 后续期提示 |
| any → low_power | 电量 <15%（可用 sim 电压或固件注入） | 60 min 心跳、执行器被拒 |
| any → charging | 接入充电 | 5 min 上报、震动被拒、允许 FOTA |

## D. 断网补传（≥5 次 / 台）

1. 断网（拔天线 / 衰减盒 / 关 Broker）≥10 min，期间产生 ≥20 条遥测。
2. 恢复；检查 ≤2 min 重连，缓存按 seq 顺序补传，后端可追溯。
3. 4G 断开/恢复 ≥20 次，无需人工重启。
4. 缓存满（1000 条）行为：最旧被覆盖且有事件记录。

## 输出

`records/functional_log.csv` 每台一行汇总；工具输出粘贴到 G1 记录。
