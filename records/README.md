# records

所有台账为 CSV，第一行是字段说明。原始仪器数据放 `raw/<device_id>/<TP>_<date>/`，不入 git。

| 文件 | 由哪个规程填写 |
|---|---|
| device_ledger.csv | TP-01（登记）、9/22 装配（出生证字段） |
| bringup_log.csv | TP-01 |
| battery_incoming.csv | TP-02 |
| power_log.csv | TP-03 |
| functional_log.csv | TP-04 |
| antenna_ab.csv | TP-05 |
| power_integrity.csv | TP-06 |
| fota_fault_log.csv | TP-07 |
| mechanical_safety.csv | TP-08 |
| positioning_log.csv | TP-09 |
| wear_trial_log.csv | TP-10 |
| defects.csv | 所有规程 |
| procurement_log.csv | 采购 |
| risk_register.csv | 每周一/四风险检查 |
| fae_questions.md | 供应商沟通 |
| gate_records/ | G0～G4 |
| daily/ | 每日进展 |

带 `_local_only` 后缀的字段（IMEI/ICCID/SN）只保留在本机副本，提交前请清空或使用 `git update-index --skip-worktree records/device_ledger.csv`。
