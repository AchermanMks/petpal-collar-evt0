-- 复制为 config.lua 并填写；config.lua 已在 .gitignore，不要提交
return {
    device_id = "collar-evt-001",
    fw = "evt0.0.1",

    -- 功能开关：先只开 mqtt，逐项打开，见 docs/05_BOARD_BRINGUP_PLAN.md
    features = {
        mqtt = true,
        gnss = false,
        gsensor = false,
        power = false,
        actuator = false,
        ble = false,
        lowpower = false,          -- 全部调通后再开 pm.power(pm.WORK_MODE, 1)
    },

    mqtt = {
        host = "broker.example.com",
        port = 8883,
        tls = true,
        ca_file = "/luadb/ca.crt", -- 与脚本一起烧录的 CA 证书文件名
        user = "collar-evt-001",
        pass = "CHANGE_ME",
        keepalive = 120,
        client_id = nil,           -- nil 则用 device_id
    },

    telemetry_period_s = 30,       -- 调试阶段 30 s；正式 routine 为 300 s
    gnss = {
        mode = 1,                  -- 1 全星座，2 单北斗
        timeout_s = 90,
        power_gpio = 21,
        uart_id = 2,
        nmea_debug = false,
        agps = true,
    },
    gsensor = {
        i2c_id = 1, addr = 0x26,
        power_gpio = 24, pullup_gpio = 28,
        int_gpio = 20,             -- 出厂工程 20；demo 39；实测后改
        threshold = 0x20,
        motion_timeout_s = 10,
    },
    power = {
        adc_channel = 0,
        divider_high_k = 1000, divider_low_k = 300, offset_mv = 140,
        full_mv = 4150, empty_mv = 3300,
        sample_period_ms = 60000,
    },
    actuator = {
        led_gpio = 16,  led_on_level = 1,
        motor_gpio = 26,           -- 经 MOSFET 驱动马达；板上无马达时可接 LED 观察
        motor_on_level = 1,
    },
    ble = {
        name = "PetPal-EVT",
        ibeacon_uuid = "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0",
        major = 1, minor = 1, tx_power = -59,
        adv_interval_ms = 1000,
    },
    low_battery_pct = 15,
}
