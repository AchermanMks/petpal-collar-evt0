-- 执行器安全上限：固件本地、不可被后端参数绕过（方案 3.4）
local M = {}
M.MAX_PULSE_MS = 500
M.MAX_COUNT = 3
M.COOLDOWN_S = 30
local last_exec = 0

-- 返回 clamped_args, clamped(bool)
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

-- 返回 reason 或 nil
function M.check_allowed(state, now)
    if state.mode == "charging" then return "charging" end
    if state.mode == "low_power" or (state.battery_pct or 100) < 15 then return "low_battery" end
    if (state.temp_c or 25) > 45 then return "over_temp" end
    if now - last_exec < M.COOLDOWN_S then return "cooldown" end
    return nil
end

function M.mark_executed(now) last_exec = now end

return M
