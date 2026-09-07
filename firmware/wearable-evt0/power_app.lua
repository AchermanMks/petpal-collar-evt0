--[[ F6：ADC0 电池电压、VBUS 充电检测、PWRKEY 长按关机；维护 STATE.battery
参考 reference/project/Air8201G/factory/code/mypower.lua ]]
local cfg = _G.CFG
local P = cfg.power

local function read_mv()
    local samples = {}
    for i = 1, 5 do
        adc.setRange(adc.ADC_RANGE_MIN)
        adc.open(P.adc_channel)
        local raw = adc.get(P.adc_channel)
        adc.close(P.adc_channel)
        if raw then
            samples[#samples + 1] = raw * (P.divider_high_k + P.divider_low_k) / P.divider_low_k + P.offset_mv
        end
        sys.wait(10)
    end
    if #samples < 3 then return nil end
    table.sort(samples)
    local sum = 0
    for i = 2, #samples - 1 do sum = sum + samples[i] end
    return math.floor(sum / (#samples - 2) + 0.5)
end

local function pct(mv)
    if mv >= P.full_mv then return 100 end
    if mv <= P.empty_mv then return 0 end
    return math.floor((mv - P.empty_mv) / (P.full_mv - P.empty_mv) * 100)
end

sys.taskInit(function()
    while true do
        local mv = read_mv()
        -- 对照：主供电脚直读（无分压）
        adc.open(adc.CH_VBAT); local vbat = adc.get(adc.CH_VBAT); adc.close(adc.CH_VBAT)
        if mv then
            _G.STATE.battery.mv = mv
            _G.STATE.battery.pct = pct(mv)
            if _G.STATE.battery.pct < cfg.low_battery_pct and not _G.STATE.battery.charging and _G.STATE.mode ~= "charging" then
                _G.STATE.mode = "low_power"
            end
        end
        log.info("power", "adc0_mv", mv, "pct", _G.STATE.battery.pct, "ch_vbat_mv", vbat, "charging", _G.STATE.battery.charging)
        sys.wait(P.sample_period_ms)
    end
end)

-- VBUS（WAKEUP1）插拔
gpio.debounce(gpio.WAKEUP1, 200)
gpio.setup(gpio.WAKEUP1, function()
    local lv = gpio.get(gpio.WAKEUP1)
    _G.STATE.battery.charging = (lv == 1)
    _G.STATE.mode = (lv == 1) and "charging" or "routine"
    log.info("power", lv == 1 and "CHARGING_START" or "CHARGING_STOP")
    sys.publish(lv == 1 and "CHARGING_START" or "CHARGING_STOP")
end, gpio.PULLDOWN, gpio.BOTH)
_G.STATE.battery.charging = (gpio.get(gpio.WAKEUP1) == 1)

-- PWRKEY 长按 7 s 关机（轮询法，来自出厂工程）
gpio.debounce(gpio.PWR_KEY, 200)
local polling = false
gpio.setup(gpio.PWR_KEY, function()
    if gpio.get(gpio.PWR_KEY) == 0 and not polling then polling = true; sys.publish("PWRKEY_POLL") end
end, gpio.PULLUP, gpio.FALLING)
sys.taskInit(function()
    while true do
        sys.waitUntil("PWRKEY_POLL")
        local n = 0
        while true do
            sys.wait(1000)
            if gpio.get(gpio.PWR_KEY) == 0 then
                n = n + 1; log.info("power", "PWRKEY held", n)
                if n >= 7 then log.warn("power", "shutdown"); pm.shutdown() end
            else
                log.info("power", "PWRKEY short press"); sys.publish("PWRKEY_SHORT"); break
            end
        end
        polling = false
    end
end)
