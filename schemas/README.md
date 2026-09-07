# MQTT 契约 schema

对应方案 3.2～3.4。后端 MQTT Bridge 与 `tools/telemetry_validator.py` 共用这些文件；修改需同步更新 `pet-collar/backend/docs/API_CONTRACT`。

| Topic | Schema | QoS | retained |
|---|---|---|---|
| `petpal/v1/{device_id}/telemetry` | telemetry.schema.json | 1 | 否 |
| `petpal/v1/{device_id}/event` | event.schema.json | 1 | 否 |
| `petpal/v1/{device_id}/state` | state.schema.json | 1 | 是（LWT → `online=false`） |
| `petpal/v1/{device_id}/cmd` | command.schema.json | 1 | 否 |
| `petpal/v1/{device_id}/ack` | ack.schema.json | 1 | 否 |

业务规则（schema 表达不了的，由 validator 检查）：
- 无可靠定位不得上报 `0,0`；`position=null` 时应带 `last_fix`。
- `seq` 单调递增；缺口需对应 `reboot` 事件或 `replayed=true` 补传。
- 同一 command id 至多一次 `executed`。
- VIBRATE 的 `applied_args` 必须在固件硬上限内，即使下发参数超限。
