--[[ F4：GNSS 定位（exgnss 定时或成功即关模式）；维护 STATE.position / last_fix / gnss
关键：定位结果必须在回调内立即读取，回调返回后 exgnss 会关掉 GNSS。
若底层固件无 exgnss 库，改用 reference/gnss/Air8201G/libgnss/gnss.lua（UART2 + GPIO21 手动流程） ]]
local cfg = _G.CFG
local G = cfg.gnss
local exgnss = require("exgnss")
local M = {}
local running = false

exgnss.setup({ gnssmode = G.mode, debug = G.nmea_debug })

-- 同步定位一次，须在 task 内调用；返回 ok, ttff_s
function M.locate(timeout_s)
    if running then return false end
    running = true
    timeout_s = timeout_s or G.timeout_s
    local t0 = mcu.ticks()
    local topic = "GNSS_DONE_" .. tostring(t0)
    local snap = { ok = false }
    exgnss.open(exgnss.TIMERORSUC, { tag = "petpal", val = timeout_s, cb = function(tag)
        if exgnss.is_fix() then
            local rmc, gga = exgnss.rmc(0), exgnss.gga(0)
            if rmc and rmc.lat and rmc.lng and (math.abs(rmc.lat) > 1e-6 or math.abs(rmc.lng) > 1e-6) then
                snap = { ok = true, lat = rmc.lat, lng = rmc.lng, speed = rmc.speed or 0,
                         sats = gga and gga.sv or 0, alt = gga and gga.alt or 0, ttff = (mcu.ticks() - t0) / 1000 }
            end
        end
        sys.publish(topic)
    end })
    local woke = sys.waitUntil(topic, (timeout_s + 5) * 1000)
    if not woke then pcall(exgnss.close, exgnss.TIMERORSUC, { tag = "petpal" }) end
    running = false
    if snap.ok then
        _G.STATE.position = { source = "gnss", lat = snap.lat, lng = snap.lng, accuracy_m = 10.0, fix_age_s = 0, sats = snap.sats }
        _G.STATE.last_fix = { ts = os.time(), lat = snap.lat, lng = snap.lng, source = "gnss" }
        _G.STATE.gnss.sats, _G.STATE.gnss.ttff_s = snap.sats, snap.ttff
        log.info("gnss", "FIX", snap.lat, snap.lng, "sats", snap.sats, "ttff_s", snap.ttff)
    else
        _G.STATE.position = nil
        log.warn("gnss", "no fix within", timeout_s, "s")
    end
    return snap.ok, snap.ttff
end

-- 开机一次；之后按模式周期定位
sys.taskInit(function()
    sys.waitUntil("NET_READY", 60000)   -- AGPS 需要网络
    M.locate()
    while true do
        local period = (_G.STATE.mode == "lost") and 20 or (_G.STATE.mode == "low_power" and 2700 or 300)
        sys.wait(period * 1000)
        if _G.STATE.mode ~= "stationary" then M.locate() end
    end
end)

sys.subscribe("LOCATE_NOW", function() sys.taskInit(M.locate) end)
_G.GNSS = M
return M
