--[[ 远程日志（2026-09-22）：把 log.info/warn/error/debug 的每一行存进内存环形缓冲（RAM，不写 Flash），
  1) LOG_UPLOAD 命令：按需把最近 N 行经 MQTT 发到 petpal/v1/<id>/log（每包 ≤20 行，走 outbox，3 KB 限制）
  2) E 级日志：自动发一次 log_error 事件（带最近 20 行），60 s 内最多一次；同时把这 20 行写到 KV pp_lastlog，
     下次开机（非冷启动）作为 log_prev_boot 事件补发，用于看自发重启前发生了什么。
必须在其他模块 require 之前加载。行内不含 IMEI 等标识：底层日志不经过这里，脚本层本来就打码。 ]]
local M = { CAP = 200, LINE_MAX = 160, SNAP = 20 }
local buf, head, count = {}, 0, 0
local chunk_seq = 0
local last_error_event = -999999
local pending_prev = fskv and fskv.get("pp_lastlog") or nil

-- 最近 n 行（旧→新）
function M.tail(n)
    n = math.min(n or M.SNAP, count)
    local out = {}
    for i = n - 1, 0, -1 do out[#out + 1] = buf[(head - i - 1) % M.CAP + 1] end
    return out
end

-- LuatOS 内置库是只读表（rotable），不能给 log.info 赋值。改为用一个代理表替换全局 log：
-- 我们自己的 info/warn/error/debug 先记缓冲再调原函数，其余字段透传到原库。C 侧/其他库不受影响。
local orig_log = log
local function packargs(...) return { n = select("#", ...), ... } end
local proxy = setmetatable({}, { __index = orig_log })
for _, lv in ipairs({ "debug", "info", "warn", "error" }) do
    local orig, tag = orig_log[lv], lv:sub(1, 1):upper()
    proxy[lv] = function(...)
        local a = packargs(...)
        pcall(function()
            local parts = {}
            for i = 1, a.n do parts[i] = tostring(a[i]) end
            local line = string.format("%d %s %s", mcu.ticks(), tag, table.concat(parts, " "))
            if #line > M.LINE_MAX then line = line:sub(1, M.LINE_MAX) end
            head = head % M.CAP + 1; buf[head] = line
            if count < M.CAP then count = count + 1 end
        end)
        orig(...)
        if lv == "error" and _G.PETPAL and mcu.ticks() - last_error_event > 60000 then
            last_error_event = mcu.ticks()
            local snap = M.tail(M.SNAP)
            pcall(function() if fskv then fskv.set("pp_lastlog", json.encode(snap)) end end)
            pcall(_G.PETPAL.event, "log_error", { lines = snap })
        end
    end
end
_G.log = proxy

-- 上一次开机留下的错误快照（非冷启动时补发一次），由 main.lua 在 PETPAL 就绪后调用
function M.flush_prev_boot(reason)
    if type(pending_prev) ~= "string" or #pending_prev == 0 then return end
    local ok, lines = pcall(json.decode, pending_prev)
    pending_prev = nil
    if fskv then fskv.del("pp_lastlog") end
    if ok and type(lines) == "table" then _G.PETPAL.event("log_prev_boot", { reason = reason, lines = lines }) end
end

-- LOG_UPLOAD：把最近 n 行分包发出。publish(topic_suffix, table) 由 mqtt_app 提供；返回 包数
function M.upload(n, publish)
    n = math.max(1, math.min(M.CAP, math.floor(n or 60)))
    local lines = M.tail(n)
    local packets = 0
    for i = 1, #lines, M.SNAP do
        chunk_seq = chunk_seq + 1
        local part = {}
        for j = i, math.min(i + M.SNAP - 1, #lines) do part[#part + 1] = lines[j] end
        if not publish("/log", { v = 1, device_id = _G.CFG.device_id, chunk = chunk_seq, part = (i - 1) // M.SNAP + 1,
                                  parts = (#lines + M.SNAP - 1) // M.SNAP, uptime_ms = mcu.ticks(), lines = part }) then
            return packets, "enqueue_failed"
        end
        packets = packets + 1
    end
    return packets
end
function M.size() return count end
_G.LOGBUF = M
return M
