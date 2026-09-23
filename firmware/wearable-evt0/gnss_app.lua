--[[ F4：GNSS 定位；维护 STATE.position / last_fix / gnss
两种工作方式（config.lua 的 gnss.tracking）：
  tracking=true  台架/走失：GNSS 常开（exgnss.DEFAULT），每秒读一次定位；未定位时每 10 s 打印可见卫星数与最大信噪比，方便摆天线
  tracking=false 省电：exgnss.TIMERORSUC 定时或成功即关，按模式周期定位（结果必须在回调内立即读取，回调返回后 GNSS 会被关掉）
实板 V2030 注意：tonumber(nil) 直接报错；libgnss 取不到数据时可能返回 nil 或字段缺失，这里所有读取都做类型判断并用 pcall 包住。
若底层固件无 exgnss 库，改用 reference/gnss/Air8201G/libgnss/gnss.lua（UART2 + GPIO21 手动流程） ]]
local cfg = _G.CFG
local G = cfg.gnss
local S = _G.STATE
local exgnss = require("exgnss")
local M = {}
local running = false
local opened_tick, first_fix_tick, last_fence_tick
local paused = false   -- 摄像头工作期间暂停 GNSS（2026-09-22：两者同时跑时 USB 实况从 7 fps 掉到 <1 fps；用户要求二选一）

exgnss.setup({gnssmode=G.mode, debug=G.nmea_debug, agps_enable=G.agps==true,
    uart=G.uart_id, uartbaud=115200, gnss_volgpio=G.power_gpio, rtc=true})
S.gnss.ready = true
S.gnss.tracking = G.tracking == true
S.gnss.fix = false

local function num(v) return type(v) == "number" and v == v and v or nil end

-- 当前定位（十进制度）；未定位或数据不完整返回 nil。Current official exgnss: mode 0 is DDMM.MMMM, mode 2 is decimal degrees.
local function read_fix()
    local ok, fixed = pcall(exgnss.is_fix)
    if not ok or not fixed then return nil end
    local ok1, rmc = pcall(exgnss.rmc, 2)
    local ok2, gga = pcall(exgnss.gga, 2)
    if not ok1 or type(rmc) ~= "table" then return nil end
    if not ok2 or type(gga) ~= "table" then gga = {} end
    local lat, lng = num(rmc.lat), num(rmc.lng)
    if not lat or not lng or math.abs(lat) > 90 or math.abs(lng) > 180 then return nil end
    if math.abs(lat) < 1e-6 and math.abs(lng) < 1e-6 then return nil end      -- 0,0 不是定位
    local hdop = num(gga.hdop)
    return { source = "gnss", lat = lat, lng = lng,
             accuracy_m = hdop and hdop < 50 and math.max(10, hdop * 10) or nil, accuracy_estimated = true, fix_age_s = 0,
             sats = num(gga.satellites_tracked) or num(gga.sv) or 0,
             speed_kmh = (num(rmc.speed) or 0) * 1.852, alt_m = num(gga.altitude) or num(gga.alt) or 0 }
end

-- 可见卫星统计（未定位时判断天线/环境用）
local function sky()
    local ok, gsv = pcall(exgnss.gsv)
    if not ok or type(gsv) ~= "table" then return 0, 0, 0 end
    local tracked, best = 0, 0
    if type(gsv.sats) == "table" then
        for _, s in pairs(gsv.sats) do
            local snr = type(s) == "table" and num(s.snr) or 0
            if snr > 0 then tracked = tracked + 1 end
            if snr > best then best = snr end
        end
    end
    return num(gsv.total_sats) or 0, tracked, best
end

local function publish(pos)
    local now = mcu.ticks()
    S.position = pos
    S.last_fix = { ts = os.time(), tick = now, lat = pos.lat, lng = pos.lng, source = "gnss" }
    S.gnss.fix, S.gnss.sats = true, pos.sats
    if not first_fix_tick then
        first_fix_tick = now
        S.gnss.ttff_s = (now - (opened_tick or now)) / 1000
        log.info("gnss", "FIX", pos.lat, pos.lng, "sats", pos.sats, "ttff_s", S.gnss.ttff_s)
    end
    -- 围栏要求“两次独立定位”：连续 1 Hz 的点不算独立，20 s 才喂一次
    if not last_fence_tick or now - last_fence_tick >= 20000 then last_fence_tick = now; _G.PETPAL.position(pos) end
