-- Air8201G-BLMQ EXB_AIR8201G_BTB_V1.4, bench bring-up only.
-- No remote credentials, no motor, no high voltage, no low-power USB shutdown.
local c=require("bench_defaults") -- packaging tool copies config.example.lua under this name
c.features={mqtt=false,gnss=true,gsensor=true,power=true,actuator=true,ble=false,lowpower=false}
c.ignore_feature_override=true -- 明确台架包的配置，不删除旧 KV；普通配置仍可 USB 切开关
c.gnss.agps=false
c.actuator.motor_verified=false
c.actuator.motor_gpio=nil
return c
