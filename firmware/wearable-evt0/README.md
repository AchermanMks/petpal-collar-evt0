# wearable-evt0 固件骨架（LuatOS / Air8201G）

> 这是 **bring-up 与测试用骨架**，不是正式固件。正式固件在 `pet-collar` 仓库的 `wearable-evt0` 分支演进；此处保持与 `schemas/` 契约一致，供 TP-01 / TP-04 使用。

## 文件

| 文件 | 说明 |
|---|---|
| `main.lua` | 入口：网络注册 → MQTT/TLS → GNSS → 周期遥测；命令处理含固件本地安全上限 |
| `config.example.lua` | 配置模板；复制为 `config.lua` 填入 Broker 与设备凭据（已 gitignore） |
| `safety.lua` | 执行器硬上限与冷却，独立模块便于审查 |

## 版本规则

- 固件版本字符串：`evt0.<minor>.<patch>[-rcN]`，与 `schemas/telemetry.schema.json` 的 `fw` 正则一致。
- 设备 ID：`collar-evt-NNN`，来自 `records/device_ledger.csv`，写入 `config.lua`，不硬编码在 `main.lua`。
- 每次烧录记录 LuatOS 底层固件版本与脚本哈希到 `records/bringup_log.csv`。

## 烧录（TP-01 步骤 3）

1. Luatools 选择 Air8201G 对应底层固件（版本记录在此处：`LuatOS core: ______`）。
2. 脚本文件：`main.lua`、`safety.lua`、`config.lua`。
3. 首次上电用限流台式电源，不接锂电。

## 明确不包含

电弧、摄像头、MJPEG、Wi-Fi 常在线、HTTP Server、LittleFS 音频上传。凭据不在源码中。
