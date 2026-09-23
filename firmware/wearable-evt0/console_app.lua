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
local FEATURES = { "mqtt", "gnss", "gsensor", "power", "actuator", "ble", "lowpower", "camera", "audio" }
local WARN = { lowpower = "requires lowpower_bench_verified; USB may stop", actuator = "LED enabled; unverified motor remains disabled" }

local function mask(s)
    s = tostring(s or "")
    if #s <= 6 then return "***" end
    return s:sub(1, 3) .. string.rep("*", #s - 6) .. s:sub(-3)
end

-- USB 满包（512 字节）偶发丢失（2026-09-20 板 2 实测根因）：回复按 480 字节分段写，每段都是短包
local pending = {} -- 二进制窗口发送期间产生的文本回复先排队，发完再补发，避免插进 JPEG 字节流
local function send(s)
    if _G.CAMERA and _G.CAMERA.tx_busy then pending[#pending + 1] = s; return end
    s = s .. "\r\n"
    for i = 1, #s, 480 do uart.write(uart.VUART_0, s:sub(i, i + 479)) end
end

-- camera read：一行文本头 + 原始字节。在 task 里按 480 字节写，uart.write 返回 0 时等待重试（发送缓冲满）
local function send_binary(header, data)
    _G.CAMERA.tx_busy = true
    sys.taskInit(function()
        local p, i, stall = header .. "\r\n" .. data, 1, 0
        while i <= #p and stall < 200 do
            local seg = p:sub(i, i + 479)
            local n = uart.write(uart.VUART_0, seg)
            if type(n) ~= "number" then n = #seg end
            if n > 0 then i = i + n; stall = 0 else stall = stall + 1; sys.wait(5) end
        end
        _G.CAMERA.tx_busy = false
        local q = pending; pending = {}
        for _, s in ipairs(q) do send(s) end
    end)
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
    if line:sub(1,8)=="command " then
        local ok,c=pcall(json.decode,line:sub(9))
        if not ok or type(c)~="table" then return "err invalid command JSON" end
        _G.COMMAND.handle(c,function(a) send("ack "..json.encode(a)); return true end)
        return "ok command processed"
    end
    local args = {}
    for w in line:gmatch("%S+") do args[#args + 1] = w end
    local cmd = args[1]
    if not cmd then return nil end
    if cmd == "camera" then
        if not _G.CAMERA then return "err camera feature off" end
        if args[2]=="capture" then
            local ok,e=_G.CAMERA.capture(args[3],send)
            return ok and "ok camera scheduled" or ("err camera "..tostring(e))
        elseif args[2]=="chunk" then
            local r,e=_G.CAMERA.chunk(args[3],tonumber(args[4] or "")); return r or ("err camera "..tostring(e))
        elseif args[2]=="read" then
            if _G.CAMERA.tx_busy then return "err camera tx_busy" end
            local data,e=_G.CAMERA.slice(args[3],tonumber(args[4] or ""),tonumber(args[5] or ""))
            if not data then return "err camera "..tostring(e) end
            send_binary("jpegbin "..args[3].." "..args[4].." "..#data,data); return nil
        elseif args[2]=="config" then
            local kv={}
            for i=3,#args do local k,v=args[i]:match("^(%w+)=([%w]+)$"); if not k then return "err camera bad_option" end; kv[k]=v end
            local r,e=_G.CAMERA.config(kv); return r and ("ok camera config "..r) or ("err camera "..tostring(e))
        elseif args[2]=="close" then
            local ok,e=_G.CAMERA.release(args[3]); return ok and "ok camera closed" or ("err camera "..tostring(e))
        end
        return "err camera unknown operation"
    elseif cmd == "ping" then
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
    elseif cmd == "sim" then
        -- SIM 诊断：sim → 当前状态；sim 0|1|2 → 切卡槽(2=自动)并进出飞行模式重新搜卡，不用重启/重烧
        local function report() return string.format("simid %s iccid %s status %s csq %s", tostring(mobile.simid and mobile.simid() or "?"),
            mobile.iccid() and mask(mobile.iccid()) or "nil", tostring(mobile.status()), tostring(mobile.csq())) end
        if not args[2] then return "ok sim " .. report() end
        local n = tonumber(args[2] or "")
        if n ~= 0 and n ~= 1 and n ~= 2 then return "err sim slot must be 0, 1 or 2" end
        sys.taskInit(function()
            pcall(mobile.flymode, 0, true); sys.wait(800)
            local ok, e = pcall(mobile.simid, n); sys.wait(300)
            pcall(mobile.flymode, 0, false); sys.wait(9000)
            send((ok and "ok" or "err") .. " sim rescan slot " .. n .. " -> " .. report())
        end)
        return "ok sim rescan scheduled"
    elseif cmd == "capabilities" then
        return "ok " .. json.encode(_G.PETPAL.capabilities())
    elseif cmd == "snapshot" then
        _G.STATE.capabilities=_G.PETPAL.capabilities()
        _G.STATE.clock_synced=_G.PETPAL.clock_valid()
        if _G.GNSS then _G.GNSS.status() end
        if _G.STATE.position then
            -- 用开机毫秒计时算定位年龄：首次定位后 GNSS 会校 RTC，os.time() 会跳变
            local lf=_G.STATE.last_fix
            if lf and lf.tick then _G.STATE.position.fix_age_s=math.max(0,(mcu.ticks()-lf.tick)//1000)
            else _G.STATE.position.fix_age_s=math.max(0,os.time()-(lf and lf.ts or os.time())) end
        end
        return "ok " .. json.encode(_G.STATE, "7f") -- 默认 %.7g 只有 7 位有效数字，经度 114.05xxxx 会丢到 ~10 m；7 位小数≈1 cm
    elseif cmd == "mode" then
        local ok,e=_G.PETPAL.set_mode(args[2],tonumber(args[3] or "") or 7200)
        return ok and "ok mode updated" or ("err "..tostring(e))
    elseif cmd == "led" then
        if not _G.ACT then return "err actuator feature off" end
        local pattern,duration=args[2] or "blink",tonumber(args[3] or "") or 2
        sys.taskInit(function() local ok,e=_G.ACT.led(pattern,duration); send(ok and "ok led done" or "err "..tostring(e)) end)
        return "ok led scheduled"
    elseif cmd == "vibrate" then
        -- 台架直通：vibrate [ms] [次数]；同样受 500 ms×3、30 s 冷却、低电/温度等限制
        if not _G.ACT then return "err actuator feature off" end
        local a={duration_ms=tonumber(args[2] or "") or 200,count=tonumber(args[3] or "") or 1}
        local reason=_G.ACT.check_allowed(); if reason then return "err vibrate "..reason end
        sys.taskInit(function() local ok,why=_G.ACT.vibrate(a); send(ok and ("ok vibrate done"..(why and (" "..why) or "")) or ("err vibrate "..tostring(why))) end)
        return "ok vibrate scheduled"
    elseif cmd == "stop" then
        if _G.ACT then _G.ACT.stop_motor(); _G.ACT.led("off",0) end
        if _G.AUDIO then _G.AUDIO.stop() end
        return "ok outputs off"
    elseif cmd == "audio" then
        -- 台架直通（不经过时钟/去重）：audio test | audio beep <hz> <ms> [vol] | audio tts <文字> [vol 放最后不支持，用默认] | audio file <name> [vol] | audio stop
        if not _G.AUDIO then return "err audio feature is off" end
        if args[2]=="stop" then _G.AUDIO.stop(); return "ok audio stopped" end
        local a={kind=args[2]}
        if args[2]=="beep" then a.freq_hz,a.duration_ms,a.volume=tonumber(args[3] or ""),tonumber(args[4] or ""),tonumber(args[5] or "")
        elseif args[2]=="tts" then a.text=line:match("^%S+%s+%S+%s+(.+)$")
        elseif args[2]=="file" then a.name,a.volume=args[3],tonumber(args[4] or "") end
        local plan,e=_G.AUDIO.plan(a); if not plan then return "err audio "..tostring(e) end
        sys.taskInit(function() local ok,why=_G.AUDIO.play(a); send(ok and ("ok audio done"..(why and (" "..why) or "")) or ("err audio "..tostring(why))) end)
        return "ok audio scheduled"
    elseif cmd == "time" then
        -- 台架对时（docs/16 §4.3）：只在时钟无效时接受，不覆盖 GNSS/网络对过的时间
        local ts=tonumber(args[2] or "")
        if not ts or ts%1~=0 or ts<1700000000 or ts>4102444800 then return "err time invalid" end
        if _G.PETPAL.clock_valid() then return "ok time kept "..os.time() end
        local d=os.date("!*t",ts)
        if not rtc or not rtc.set({year=d.year,mon=d.month,day=d.day,hour=d.hour,min=d.min,sec=d.sec}) then return "err time rtc_unavailable" end
        return "ok time set "..os.time()
    elseif cmd == "logs" then
        if not _G.LOGBUF then return "err logbuf off" end
        local n=tonumber(args[2] or "") or 20
        return "ok " .. json.encode(_G.LOGBUF.tail(n))
    elseif cmd == "gsensor" then
        -- gsensor → 状态；gsensor set fast 0|1 / readreg 0|1 / sample <ms> → 改参数并重启传感器（不重烧，对比 NACK 率）
        if not _G.GSENSOR then return "err gsensor feature is off" end
        if args[2]=="set" then local ok,e=_G.GSENSOR.tune(args[3],args[4]); return ok and ("ok gsensor restarted "..args[3].."="..tostring(args[4])) or ("err gsensor "..tostring(e)) end
        return "ok " .. json.encode(_G.GSENSOR.status())
    elseif cmd == "gnss" then
        if not _G.GNSS then return "err gnss feature is off" end
        return "ok " .. json.encode(_G.GNSS.status())
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
                log.info("console", "cmd", line:match("^%S+"))
                local ok, reply = pcall(handle, #line<=2048 and line or "oversize")
                if not ok then reply = "err " .. tostring(reply) end
                if reply then send(reply) end
            end
        end
        if #buf > 512 then buf = "" end
    end
end

uart.setup(UART_ID, 115200, 8, 1)
uart.on(UART_ID, "receive", on_recv)
log.info("console", "listening on VUART_0; commands: ping get set clear status locate reboot")
return M
