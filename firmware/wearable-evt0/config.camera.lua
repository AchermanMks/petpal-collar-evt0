-- Dedicated USB camera bring-up. Do not load gsensor: excamera closes shared I2C1.
local c=require("bench_defaults")
c.features={camera=true,power=true,gnss=true,audio=true,mqtt=false,gsensor=false,actuator=false,ble=false,lowpower=false} -- GNSS 走 UART2/GPIO21，不占摄像头的 I2C1
c.gnss.tracking=true -- 台架：常开实时定位
c.gnss.agps=false   -- 无 SIM，不请求 AGPS；冷启动需天线见天
c.camera={board="Air8201G_BTB_V1.4"}
c.ignore_feature_override=true
return c
