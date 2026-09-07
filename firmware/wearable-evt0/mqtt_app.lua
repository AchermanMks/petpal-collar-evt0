--[[ F3/F8/F9：MQTT/TLS 单向校验、telemetry/state/ack 发布、cmd 处理（含去重、过期、硬上限）
Topic 与 payload 见 schemas/。参考 reference/mqtt/mqtts_ca ]]
local cfg = _G.CFG
local Q = cfg.mqtt
local base = "petpal/v1/" .. cfg.device_id
local mqttc
local seen = {}          -- command id 去重（内存，重启清空）

local function now() return os.time() end
local function pub(topic, tbl, retain)
    if not mqttc or not mqttc:ready() then log.warn("mqtt", "not ready, drop", topic); return false end
    local r = mqttc:publish(base .. topic, json.encode(tbl), 1, retain and 1 or 0)
    return r ~= nil and r ~= false
end

local function publish_state(reason, online)
    return pub("/state", { v = 1, device_id = cfg.device_id, ts = now(), online = online ~= false,
                           mode = _G.STATE.mode, fw = cfg.fw, reason = reason,
                           boot_count = 0, cache_depth = 0 }, true)
end

local function publish_telemetry()
    local S = _G.STATE
    S.seq = S.seq + 1
    local m = { v = 1, device_id = cfg.device_id, seq = S.seq, ts = now(), mode = S.mode,
                position = S.position or json.null,
                motion = { state = S.motion.state, steps = S.motion.steps },
                battery = { pct = S.battery.pct, mv = S.battery.mv, charging = S.battery.charging },
                radio = { rsrp_dbm = S.radio.rsrp_dbm, rssi_dbm = S.radio.rssi_dbm }, fw = cfg.fw }
    if not S.position and S.last_fix then m.last_fix = S.last_fix end
    if S.position then S.position.fix_age_s = math.max(0, now() - (S.last_fix and S.last_fix.ts or now())) end
    local ok = pub("/telemetry", m)
    log.info("mqtt", "telemetry seq", S.seq, ok and "sent" or "DROPPED")
end

local function ack(id, status, reason, applied)
    local a = { id = id, device_id = cfg.device_id, ts = now(), status = status }
    if reason then a.reason = reason end
    if applied then a.applied_args = applied end
    pub("/ack", a)
    log.info("mqtt", "ack", id, status, reason or "")
end

local function handle_cmd(payload)
    local ok, c = pcall(json.decode, payload)
    if not ok or type(c) ~= "table" or not c.id then log.warn("mqtt", "bad cmd", payload); return end
    local t = now()
    if c.device_id and c.device_id ~= cfg.device_id then return ack(c.id, "rejected", "wrong_device") end
    if seen[c.id] then return ack(c.id, "rejected", "duplicate") end
    seen[c.id] = t
    if c.expires_at and c.expires_at < t then return ack(c.id, "rejected", "expired") end
    if c.issued_at and math.abs(t - c.issued_at) > 600 then return ack(c.id, "rejected", "bad_time") end
    ack(c.id, "accepted")
    sys.taskInit(function()
        local ACT = _G.ACT
        if c.type == "VIBRATE" then
            if not ACT then return ack(c.id, "rejected", "unsupported") end
            local reason = ACT.check_allowed(t)
            if reason then return ack(c.id, "rejected", reason) end
            local args, clamped = ACT.clamp_vibrate(c.args)
            ACT.vibrate(args)
            return ack(c.id, "executed", clamped and "limit_clamped" or nil, args)
        elseif c.type == "LED" then
            if not ACT then return ack(c.id, "rejected", "unsupported") end
            ACT.led((c.args or {}).pattern or "blink", (c.args or {}).duration_s or 5)
            return ack(c.id, "executed")
        elseif c.type == "SET_MODE" then
            local m = c.args and c.args.mode
            if m == "routine" or m == "lost" then _G.STATE.mode = m; publish_state("mode_change"); return ack(c.id, "executed") end
            return ack(c.id, "rejected", "unsupported")
        elseif c.type == "LOCATE_NOW" then
            if _G.GNSS then _G.GNSS.locate(60) end
            publish_telemetry(); return ack(c.id, "executed")
        elseif c.type == "GET_STATE" then
            publish_state("periodic"); return ack(c.id, "executed")
        end
        return ack(c.id, "rejected", "unsupported")
    end)
end

local function on_event(client, event, data, payload, metas)
    if event == "conack" then
        log.info("mqtt", "connected")
        client:subscribe(base .. "/cmd", 1)
        publish_state("boot")
        sys.publish("MQTT_READY")
    elseif event == "recv" then
        handle_cmd(payload)
    elseif event == "sent" then
        -- data = message id
    elseif event == "disconnect" then
        log.warn("mqtt", "disconnected")
    elseif event == "error" then
        log.error("mqtt", "error", data, payload)
    end
end

sys.taskInit(function()
    while not socket.adapter(socket.dft()) do sys.waitUntil("IP_READY", 1000) end
    -- TLS 校验需要正确时间：先 sntp，超时则用基站时间
    socket.sntp(); sys.waitUntil("NTP_UPDATE", 8000)
    log.info("mqtt", "time", os.date("%Y-%m-%d %H:%M:%S"))
    local opts
    if Q.tls then
        local ca = io.readFile(Q.ca_file)
        if not ca then log.error("mqtt", "CA file missing", Q.ca_file); return end
        opts = { server_cert = ca }
    end
    mqttc = mqtt.create(nil, Q.host, Q.port, opts)
    if not mqttc then log.error("mqtt", "create failed"); return end
    mqttc:auth(Q.client_id or cfg.device_id, Q.user, Q.pass, true)
    mqttc:keepalive(Q.keepalive)
    mqttc:will(base .. "/state", json.encode({ v = 1, device_id = cfg.device_id, ts = 0, online = false, reason = "lwt" }), 1, 1)
    mqttc:on(on_event)
    mqttc:autoreconn(true, 5000)
    local r = mqttc:connect()
    log.info("mqtt", "connect()", r, Q.host, Q.port, Q.tls and "tls" or "plain")

    sys.waitUntil("MQTT_READY", 60000)
    while true do
        publish_telemetry()
        local S = _G.STATE
        local period = cfg.telemetry_period_s
        if S.mode == "lost" then period = math.min(period, 20)
        elseif S.mode == "stationary" or S.mode == "low_power" then period = math.max(period, 3600) end
        sys.wait(period * 1000)
    end
end)

sys.subscribe("GSENSOR_MOTION", function() if _G.STATE.mode == "stationary" then _G.STATE.mode = "routine" end end)
