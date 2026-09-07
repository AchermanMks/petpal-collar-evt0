-- 复制为 config.lua 并填写；config.lua 已在 .gitignore
return {
    device_id = "collar-evt-001",
    fw = "evt0.0.1",
    mqtt = {
        host = "broker.example.com",
        port = 8883,
        tls = true,
        ca_file = "/luadb/ca.crt",     -- 上传到脚本区
        user = "collar-evt-001",
        pass = "CHANGE_ME",
        keepalive = 120,
    },
    periods = {                          -- 秒；对应方案 3.5 状态机
        stationary_heartbeat = 3600,
        routine_telemetry = 300,
        routine_gnss = 600,
        lost_telemetry = 20,
        low_power_heartbeat = 3600,
        low_power_gnss = 2700,
        charging_telemetry = 300,
    },
    low_battery_pct = 15,
    lost_ttl_s = 7200,
    cache_max = 1000,
    gnss_timeout_s = 90,
    motion_still_s = 600,                -- 持续静止多久进入 stationary
}
