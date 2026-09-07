-- PetPal wearable-evt0 bring-up 骨架（LuatOS, Air8201G）
-- 覆盖 TP-01 步骤 4～9 与 TP-04 的最小闭环：注册网络、MQTT/TLS、GNSS、遥测、命令/ACK、安全上限。
-- 未实现（正式固件负责）：G-sensor 唤醒状态机、离线 ring buffer 持久化、FOTA、看门狗策略。
PROJECT = "petpal_evt0"
VERSION = "0.0.1"

local sys = require("sys")
require("sysplus")
local cfg = require("config")
local safety = require("safety")
local json = json or require("json")

local base = "petpal/v1/" .. cfg.device_id
local state = { seq = 0, mode = "routine", battery_pct = 100, mv = 4000, charging = false,
                last_fix = nil, seen_cmd = {}, boot_ts = 0 }

-- ---------- 辅助 ----------
local function now() return os.time() end

local function battery_read()
    -- TODO: 替换为 Air8201G 实际 ADC/充电管理读取
    local mv = adc and adc.get and adc.get(adc.CH_VBAT) or 4000
    local pct = math.floor(math.max(0, math.min(100, (mv - 3300) / 9)))
    state.mv, state.battery_pct = mv, pct
    state.charging = false -- TODO: 充电状态 GPIO/寄存器
    return pct, mv
end

local function radio_read()
    local rsrp = mobile and mobile.rsrp and mobile.rsrp() or -100
    local rssi = mobile and mobile.rssi and mobile.rssi() or -70
    return rsrp, rssi
end

local function position_read()
    -- 返回 position 表或 nil；不得返回 0,0
    if libgnss and libgnss.isFix and libgnss.isFix() then
        local rmc = libgnss.getRmc(2)
        if rmc and rmc.lat and rmc.lng and (math.abs(rmc.lat) > 1e-6 or math.abs(rmc.lng) > 1e-6) then
            local p = { source = "gnss", lat = rmc.lat, lng = rmc.lng, accuracy_m = 10.0, fix_age_s = 0 }
            state.last_fix = { ts = now(), lat = p.lat, lng = p.lng, source = "gnss" }
            return p
        end
    end
    return nil
end

-- ---------- MQTT ----------
local mqttc
local function publish(topic, tbl, retain)
    if not mqttc or not mqttc:ready() then return false end
    return mqttc:publish(base .. topic, json.encode(tbl), 1, retain and 1 or 0)
end

local function publish_state(reason, online)
    publish("/state", { v = 1, device_id = cfg.device_id, ts = now(), online = online ~= false,
                        mode = state.mode, fw = cfg.fw, reason = reason }, true)
end

local function publish_telemetry()
    state.seq = state.seq + 1
    local pct, mv = battery_read()
    local rsrp, rssi = radio_read()
    local pos = position_read()
    local m = { v = 1, device_id = cfg.device_id, seq = state.seq, ts = now(), mode = state.mode,
                position = pos or json.null,
                motion = { state = "moving" },
                battery = { pct = pct, mv = mv, charging = state.charging },
                radio = { rsrp_dbm = rsrp, rssi_dbm = rssi }, fw = cfg.fw }
    if not pos and state.last_fix then m.last_fix = state.last_fix end
    if not publish("/telemetry", m) then
        -- TODO: 写入离线 ring buffer（cache_max），恢复后带 replayed=true 补传
        log.warn("telemetry", "offline, seq", state.seq)
    end
end

local function ack(id, status, reason, applied)
    local m = { id = id, device_id = cfg.device_id, ts = now(), status = status }
    if reason then m.reason = reason end
    if applied then m.applied_args = applied end
    publish("/ack", m)
end

local function vibrate(args)
    -- TODO: 载板 MOSFET GPIO；上电默认关闭
    for i = 1, args.count do
        log.info("vibrate", "pulse", i, args.duration_ms)
        -- gpio.set(PIN_MOTOR, 1); sys.wait(args.duration_ms); gpio.set(PIN_MOTOR, 0)
        sys.wait(args.duration_ms)
        if i < args.count then sys.wait(300) end
    end