end

-- 摄像头打开时调用：关 GNSS（含供电脚），保留最后位置；摄像头空闲关闭后 resume 重新打开（热启动几秒内恢复定位）
function M.pause(why)
    if paused then return end
    paused = true; S.gnss.paused = why or true; S.gnss.fix = false
    if G.tracking == true then pcall(exgnss.close, exgnss.DEFAULT, { tag = "petpal_track" }) end
    log.info("gnss", "paused", why)
end
function M.resume()
    if not paused then return end
    paused = false; S.gnss.paused = nil
    if G.tracking == true then opened_tick = mcu.ticks(); first_fix_tick = nil; exgnss.open(exgnss.DEFAULT, { tag = "petpal_track" }) end
    log.info("gnss", "resumed")
end

function M.status()
    local total, tracked, best = sky()
    S.gnss.sats_in_view, S.gnss.sats_with_signal, S.gnss.snr_max = total, tracked, best
    S.gnss.on_s = opened_tick and math.floor((mcu.ticks() - opened_tick) / 1000) or 0
    return S.gnss
end

-- 同步定位一次，须在 task 内调用；返回 ok, ttff_s
function M.locate(timeout_s)
    if paused then return false, nil end
    if G.tracking == true then return S.gnss.fix, S.gnss.ttff_s end   -- 常开模式下位置本来就是实时的
    if running then return false end
    running = true
    timeout_s = timeout_s or G.timeout_s
    local t0 = mcu.ticks()
    opened_tick, first_fix_tick = t0, nil
    local topic = "GNSS_DONE_" .. tostring(t0)
    local pos
    exgnss.open(exgnss.TIMERORSUC, { tag = "petpal", val = timeout_s, cb = function(tag)
        pos = read_fix()
        sys.publish(topic)
    end })
    local woke = sys.waitUntil(topic, (timeout_s + 5) * 1000)
    if not woke then pcall(exgnss.close, exgnss.TIMERORSUC, { tag = "petpal" }) end
    running = false
    if pos then
        publish(pos)
    else
        S.position = nil; S.gnss.fix = false
        local total, tracked, best = sky()
        log.warn("gnss", "no fix within", timeout_s, "s; sats in view", total, "with signal", tracked, "snr max", best)
        _G.PETPAL.event("gnss_timeout", {timeout_s=timeout_s})
    end
    return pos ~= nil, S.gnss.ttff_s
end

sys.taskInit(function()
    if G.agps then sys.waitUntil("NET_READY", 60000) end
    if G.tracking == true then
        opened_tick = mcu.ticks()
        exgnss.open(exgnss.DEFAULT, { tag = "petpal_track" })
        local n = 0
        while true do
            sys.wait(1000); n = n + 1
            if paused then goto continue end
            local pos = read_fix()
            if pos then
                publish(pos)
            else
                -- 失锁：位置保留但会变旧，App 按 fix_age_s>120 s 判无效；不编造坐标
                if S.gnss.fix then log.warn("gnss", "fix lost") end
                S.gnss.fix = false
            end
            if n % 10 == 0 then
                local g = M.status()
                log.info("gnss", pos and "tracking" or "searching", "on_s", g.on_s, "in_view", g.sats_in_view, "with_signal", g.sats_with_signal, "snr_max", g.snr_max, "used", pos and pos.sats or 0)
            end
            ::continue::
        end
    end
    -- 开机一次；之后按模式周期定位
    M.locate()
    while true do
        local period = (S.mode == "lost") and 20 or (S.mode == "low_power" and 2700 or 300)
        sys.wait(period * 1000)
        if S.mode ~= "stationary" then M.locate() end
    end
end)

sys.subscribe("LOCATE_NOW", function() sys.taskInit(M.locate) end)
_G.GNSS = M
return M
