-- 板1（台账 dev-blmq-01，Air8201G-BLMQ + EXB_AIR8201G_BTB_V1.4）台架配置：摄像头 + GNSS 常开 + 声音 + 灯/马达 + 电池。
-- gsensor 与摄像头共用 I2C1：摄像头打开时 DA267 断电，摄像头空闲关闭后恢复。只用于开发板台架，不是佩戴固件。
local c=require("bench_defaults")
c.device_id="collar-evt-003"
c.fw="evt0.0.22"
c.features={camera=true,power=true,gnss=true,audio=true,actuator=true,mqtt=true,gsensor=true,ble=false,lowpower=false} -- gsensor 与摄像头运行时二选一
c.ignore_feature_override=true
c.camera={board="Air8201G_BTB_V1.4"}
c.gnss.tracking=true -- 常开实时定位
c.gnss.agps=true     -- 2026-09-21 板1 已插卡联网：开机下载合宙星历(HTTP，几 KB，1 小时内不重复下)+基站粗定位(lbsLoc2，向合宙服务器上报基站信息)+SNTP，定位更快；仍需天线见天
-- 马达：带驱动的三线模块，2026-09-21 用户确认接线 GND→GND、VCC→VBAT、IN→GPIO35，上电静止（按高电平触发配置）
c.actuator.motor_gpio=35
c.actuator.motor_on_level=1
c.actuator.motor_verified=true
c.actuator.bench_allow_unknown_temp=true -- 板上无电池 NTC；台架有人值守
c.actuator.bench_allow_charging=true     -- 台架 USB 常插；佩戴固件必须为 false
c.actuator.cooldown_s=5                  -- 2026-09-21 用户要求：台架上 App 连续点击间隔缩短（佩戴固件仍为 30 s）
-- MQTT：公司 Linux 主机上的 Mosquitto，经 Tailscale Funnel 发布（TLS 由 Tailscale 终结，Let's Encrypt 证书 → ca.crt = ISRG Root X1）
-- 密码不在仓库里：打包脚本从主机 ~/petpal-broker/credentials.txt 取，写入包内 config.lua（config.lua 已 gitignore）
c.mqtt.host="jialiang-battle-ax-h610m-a-wifi.tail99e2ea.ts.net"
c.mqtt.port=8443
c.mqtt.tls=true
c.mqtt.ca_file="/luadb/ca.crt"
c.mqtt.user="collar-evt-003"
c.mqtt.keepalive=120
c.telemetry_period_s=60 -- 30 MB 物联网卡：遥测 1 分钟一条约 2 MB/月
return c
