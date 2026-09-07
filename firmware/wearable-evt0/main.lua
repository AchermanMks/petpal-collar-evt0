--[[
PetPal wearable-evt0 板级调试固件（LuatOS / Air8201G = Air780EGH）
按 config.lua 的 features 开关逐项加载模块；每个模块独立，可单独验证。
参考：firmware/reference/luatos-air8201（合宙官方 demo 与出厂工程）
]]
PROJECT = "petpal_evt0"
VERSION = "001.000.001"   -- 合宙 FOTA 要求 XXX.YYY.ZZZ；业务版本见 config.fw

local sys = require("sys")
require("sysplus")
local cfg = require("config")
_G.CFG = cfg

log.info("main", PROJECT, VERSION, cfg.device_id, cfg.fw)
local r1, r2, r3 = pm.lastReson()
log.info("main", "lastReson", r1, r2, r3, (r1 == 0 and r2 == 0 and r3 == 0) and "cold boot" or "reboot")
if hmeta then log.info("main", "hmeta", hmeta.model and hmeta.model() or "?", hmeta.hwver and hmeta.hwver() or "?") end
log.info("main", "features", json.encode(cfg.features))

-- errDump：脚本语法错误/自定义错误本地记录并上传（调试阶段建议开）
if errDump then errDump.config(true, 600) end

-- 看门狗：主任务卡死 9 s 复位
if wdt then wdt.init(9000); sys.timerLoopStart(wdt.feed, 3000) end

-- 内存监控
sys.timerLoopStart(function()
    log.info("mem", "lua", rtos.meminfo(), "sys", rtos.meminfo("sys"))
end, 60000)

-- USB 日志：BLMQ/整机板 USB 经 BTB 引出，默认打开方便 Mac 抓日志
if pm and pm.USB then pm.power(pm.USB, 1) end

-- 状态总线（各模块读写，telemetry 组包）
_G.STATE = {
    mode = "routine", seq = 0, boot_ts = 0,
    battery = { pct = 100, mv = 4000, charging = false },
    position = nil, last_fix = nil, gnss = { sats = 0, ttff_s = nil },
    motion = { state = "still", steps = 0 },
    radio = { rsrp_dbm = -100, rssi_dbm = -70 },
    online = false,
}

require("net_app")                                   -- F2 必开
if cfg.features.power    then require("power_app")    end -- F6
if cfg.features.gsensor  then require("gsensor_app")  end -- F5
if cfg.features.gnss     then require("gnss_app")     end -- F4
if cfg.features.actuator then require("actuator_app") end -- F7
if cfg.features.ble      then require("ble_app")      end -- F10
if cfg.features.mqtt     then require("mqtt_app")     end -- F3/F8/F9

if cfg.features.lowpower then
    sys.taskInit(function()
        sys.wait(30000)                                -- 给日志和首次上报留时间
        log.info("main", "enter low power resident mode")
        pm.power(pm.WORK_MODE, 1)
    end)
end

sys.run()
-- sys.run() 之后不要加任何语句
