# tools

| 脚本 | 用途 | 规程 |
|---|---|---|
| telemetry_validator.py | 遥测 JSONL schema + 业务规则 + seq 缺口/重复 | TP-04 A |
| ack_checker.py | 命令/ACK 关联：最终 ACK 率、重复执行、P50/P95、震动上限裁剪检查 | TP-04 B |
| power_analyzer.py | 电流 CSV 积分、平均/峰值、唤醒计数、300 mAh 续航外推 | TP-03 |
| gnss_accuracy.py | 遥测位置 vs 手机 GPX 参考：fix 成功率、中位/P95 误差 | TP-09 |
| mqtt_sim.py | 模拟项圈接入 Broker，答复命令并执行固件同款安全上限；可注入重复 seq | 后端 soak、TP-04 A4 |
| serial_log.py | Mac 上抓板子 USB/UART 日志到 records/raw，并抽出 JSON 行供上面两个工具用 | F1～F9 |

安装：`pip install -r tools/requirements.txt`。所有脚本 `--json` 可输出机器可读结果；退出码 0 表示通过。
自测：`python3 tools/selftest.py` 生成合成数据并跑一遍全部脚本。
