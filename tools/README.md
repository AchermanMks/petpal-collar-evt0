# tools

| 脚本 | 用途 | 规程 |
|---|---|---|
| telemetry_validator.py | 遥测 JSONL schema + 业务规则 + seq 缺口/重复 | TP-04 A |
| ack_checker.py | 命令/ACK 关联：最终 ACK 率、重复执行、P50/P95、震动上限裁剪检查 | TP-04 B |
| power_analyzer.py | 电流 CSV 积分、平均/峰值、唤醒计数、300 mAh 续航外推 | TP-03 |
| gnss_accuracy.py | 遥测位置 vs 手机 GPX 参考：fix 成功率、中位/P95 误差 | TP-09 |
| mqtt_sim.py | 模拟项圈接入 Broker，答复命令并执行固件同款安全上限；可注入重复 seq | 后端 soak、TP-04 A4 |
| serial_log.py | 抓普通文本串口（UART 转 USB）日志到 records/raw，并抽出 JSON 行供上面两个工具用 | 外接 UART 时 |
| usb_log.py | **Mac 直读 Air780EGH USB 日志口**（Luatools 帧格式解码、自动选口、IMEI 打码），落到 records/raw | F1～F9 |
| luacheck.py | 用 lupa 对 firmware/wearable-evt0 全部 lua 做语法检查（`pip install lupa`） | 改固件后 |
| usb_cmd.py | 通过 USB 用户虚拟串口给 console_app 发命令：`set <feature> 0/1`、`get`、`status`、`reboot`，切功能不重烧 | F3～F10 |
| redact_ids.py | 回传/归档前给日志里的 IMEI/ICCID/IMSI 打码（底层固件会打印完整 IMEI） | F1～F2 日志回传 |

安装：`pip install -r tools/requirements.txt`。所有脚本 `--json` 可输出机器可读结果；退出码 0 表示通过。
自测：`python3 tools/selftest.py` 生成合成数据并跑一遍全部脚本。
