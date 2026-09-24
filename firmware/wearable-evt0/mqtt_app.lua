-- QoS1 transport: offline durable outbox + terminal command acknowledgements.
local cfg,S,Q=_G.CFG,_G.STATE,_G.CFG.mqtt
local base="petpal/v1/"..cfg.device_id
local queue=require("outbox_app")
local mqttc,pending,pending_at
local function pub(topic,tbl,retain)
    if (topic=="/telemetry" or topic=="/state") and queue.depth()>=((cfg.outbox or {}).max_records or 64)-8 then
        S.cache_full=true; log.warn("mqtt","cache reserve for events/acks",topic); return false
    end
    local ok,reason=queue.push(topic,json.encode(tbl),retain)
    if not ok then log.error("mqtt","enqueue failed",topic,reason) end
    return ok
end
local function state(reason)
    return pub("/state",{v=1,device_id=cfg.device_id,ts=_G.PETPAL.clock_valid() and os.time() or 0,
        online=S.mqtt_online,mode=S.mode,fw=cfg.fw,reason=reason,boot_count=S.boot_count,
        cache_depth=queue.depth(),capabilities=_G.PETPAL.capabilities()},true)
end
local function telemetry()
    S.seq=S.seq+1
    local p
    if S.position then p={}; for k,v in pairs(S.position) do p[k]=v end; p.accuracy_m=p.accuracy_m or json.null end
    if p then p.fix_age_s=math.max(0,os.time()-(S.last_fix and S.last_fix.ts or os.time())) end
    local m={v=1,device_id=cfg.device_id,seq=S.seq,boot_count=S.boot_count,
        ts=_G.PETPAL.clock_valid() and os.time() or 0,clock_synced=_G.PETPAL.clock_valid(),mode=S.mode,
        position=p or json.null,last_fix=S.last_fix,motion=S.motion,outputs=S.outputs,
        battery={ready=S.battery.ready,pct=S.battery.pct or json.null,mv=S.battery.mv or json.null,
            charging=S.battery.charging,temp_c=S.battery.temp_c},
        radio={rsrp_dbm=S.radio.rsrp_dbm or json.null,rssi_dbm=S.radio.rssi_dbm or json.null},
        capabilities=_G.PETPAL.capabilities(),fw=cfg.fw}
    return pub("/telemetry",m)
end
sys.subscribe("PETPAL_EVENT",function(e) pub("/event",e) end)
_G.MQTT_PUB=pub   -- 供 LOG_UPLOAD 等按需发布（同样走 outbox / QoS1）
-- 实况帧：不落盘、QoS0、连接断开即丢（画面是易失数据，不进 outbox）
_G.MQTT_RAW_PUB=function(topic,payload) if mqttc and mqttc:ready() then return mqttc:publish(base..topic,payload,0,0) end; return false end
sys.subscribe("PETPAL_STATE_REQUEST",function() state("requested"); telemetry() end)
sys.subscribe("MODE_CHANGED",function() state("mode_change") end)

local function on_event(client,event,data,payload)
    if event=="conack" then
        S.mqtt_online=true; pending=nil
        client:subscribe(base.."/cmd",1); state("connect"); sys.publish("MQTT_READY")
    elseif event=="recv" and data==base.."/cmd" then
        if type(payload)~="string" or #payload>2048 then return end
        local ok,c=pcall(json.decode,payload)
        if not ok then return end
        -- Leave room for acknowledgements/events; terminal result also persists in dedup KV.
        if queue.depth()>((cfg.outbox or {}).max_records or 64)-8 then
            log.error("mqtt","command blocked: ack queue full"); return
        end
        _G.COMMAND.handle(c,function(a) return pub("/ack",a) end)
    elseif event=="sent" then
        if pending and pending.message_id==data then
            if queue.confirm(pending.record) then pending=nil; sys.publish("OUTBOX_READY") end
        end
    elseif event=="disconnect" then
        S.mqtt_online=false; pending=nil; queue.mark_replayed()
    elseif event=="error" then log.warn("mqtt","transport error",data) end
end

-- Collector is independent of connection establishment (otherwise nothing caches offline).
sys.taskInit(function()
    while true do
        telemetry()
        local period=cfg.telemetry_period_s or 30
        if S.mode=="lost" then period=math.min(period,20)
        elseif S.mode=="stationary" or S.mode=="low_power" then period=math.max(period,300) end
        sys.wait(math.max(5,period)*1000)
    end
end)

sys.taskInit(function()
    if not Q or Q.host=="broker.example.com" or Q.pass=="CHANGE_ME" then log.error("mqtt","real broker credentials not configured"); return end
    if Q.tls~=true then log.error("mqtt","TLS required for remote commands"); return end
    local ca=io.readFile(Q.ca_file)
    if not ca or #ca==0 then log.error("mqtt","CA missing"); return end
    while not socket.adapter(socket.dft()) do sys.waitUntil("IP_READY",1000) end
    while not _G.PETPAL.clock_valid() do socket.sntp(); sys.waitUntil("NTP_UPDATE",10000) end
    mqttc=mqtt.create(nil,Q.host,Q.port,{server_cert=ca})
    if not mqttc then log.error("mqtt","create failed"); return end
    mqttc:auth(Q.client_id or cfg.device_id,Q.user,Q.pass,true)
    mqttc:keepalive(Q.keepalive or 120)
    mqttc:will(base.."/state",json.encode({v=1,device_id=cfg.device_id,ts=0,online=false,mode=S.mode,
        fw=cfg.fw,reason="lwt",boot_count=S.boot_count,cache_depth=0}),1,1)
    mqttc:on(on_event); mqttc:autoreconn(true,5000); mqttc:connect()
    while true do
        if pending and mcu.ticks()-pending_at>30000 then
            -- Late PUBACK cannot match a subsequent message; force clean reconnect.
            mqttc:disconnect(); pending=nil; S.mqtt_online=false; queue.mark_replayed(); mqttc:connect()
        end
        if not pending and mqttc:ready() then
            local r=queue.oldest()
            if r then
                local payload=r.payload
                if r.replayed and r.topic=="/telemetry" then
                    local ok,t=pcall(json.decode,payload)
                    if ok and type(t)=="table" then t.replayed=true; payload=json.encode(t) end
                end
                local id=mqttc:publish(base..r.topic,payload,1,r.retain and 1 or 0)
                if type(id)=="number" then pending={record=r,message_id=id}; pending_at=mcu.ticks() end
            end
        end
        sys.waitUntil("OUTBOX_READY",500)
    end
end)
return {telemetry=telemetry,state=state,queue=queue}
