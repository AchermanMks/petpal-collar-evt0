-- Shared command contract. Reserve id durably before any output, no reboot replay.
local M,seen,order={}, {}, {}
local key="pp_cmds"
if fskv then
    local raw=fskv.get(key)
    if type(raw)=="string" then
        local ok,t=pcall(json.decode,raw)
        if ok and type(t)=="table" then for _,a in ipairs(t) do if type(a)=="table" and type(a.id)=="string" then
            if a.status=="accepted" then a.status="rejected"; a.reason="execution_unknown_after_reboot" end
            seen[a.id]=a; order[#order+1]=a
        end end end
    end
end
local function remember(a)
    local next_order={}
    for _,r in ipairs(order) do
        -- Never evict a still-valid id to make room: fail closed if dedup is full.
        if r.id~=a.id and (not r.expires_at or r.expires_at>=os.time()) then next_order[#next_order+1]=r end
    end
    if #next_order>=24 then return false end
    next_order[#next_order+1]=a
    local encoded=json.encode(next_order)
    if #encoded>4095 or not fskv or not fskv.set(key,encoded) then return false end
    order=next_order; seen={}; for _,r in ipairs(order) do seen[r.id]=r end
    return true
end
local function ack(c,status,reason,applied)
    return {id=c.id,device_id=_G.CFG.device_id,ts=_G.PETPAL.clock_valid() and os.time() or 0,
        status=status,reason=reason,applied_args=applied,expires_at=c.expires_at}
end
function M.validate(c)
    if type(c)~="table" or type(c.id)~="string" or #c.id<8 or #c.id>64 then return "invalid_id" end
    if c.device_id and c.device_id~=_G.CFG.device_id then return "wrong_device" end
    if not _G.PETPAL.clock_valid() then return "clock_unsynced" end
    for _,k in ipairs({"issued_at","expires_at"}) do if type(c[k])~="number" or c[k]~=c[k] or c[k]%1~=0 then return "invalid_time" end end
    local now=os.time()
    if c.expires_at<=now then return "expired" end
    if c.issued_at>now+30 or now-c.issued_at>600 or c.expires_at<c.issued_at or c.expires_at-c.issued_at>600 then return "bad_time" end
    if c.args~=nil and type(c.args)~="table" then return "invalid_args" end
    local a=c.args or {}
    if c.type=="VIBRATE" then
        if not _G.ACT then return "unsupported" end
        local out,reason=_G.ACT.clamp_vibrate(a); if not out then return reason end
        return _G.ACT.check_allowed()
    elseif c.type=="LED" then
        if not _G.ACT then return "unsupported" end
        if a.pattern and a.pattern~="off" and a.pattern~="on" and a.pattern~="blink" and a.pattern~="breathe" then return "invalid_pattern" end
        if a.duration_s and (type(a.duration_s)~="number" or a.duration_s~=a.duration_s or math.abs(a.duration_s)==math.huge) then return "invalid_duration" end
    elseif c.type=="BUZZ" then
        if not _G.AUDIO then return "unsupported" end
        local plan,reason=_G.AUDIO.plan(a); if not plan then return reason end
        return _G.AUDIO.check_allowed()
    elseif c.type=="SET_MODE" then
        if a.mode~="routine" and a.mode~="lost" then return "unsupported_mode" end
        local ttl=a.ttl_s or 7200
        if type(ttl)~="number" or ttl~=ttl or ttl%1~=0 or ttl<60 or ttl>7200 then return "invalid_ttl" end
    elseif c.type=="LOCATE_NOW" then if not _G.GNSS then return "unsupported" end
    elseif c.type=="GSENSOR_TUNE" then
        if not _G.GSENSOR then return "unsupported" end
        if type(a.key)~="string" or (a.value~=nil and type(a.value)~="string" and type(a.value)~="number") then return "invalid_args" end
    elseif c.type=="LOG_UPLOAD" then
        if not _G.LOGBUF or not _G.MQTT_PUB then return "unsupported" end
        if a.lines~=nil and (type(a.lines)~="number" or a.lines~=a.lines or a.lines<1 or a.lines>200) then return "invalid_args" end
    elseif c.type=="GET_STATE" or c.type=="STOP" or c.type=="SET_GEOFENCE" then
    else return "unsupported" end
end
function M.handle(c,reply)
    if type(c)~="table" or type(c.id)~="string" or #c.id<8 or #c.id>64 then return false,"invalid_id" end
    if c.device_id and c.device_id~=_G.CFG.device_id then reply(ack(c,"rejected","wrong_device")); return false end
    -- Idempotent emergency OFF must not depend on RTC, battery or flash availability.
    if c.type=="STOP" then
        if _G.ACT then _G.ACT.stop_motor(); _G.ACT.led("off",0) end
        if _G.AUDIO then _G.AUDIO.stop() end
        reply(ack(c,"executed")); return true
    end
    if seen[c.id] then reply(seen[c.id]); return false,"duplicate" end
    local reason=M.validate(c)
    if reason then reply(ack(c,"rejected",reason)); return false,reason end
    local reserved=ack(c,"accepted")
    if not remember(reserved) then reply(ack(c,"rejected","storage_failed")); return false end
    if reply(reserved)==false then return false,"ack_not_queued" end
    sys.taskInit(function()
        local ok,result,why,applied=pcall(function()
            local a=c.args or {}
            if c.type=="VIBRATE" then return _G.ACT.vibrate(a)
            elseif c.type=="LED" then return _G.ACT.led(a.pattern,a.duration_s)
            elseif c.type=="BUZZ" then return _G.AUDIO.play(a)
            elseif c.type=="STOP" then if _G.ACT then _G.ACT.stop_motor(); _G.ACT.led("off",0) end; return true
            elseif c.type=="SET_MODE" then return _G.PETPAL.set_mode(a.mode,a.ttl_s)
            elseif c.type=="SET_GEOFENCE" then return _G.PETPAL.set_fence(a)
            elseif c.type=="LOCATE_NOW" then local fix=_G.GNSS.locate(60); return fix,fix and nil or "no_fix"
            elseif c.type=="GET_STATE" then sys.publish("PETPAL_STATE_REQUEST"); return true
            elseif c.type=="GSENSOR_TUNE" then local ok,why=_G.GSENSOR.tune(a.key,a.value~=nil and tostring(a.value) or nil); return ok,why,{key=a.key,value=a.value}
            elseif c.type=="LOG_UPLOAD" then local n,why=_G.LOGBUF.upload(a.lines or 60,_G.MQTT_PUB); return n>0,why,{packets=n} end
        end)
        if not ok then result,why=false,"execution_failed" end
        local terminal=ack(c,result and "executed" or "rejected",why,applied)
        if not remember(terminal) then terminal.reason="result_storage_failed" end
        reply(terminal)
    end)
    return true
end
return M
