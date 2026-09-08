# 板级功能调试进度

板子：BLMQ（LM / BLMQ / G）  设备号：collar-evt-___  底层固件版本：________  脚本版本：evt0.0.___

| # | 功能 | 状态 | 日期 | 日志文件（records/raw/…） | 备注 |
|---|---|---|---|---|---|
| F0 | 烧录环境（Windows/VM + Luatools）可用 | 进行中 | 2026-09-07 | | 改为另一台 Windows 电脑烧录，交接单 docs/08 + petpal-flash-kit.zip；Mac 虚拟机方案 docs/07 作备用 |
| F1 | 开机、日志、版本、开机原因 | ☐ | | | |
| F2 | SIM 注册、IP_READY、信号 | ☐ | | | 注册耗时 ___ s，RSRP ___ |
| F3 | MQTT/TLS 单向校验；错误 CA 失败 | ☐ | | | |
| F4 | GNSS 冷/热启动 fix | ☐ | | | 冷 ___ s / 热 ___ s / 卫星 ___ |
| F5 | DA267 WHO_AM_I、震动中断、步数 | ☐ | | | INT 引脚实测 GPIO ___ |
| F6 | ADC 电压、VBUS 充电检测 | ☐ | | | ADC ___ mV vs 万用表 ___ mV |
| F7 | LED / 马达 GPIO 输出，默认关 | ☐ | | | 引脚 ___ |
| F8 | 遥测闭环 100 条通过 validator | ☐ | | | |
| F9 | 命令 ACK 40 条通过 ack_checker；裁剪与冷却 | ☐ | | | |
| F10 | BLE 广播被手机扫到 | ☐ | | | |
| F11 | 低功耗电流（可选） | ☐ | | | |
| F12 | FOTA（可选） | ☐ | | | |
| F13 | 断网缓存补传（可选） | ☐ | | | |

## 问题记录

| 日期 | 功能 | 现象 | 处理 | 状态 |
|---|---|---|---|---|
| 2026-09-07 | F0 | Mac mini 无 Windows 虚拟机，Luatools 无法运行；模组未接 USB（Air8201G 无板载 Type-C，需 BTB 扩展板） | 已定 Mac+UTM 路线，板子 BLMQ 自带 Type-C；工具与固件已下载到 ~/petpal-vm-share | 进行中 |