end

local function handle_cmd(payload)
    local ok, c = pcall(json.decode, payload)
    if not ok or type(c) ~= "table" or not c.id then return end
    local t = now()
    if c.device_id and c.device_id ~= cfg.device_id then return ack(c.id, "rejected", "wrong_device") end
    if state.seen_cmd[c.id] then return ack(c.id, "rejected", "duplicate") end
    state.seen_cmd[c.id] = t
    if c.expires_at and c.expires_at < t then return ack(c.id, "rejected", "expired") end
    if c.issued_at and math.abs(t - c.issued_at) > 600 then return ack(c.id, "rejected", "bad_time") end
    ack(c.id, "accepted")

    if c.type == "VIBRATE" then
        local reason = safety.check_allowed(state, t)
        if reason then return ack(c.id, "rejected", reason) end
        local args, clamped = safety.clamp_vibrate(c.args)
        safety.mark_executed(t)
        vibrate(args)
        return ack(c.id, "executed", clamped and "limit_clamped" or nil, args)
    elseif c.type == "SET_MODE" then
        local m = c.args and c.args.mode
        if m == "routine" or m == "lost" then state.mode = m; publish_state("mode_change"); return ack(c.id, "executed") end
        return ack(c.id, "rejected", "unsupported")
    elseif c.type == "LOCATE_NOW" then
        publish_telemetry(); return ack(c.id, "executed")
    elseif c.type == "LED" then
        -- TODO: 低电流 LED，不常亮
        return ack(c.id, "executed")
    elseif c.type == "GET_STATE" then
        publish_state("periodic"); return ack(c.id, "executed")
    end
    return ack(c.id, "rejected", "unsupported")
end

-- ---------- 主任务 ----------
sys.taskInit(function()
    state.boot_ts = now()
    log.info("boot", cfg.device_id, cfg.fw)
    -- 网络注册
    if mobile then
        while not mobile.status or mobile.status() ~= 1 do sys.wait(1000) end
        log.info("net", "registered", "imei redacted in logs")
    end
    -- GNSS 开启（Air8201G 内置 GNSS；实际串口/电源引脚以硬件资料为准）
    if libgnss then
        -- uart.setup(2, 115200); libgnss.bind(2)
        log.info("gnss", "enabled")
    end
    -- MQTT
    mqttc = mqtt.create(nil, cfg.mqtt.host, cfg.mqtt.port, cfg.mqtt.tls and { ca_file = cfg.mqtt.ca_file } or nil)
    mqttc:auth(cfg.device_id, cfg.mqtt.user, cfg.mqtt.pass)
    mqttc:keepalive(cfg.mqtt.keepalive)
    mqttc:will(base .. "/state", json.encode({ v = 1, device_id = cfg.device_id, ts = 0, online = false, reason = "lwt" }), 1, 1)
    mqttc:on(function(client, event, data, payload)
        if event == "conack" then
            client:subscribe(base .. "/cmd", 1)
            publish_state("boot")
        elseif event == "recv" then
            handle_cmd(payload)
        elseif event == "disconnect" then
            log.warn("mqtt", "disconnected")
        end
    end)
    mqttc:autoreconn(true, 5000)
    mqttc:connect()

    while true do
        publish_telemetry()
        local p = cfg.periods
        local wait = state.mode == "lost" and p.lost_telemetry
            or state.mode == "stationary" and p.stationary_heartbeat
            or state.mode == "low_power" and p.low_power_heartbeat
            or state.mode == "charging" and p.charging_telemetry
            or p.routine_telemetry
        if state.battery_pct < cfg.low_battery_pct and state.mode ~= "charging" then state.mode = "low_power" end
        sys.wait(wait * 1000)
    end
end)

sys.run()
