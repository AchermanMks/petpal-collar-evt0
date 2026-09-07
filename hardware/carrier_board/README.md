# 功能载板 Rev A 要求（方案 2.3）

- 2 层、0.8 mm FR-4、沉金；只承载低速控制和电源，不承载 LTE/GNSS 射频匹配。
- 测试点：VBAT、GND、充电输入、PWM/GPIO（马达、LED、蜂鸣）、I²C、UART/调试、PWRKEY、RESET。
- 震动马达：逻辑电平 MOSFET + 反向/瞬态保护；上电默认关闭（下拉）。
- LED 静态电流 ≤2 mA。
- 充电入口：反接、过流、湿水短路保护。
- 若 Air8201G-LM 充电管理无 NTC 行为：载板补温度检测 + 软件禁止充电。
- 电池独立保护板，软件保护不是唯一保护。

## 交付物（订单 C，9/9 释放，9/14 到货 20 片）

`schematic/`、`gerber/`、`assembly/`、`bom_carrier.csv`（此处待放）。

## 到货检查（TP-01 扩展）

外观、沉金、测试点导通、MOSFET 上电状态、LED 静态电流。
