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
    return { source = "gnss", lat = lat, lng = lng, hdop = hdop,
             accuracy_m = hdop and hdop < 50 and math.max(10, hdop * 10) or nil, accuracy_estimated = true, fix_age_s = 0,
             sats = num(gga.satellites_tracked) or num(gga.sv) or 0,
             speed_kmh = (num(rmc.speed) or 0) * 1.852, alt_m = num(gga.altitude) or num(gga.alt) or 0 }
end

-- 质量门 + 静止平均（2026-09-23，用户要求）
--   门：卫星 < min_sats 或 HDOP > max_hdop 的定位不上报（保留上一次好定位，标记 gated）
--   平均：连续定位间移动距离都 < still_m 且速度 < still_kmh 视为静止，对最近 avg_n 次取均值；一旦判定移动立即回到原始值，不引入滞后
local F = { min_sats = 6, max_hdop = 2.5, still_m = 8, still_kmh = 2, avg_n = 8, max_jump_m = 300 }
for k, v in pairs(G.filter or {}) do F[k] = v end
local win = {}          -- 最近的原始定位（静止窗口）
local last_raw          -- 上一次通过质量门的原始定位
S.gnss.filter = { gated = 0, averaged = false, window = 0 }

local function haversine(a, b)
    local rad = math.pi / 180
    local x = math.sin((b.lat - a.lat) * rad / 2) ^ 2 + math.cos(a.lat * rad) * math.cos(b.lat * rad) * math.sin((b.lng - a.lng) * rad / 2) ^ 2
    return 6371000 * 2 * math.asin(math.sqrt(math.max(0, math.min(1, x))))
end

function M.filter_reset() win = {}; last_raw = nil; S.gnss.filter.averaged, S.gnss.filter.window = false, 0 end

-- 返回要上报的位置（原始或平均后的副本），或 nil（被质量门拦下）
function M.filter(raw)
    if raw.sats < F.min_sats or (raw.hdop and raw.hdop > F.max_hdop) then
        S.gnss.filter.gated = S.gnss.filter.gated + 1; return nil
    end
    -- 单点大跳变（>max_jump_m 且上一点很近的时间）先按可疑处理：不进窗口，但仍上报原始值让 App 看到
    local moving = raw.speed_kmh >= F.still_kmh
    if last_raw and not moving then
        local d = haversine(last_raw, raw)
        if d > F.still_m then moving = true end
    end
    last_raw = raw
    if moving then win = {}; S.gnss.filter.averaged, S.gnss.filter.window = false, 0; return raw end
    win[#win + 1] = raw
    while #win > F.avg_n do table.remove(win, 1) end
    S.gnss.filter.window = #win
    if #win < 3 then S.gnss.filter.averaged = false; return raw end
    local out = {}; for k, v in pairs(raw) do out[k] = v end
    local lat, lng, alt = 0, 0, 0
    for _, w in ipairs(win) do lat = lat + w.lat; lng = lng + w.lng; alt = alt + (w.alt_m or 0) end
    out.lat, out.lng, out.alt_m = lat / #win, lng / #win, alt / #win
    out.speed_kmh = 0
    -- 平均后的精度估计：原估计 / sqrt(n)，下限 5 m
    if out.accuracy_m then out.accuracy_m = math.max(5, out.accuracy_m / math.sqrt(#win)) end
    out.averaged_n = #win
    S.gnss.filter.averaged = true
    return out
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
    M.filter_reset()   -- 暂停期间可能被移动过，旧窗口作废
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
        local raw = read_fix()
        pos = raw and (M.filter(raw) or raw)   -- 一次性定位：门拦下也按原始值给，总比没有好，但 hdop/sats 随包上报
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
            local raw = read_fix()
            local pos = raw and M.filter(raw)
            if pos then
                publish(pos)
            elseif raw then
                -- 有定位但没过质量门：保留上一次好位置，fix 标记仍为真（接收机是锁定的）
                S.gnss.fix = true; S.gnss.sats = raw.sats
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
