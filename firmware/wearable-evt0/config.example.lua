-- 复制为 config.lua 并填写；config.lua 已在 .gitignore，不要提交
return {
    device_id = "collar-evt-001",
    fw = "evt0.0.3",
    diagnostics_upload = false,   -- 不自动向第三方上传错误/设备数据
    lowpower_bench_verified = false, -- 未验证耗电/唤醒前不得关闭 USB
    outbox = {max_records = 64},
    geofence = {enabled = false},

    -- 功能开关：默认全部关闭；板载台架使用独立 bench 包；配置真实服务后再启用 MQTT
    features = {
        mqtt = false,             -- 配好真实 TLS broker/CA/ACL 后开启
        gnss = false,
        gsensor = false,
        power = false,
        actuator = false,
        ble = false,
        lowpower = false,          -- 全部调通后再开 pm.power(pm.WORK_MODE, 1)
        camera = false,
        audio = false,            -- ES8311 + AW8010B；喇叭焊在 SPK+/SPK- 后才开
    },

    camera = {board = nil}, -- 专用摄像头包填写准确 BTB 型号；默认不猜引脚
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
        agps = false,             -- 初次无卡台架测试不请求第三方 AGPS
        tracking = false,         -- true=GNSS 常开每秒更新（台架/实时看位置）；false=按模式周期定位后关闭（省电）
    },
    gsensor = {
        i2c_id = 1, addr = 0x26,
        power_gpio = 24, pullup_gpio = 28,
        int_gpio = 20,             -- 出厂工程 20；demo 39；实测后改
        bus_power_gpio = 26,       -- I2C1 外围供电（官方例程），与摄像头共用，只拉高不拉低
        i2c_fast = false,          -- true=400 kHz；默认 100 kHz（出厂工程）
        use_readreg = true,        -- false 则用 send+recv（对比 NACK 率用）
        sample_ms = 100,
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
        motor_gpio = nil,          -- 必须核对原理图/实际 MOSFET 接线，不能猜引脚
        motor_verified = false,
        bench_allow_unknown_temp = false, -- 仅无人/无动物台架显式允许，无温度传感器不能当作25°C
        bench_allow_charging = false,     -- 仅插着 USB 的开发板台架；佩戴/量产固件必须为 false（充电时拒绝震动）
        cooldown_s = 30,                  -- 两次震动命令的最小间隔；佩戴固件保持 30（方案硬性规则），台架可缩短，固件下限 3
        motor_on_level = 1,
    },
    ble = {
        name = "PetPal-EVT",
        ibeacon_uuid = "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0",
        major = 1, minor = 1, tx_power = -59,
        adv_interval_ms = 1000,
    },
    audio = { max_volume = 60, pa_gpio = 25, codec_pwr_gpio = 2, mode = "new" }, -- 宠物佩戴：音量硬上限，先保守
    low_battery_pct = 15,
}
