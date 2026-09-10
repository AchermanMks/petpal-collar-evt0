--[[ F0 调试命令台：USB 用户虚拟串口（uart.VUART_0）接收行命令，功能开关写入 KV，重启后生效。
目的：不用回 Windows 重烧就能在 Mac 上切换 features（tools/usb_cmd.py）。
协议：一行一条命令，\n 结尾，回复以 "ok " / "err " 开头。
  ping                      -> pong <PROJECT> <VERSION>
  get                       -> 当前生效 features 与 KV 覆盖
  set <feature> 0|1         -> 写 KV 覆盖（reboot 后生效）
  clear                     -> 删除 KV 覆盖，回到 config.lua
  status                    -> 网络/SIM/内存
  locate                    -> 触发一次 GNSS 定位（gnss 已开时）
  reboot                    -> 软复位
KV 读取与合并在 main.lua（必须在各模块 require 之前完成）。 ]]
local M = {}
local KEY = "feat_override"
local FEATURES = { "mqtt", "gnss", "gsensor", "power", "actuator", "ble", "lowpower" }
local WARN = { lowpower = "USB will be switched off in low power mode; logs stop", actuator = "motor/LED output; handoff rule says keep off unless justified" }

local function mask(s)
    s = tostring(s or "")
    if #s <= 6 then return "***" end
    return s:sub(1, 3) .. string.rep("*", #s - 6) .. s:sub(-3)
end

function M.load_override()
    if not fskv then return nil, "no fskv" end
    local raw = fskv.get(KEY)
    if type(raw) ~= "string" or #raw == 0 then return nil end
    local t = json.decode(raw)
    if type(t) ~= "table" then return nil, "bad json" end
    return t
end

local function save_override(t)
    if not fskv then return false, "no fskv" end
    if next(t) == nil then fskv.del(KEY); return true end
    return fskv.set(KEY, json.encode(t))
end

local function is_feature(name)
    for _, f in ipairs(FEATURES) do if f == name then return true end end
    return false
end

local function handle(line)
    local cfg = _G.CFG
    local args = {}
    for w in line:gmatch("%S+") do args[#args + 1] = w end
    local cmd = args[1]
    if not cmd then return nil end
    if cmd == "ping" then
        return "pong " .. tostring(PROJECT) .. " " .. tostring(VERSION)
    elseif cmd == "get" then
        local ov = M.load_override() or {}
        return "ok features " .. json.encode(cfg.features) .. " override " .. json.encode(ov)
    elseif cmd == "set" then
        local name, val = args[2], args[3]
        if not is_feature(name or "") then return "err unknown feature " .. tostring(name) .. " (" .. table.concat(FEATURES, ",") .. ")" end
        if val ~= "0" and val ~= "1" then return "err value must be 0 or 1" end
        local ov = M.load_override() or {}
        ov[name] = (val == "1")
        local ok, e = save_override(ov)
        if not ok then return "err kv write failed " .. tostring(e) end
        local r = "ok " .. name .. "=" .. val .. " saved, send reboot to apply"
        if val == "1" and WARN[name] then r = r .. " ; WARNING " .. WARN[name] end
        return r
    elseif cmd == "clear" then
        local ok, e = save_override({})
        return ok and "ok override cleared, send reboot to apply" or ("err " .. tostring(e))
    elseif cmd == "status" then
        local st = mobile and mobile.status() or -1
        local simid = mobile and mobile.simid and mobile.simid() or -1
        local iccid = mobile and mobile.iccid and mobile.iccid() or nil
        local csq = mobile and mobile.csq and mobile.csq() or -1
        return string.format("ok status %s simid %s iccid %s csq %s rsrp %s online %s mem %s",
            tostring(st), tostring(simid), iccid and mask(iccid) or "nil", tostring(csq),
            tostring(mobile and mobile.rsrp and mobile.rsrp() or -1), tostring(_G.STATE.online), tostring(rtos.meminfo()))
    elseif cmd == "locate" then
        if not cfg.features.gnss then return "err gnss feature is off" end
        sys.publish("LOCATE_NOW"); return "ok locate requested"
    elseif cmd == "reboot" then
        sys.timerStart(rtos.reboot, 500); return "ok rebooting"
    else
        return "err unknown command " .. cmd
    end
end

local UART_ID = uart and uart.VUART_0
if not UART_ID then
    log.warn("console", "uart.VUART_0 not available in this firmware; console disabled")
    return M
end

local buf = ""
local function on_recv()
    while true do
        local s = uart.read(UART_ID, 1024)
        if not s or #s == 0 then break end
        buf = buf .. s
        while true do
            local i = buf:find("\n", 1, true)
            if not i then break end
            local line = buf:sub(1, i - 1):gsub("\r", "")
            buf = buf:sub(i + 1)
            if #line > 0 then
                log.info("console", "cmd", line)
                local ok, reply = pcall(handle, line)
                if not ok then reply = "err " .. tostring(reply) end
                if reply then uart.write(UART_ID, reply .. "\r\n") end
            end
        end
        if #buf > 512 then buf = "" end
    end
end

uart.setup(UART_ID, 115200, 8, 1)
uart.on(UART_ID, "receive", on_recv)
log.info("console", "listening on VUART_0; commands: ping get set clear status locate reboot")
return M
