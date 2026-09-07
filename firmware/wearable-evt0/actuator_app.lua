--[[ F7：LED 与马达 GPIO；上电默认全部关闭；提供带硬上限的执行接口 ]]
local cfg = _G.CFG
local A = cfg.actuator
local M = { MAX_PULSE_MS = 500, MAX_COUNT = 3, COOLDOWN_S = 30 }
local last_exec = 0

local led_off = (A.led_on_level == 1) and 0 or 1
local motor_off = (A.motor_on_level == 1) and 0 or 1
gpio.setup(A.led_gpio, led_off)
gpio.setup(A.motor_gpio, motor_off)
log.info("actuator", "led GPIO", A.led_gpio, "motor GPIO", A.motor_gpio, "both OFF at boot")

function M.clamp_vibrate(args)
    args = args or {}
    local out, clamped = {}, false
    out.duration_ms = tonumber(args.duration_ms) or 200
    out.count = tonumber(args.count) or 1
    if out.duration_ms > M.MAX_PULSE_MS then out.duration_ms = M.MAX_PULSE_MS; clamped = true end
    if out.count > M.MAX_COUNT then out.count = M.MAX_COUNT; clamped = true end
    if out.duration_ms < 50 then out.duration_ms = 50 end
    if out.count < 1 then out.count = 1 end
    return out, clamped
end

-- 返回拒绝原因或 nil
function M.check_allowed(now)
    local S = _G.STATE
    if S.mode == "charging" or S.battery.charging then return "charging" end
    if S.mode == "low_power" or S.battery.pct < cfg.low_battery_pct then return "low_battery" end
    if (S.battery.temp_c or 25) > 45 then return "over_temp" end
    if now - last_exec < M.COOLDOWN_S then return "cooldown" end
    return nil
end

-- 须在 task 内调用
function M.vibrate(args)
    last_exec = os.time()
    for i = 1, args.count do
        gpio.set(A.motor_gpio, A.motor_on_level); sys.wait(args.duration_ms)
        gpio.set(A.motor_gpio, motor_off)
        if i < args.count then sys.wait(300) end
    end
    log.info("actuator", "vibrate done", args.count, "x", args.duration_ms, "ms")
end

function M.led(pattern, duration_s)
    duration_s = math.min(tonumber(duration_s) or 5, 300)
    if pattern == "off" then gpio.set(A.led_gpio, led_off); return end
    local on_ms, off_ms = 200, 800
    if pattern == "breathe" then on_ms, off_ms = 500, 500 end
    local t_end = mcu.ticks() + duration_s * 1000
    while mcu.ticks() < t_end do
        gpio.set(A.led_gpio, A.led_on_level); sys.wait(on_ms)
        gpio.set(A.led_gpio, led_off); sys.wait(off_ms)
    end
    log.info("actuator", "led done", pattern, duration_s, "s")
end

-- 上电自检：LED 闪 2 下，马达不动（马达只能由命令触发）
sys.taskInit(function() sys.wait(2000); M.led("blink", 2) end)

_G.ACT = M
return M
