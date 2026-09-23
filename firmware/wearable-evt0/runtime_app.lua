-- PetPal application state: requested mode is separate from safety/power mode.
local M = {}
local cfg, S = _G.CFG, _G.STATE
local requested, deadline = "routine", nil
local fence_state, fence_candidate, fence_count
local seq = 0
if fskv then
    -- 实板 V2030 的 tonumber(nil) 直接报错（不返回 nil）：键不存在时先兜底成 ""（2026-09-20 板1 清 KV 后首启崩溃）
    S.boot_count = (tonumber(fskv.get("pp_boot") or "") or 0) + 1
    fskv.set("pp_boot", S.boot_count)
end

function M.clock_valid() return os.time() >= 1700000000 end
function M.event(kind, data)
    seq = seq + 1
    sys.publish("PETPAL_EVENT", {v=1, device_id=cfg.device_id, seq=seq,
        ts=M.clock_valid() and os.time() or 0, boot_count=S.boot_count,
        clock_synced=M.clock_valid(), type=kind, data=data or {}})
end

function M.refresh_mode()
    if deadline and mcu.ticks() >= deadline then requested, deadline = "routine", nil end
    local mode = requested
    if S.battery.ready and S.battery.pct < cfg.low_battery_pct then mode = "low_power" end
    if requested == "routine" and S.motion.ready and S.motion.state == "still" and mode == "routine" then mode = "stationary" end
    if S.battery.charging then mode = "charging" end
    if S.mode ~= mode then
        local old = S.mode; S.mode = mode
        M.event("mode_changed", {from=old, mode=mode})
        sys.publish("MODE_CHANGED", mode)
    end
end

function M.set_mode(mode, ttl)
    if mode ~= "routine" and mode ~= "lost" then return false, "unsupported_mode" end
    ttl = ttl or 7200
    if type(ttl) ~= "number" or ttl ~= ttl or ttl % 1 ~= 0 or ttl < 60 or ttl > 7200 then return false, "invalid_ttl" end
    requested = mode
    deadline = mode == "lost" and (mcu.ticks() + ttl * 1000) or nil
    M.refresh_mode(); return true
end

function M.distance(lat1, lng1, lat2, lng2)
    local rad = math.pi / 180
    local a = math.sin((lat2-lat1)*rad/2)^2 + math.cos(lat1*rad)*math.cos(lat2*rad)*math.sin((lng2-lng1)*rad/2)^2
    return 6371000 * 2 * math.asin(math.sqrt(math.max(0, math.min(1, a))))
end

function M.set_fence(f)
    if type(f) ~= "table" then return false, "invalid_fence" end
    if f.enabled == false then
        if not fskv or not fskv.set("pp_fence",json.encode({enabled=false})) then return false,"storage_failed" end
        cfg.geofence = {enabled=false}; fence_state=nil; return true
    end
    for _, k in ipairs({"lat", "lng", "radius_m"}) do
        if type(f[k]) ~= "number" or f[k] ~= f[k] or math.abs(f[k]) == math.huge then return false, "invalid_fence" end
    end
    if math.abs(f.lat)>90 or math.abs(f.lng)>180 or f.radius_m<50 or f.radius_m>50000 then return false, "invalid_fence" end
    local stored = {enabled=true, lat=f.lat, lng=f.lng, radius_m=f.radius_m}
    if not fskv or not fskv.set("pp_fence", json.encode(stored)) then return false, "storage_failed" end
    cfg.geofence=stored; fence_state, fence_candidate, fence_count=nil,nil,0; return true
end

function M.position(p)
    local f = cfg.geofence
    if not f or not f.enabled or not p or p.source ~= "gnss" or not p.accuracy_m then return end
    -- Use uncertainty band + two independent fixes; no exit alarm from stale/LBS data.
    local d = M.distance(f.lat,f.lng,p.lat,p.lng)
    local margin = math.max(20,p.accuracy_m)
    local candidate
    if d > f.radius_m + margin then candidate="outside"
    elseif d < math.max(0,f.radius_m-margin) then candidate="inside" end
    if not candidate then fence_candidate,fence_count=nil,0; return end
    if candidate == fence_candidate then fence_count=(fence_count or 0)+1
    else fence_candidate,fence_count=candidate,1 end
    if fence_count >= 2 and candidate ~= fence_state then
        local old=fence_state; fence_state=candidate
        if old or candidate == "outside" then M.event(candidate=="outside" and "geofence_exit" or "geofence_enter", {distance_m=math.floor(d),radius_m=f.radius_m}) end
    end
end

function M.capabilities()
    return {gnss=S.gnss.ready==true, battery=S.battery.ready==true,
        motion=S.motion.ready==true, led=_G.ACT~=nil,
        vibration=_G.ACT~=nil and cfg.actuator.motor_verified==true,
        ble=S.ble_ready==true, mqtt=S.mqtt_online==true,
        camera=S.camera and S.camera.ready==true or false, audio=S.audio and S.audio.ready==true or false, rgb=false, fota=false,
        activity="experimental_not_health_measurement", arc=false}
end

if fskv then
    local raw=fskv.get("pp_fence")
    if type(raw)=="string" then local ok,f=pcall(json.decode,raw); if ok and type(f)=="table" then cfg.geofence=f end end
end
sys.timerLoopStart(M.refresh_mode, 1000)
_G.PETPAL=M
return M
