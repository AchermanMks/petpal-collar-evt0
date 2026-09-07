# reference

合宙 LuatOS 开源仓库（MIT License）中与 Air8201G 直接相关的官方示例与出厂工程副本，只读参考，不要在这里改代码。

- 来源：https://github.com/openLuat/LuatOS ，commit `f9601cc`，路径 `module/Air8201/` 与 `module/Air780EHM_Air780EHV_Air780EGH/demo/`
- 拉取日期：2026-09-07

| 目录 | 用途 |
|---|---|
| luatos-air8201/gnss/Air8201G | libgnss / exgnss 定位 demo（UART2、GPIO21、AGPS） |
| luatos-air8201/gsensor | DA267 demo（I2C1、0x26、GPIO24/39） |
| luatos-air8201/mqtt | mqtt / mqtts / mqtts_ca / 双向校验 demo，含 openluat_root_ca.crt |
| luatos-air8201/ble | BLE 外设 demo（Air5101 路径） |
| luatos-air8201/project/Air8201G/factory | 出厂定位器工程：电源 ADC/VBUS/PWRKEY、DA267 原始驱动、exgnss 同步定位、bluetooth 广播、FOTA |
| luatos-air8201/Air780EGH_series | 同系列 pwm / adc / gpio demo 与 pins_Air780EGH.json |

出厂工程里的 `PRODUCT_KEY`、`AUTH_KEY` 是合宙测试值，不要用于本项目。
