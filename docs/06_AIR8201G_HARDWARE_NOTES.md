# Air8201G 硬件与 API 备忘

来源：合宙 LuatOS 开源仓库 `module/Air8201/`（GitHub openLuat/LuatOS，2026-09 master），本地副本在 `firmware/reference/`。文档中心页面需要浏览器渲染，抓不到正文，以仓库代码为准。

## 型号

- Air8201G 基于 **Air780EGH** 模组；Air8201H 基于 Air780EHM。两者外设 API 一致，低功耗/PWM/GPIO/ADC demo 直接复用 `Air780EHM_Air780EHV_Air780EGH` 系列。
- 变体：Air8201G-LM（可佩戴，板载 BLE 5.2、音频、充电、DA267）、Air8201G-BLMQ（带 BTB 调试）、Air8201G-BQ。G-sensor demo 明确三者都板载 DA267。
- Air8201G 移除板载 Type-C，USB 经 BTB/焊盘引出；下载模式用 USB_BOOT。

## 引脚 / 资源

| 资源 | 值 | 来源 |
|---|---|---|
| GNSS 串口 | UART2，115200 | demo/gnss/Air8201G/libgnss |
| GNSS 供电 | GPIO21 高有效 | 同上 |
| GNSS 虚拟转发 | `libgnss.bind(2, uart.VUART_0)` 可在上位机看 NMEA | 同上 |
| AGPS | `http://download.openluat.com/9501-xingli/HXXT_GPS_BDS_AGNSS_DATA.dat` 写入 UART2，配合 `$AIDTIME` / `$AIDPOS` | 同上 |
| DA267 I2C | I2C1，地址 0x26，WHO_AM_I 寄存器 0x01 = 0x13 | demo/gsensor, project/factory |
| DA267 供电 | GPIO24 | 同上 |
| I2C 上拉使能 | GPIO28 | project/factory/gsensor.lua |
| DA267 INT | GPIO20（出厂工程）/ GPIO39（demo README）— **实测确认** | 两处不一致 |
| 电池 ADC | ADC0，`adc.setRange(adc.ADC_RANGE_MIN)` 后 open/get/close；分压 1M/300k，+140 mV | project/factory/mypower.lua |
| VBAT 直读 | `adc.CH_VBAT`（主供电脚电压） | Air780E 系列 adc demo |
| VBUS 检测 | `gpio.WAKEUP1`，PULLDOWN，BOTH 边沿 | project/factory/mypower.lua |
| PWRKEY | `gpio.PWR_KEY`，PULLUP，FALLING | 同上 |
| 红灯 | GPIO16 | 同上 |
| PWM | PWM4 = GPIO27/PIN16，PWM0 = PIN22，PWM1 = PIN20（需 LuatIO pins json 复用） | demo/pwm/pins_Air780EGH.json |
| SIM 热插拔 | `gpio.WAKEUP2` | project/factory/main.lua |
| USB 日志开关 | `pm.power(pm.USB, 1/0)` | 同上 |
| 低功耗 | `pm.power(pm.WORK_MODE, 1)` 常驻低功耗 | 同上 |
| 关机 | `pm.shutdown()` | 同上 |
| 开机原因 | `pm.lastReson()` → r1,r2,r3；(0,0,0)=冷启动 | project/factory/global_config.lua |
| BLE（板载） | `bluetooth.init()` → `:ble(cb)` → `adv_create{}` / `adv_data()` / `adv_start()`；`bluetooth.make_ibeacon_data()` | project/factory/myble.lua |
| BLE（Air5101 外挂） | `exril_5101.config_uart(2)` + `exril_5101_*` 模块 | demo/ble/peripheral/Air8201G_Air5101S |

## API 片段

```lua
-- 网络就绪等待（官方写法）
while not socket.adapter(socket.dft()) do sys.waitUntil("IP_READY", 1000) end

-- MQTT TLS 单向校验
local ca = io.readFile("/luadb/ca.crt")
local c = mqtt.create(nil, host, 8883, {server_cert = ca})
c:auth(client_id, user, pass, true)   -- clean session
c:on(function(client, event, data, payload, metas) ... end)  -- conack/recv/sent/disconnect/pong/error
c:connect()

-- exgnss 定时或成功即关
exgnss.setup({gnssmode = 1})
exgnss.open(exgnss.TIMERORSUC, {tag = "x", val = 60, cb = function(tag)
    if exgnss.is_fix() then local rmc = exgnss.rmc(0); local gga = exgnss.gga(0) end  -- 必须在 cb 内读
end})

-- DA267 原始寄存器（出厂工程）
-- RANGE 0x0F=0x01(4g), BW_ODR 0x10=0x07, INT_EN 0x16=0x87, INT_CFG 0x19=0x04, MODE 0x11=0x30, THS_X/Y/Z 0x39-0x3B
```

## 工具链

- Luatools：Windows only（闭源，wine 不可用）。macOS 需 Windows 虚拟机 + USB 直通，或另一台 Windows PC。
- 固件版本页：`https://docs.openluat.com/air780egh/luatos/firmware/version/`
- LuatIO（引脚复用 json）：`https://docs.openluat.com/air780epm/common/luatio/`
- 主题/项目版本：`PROJECT`、`VERSION="XXX.YYY.ZZZ"` 必须定义，合宙 iot 平台 FOTA 依赖三段格式。
