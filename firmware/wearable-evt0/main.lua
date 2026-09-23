--[[
PetPal wearable-evt0 板级调试固件（LuatOS / Air8201G = Air780EGH）
按 config.lua 的 features 开关逐项加载模块；每个模块独立，可单独验证。
参考：firmware/reference/luatos-air8201（合宙官方 demo 与出厂工程）
]]
PROJECT = "petpal_evt0"
VERSION = "001.000.003"   -- camera on-demand JPEG transport

local sys = require("sys")
_G.sys = sys
require("sysplus")
local cfg = require("config")
_G.CFG = cfg

log.info("main", PROJECT, VERSION, cfg.device_id, cfg.fw)
local r1, r2, r3 = pm.lastReson()
log.info("main", "lastReson", r1, r2, r3, (r1 == 0 and r2 == 0 and r3 == 0) and "cold boot" or "reboot")
if hmeta then log.info("main", "hmeta", hmeta.model and hmeta.model() or "?", hmeta.hwver and hmeta.hwver() or "?") end

-- KV 功能开关覆盖：由 console_app（USB 命令台）写入，优先于 config.lua；便于 Mac 上切功能不重烧
if fskv then fskv.init() end
local logbuf = require("logbuf_app")             -- 远程日志环形缓冲：必须最先加载才能包住后面模块的 log
local console = require("console_app")
local override = console.load_override()
if override and cfg.ignore_feature_override ~= true then
    for k, v in pairs(override) do
        if cfg.features[k] ~= nil and type(v)=="boolean" then cfg.features[k] = v end
    end
    log.info("main", "features override from kv", json.encode(override))
end
log.info("main", "features", json.encode(cfg.features))

-- errDump：脚本语法错误/自定义错误本地记录并上传（调试阶段建议开）
if errDump then errDump.config(cfg.diagnostics_upload == true, 600) end

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
    device_id = cfg.device_id, fw = cfg.fw,
    mode = "routine", seq = 0, boot_ts = 0,
    battery = { ready = false, pct = nil, mv = nil, charging = false },
    position = nil, last_fix = nil, gnss = { ready = false, sats = 0, ttff_s = nil },
    motion = { ready = false, state = "still", steps = 0 },
    radio = { rsrp_dbm = nil, rssi_dbm = nil },
    online = false, mqtt_online = false, boot_count = 0,
}

require("runtime_app")
_G.COMMAND = require("command_app")

require("net_app")                                   -- F2 必开
if cfg.features.power    then require("power_app")    end -- F6
if cfg.features.gsensor  then require("gsensor_app")  end -- F5
if cfg.features.gnss     then require("gnss_app")     end -- F4
if cfg.features.actuator then require("actuator_app") end -- F7
if cfg.features.camera   then require("camera_app")   end
if cfg.features.audio    then require("audio_app")    end
if cfg.features.ble      then require("ble_app")      end -- F10
if cfg.features.mqtt     then require("mqtt_app")     end -- F3/F8/F9

if cfg.features.lowpower and cfg.lowpower_bench_verified == true then
    sys.taskInit(function()
        sys.wait(30000)                                -- 给日志和首次上报留时间
        log.info("main", "enter low power resident mode")
        pm.power(pm.WORK_MODE, 1)
    end)
end

sys.timerStart(function() _G.PETPAL.event("reboot", {version=VERSION}); log.info("petpal", "capabilities", json.encode(_G.PETPAL.capabilities())); logbuf.flush_prev_boot(string.format("%s %s %s", tostring(r1), tostring(r2), tostring(r3))) end, 3000)

sys.run()
-- sys.run() 之后不要加任何语句
