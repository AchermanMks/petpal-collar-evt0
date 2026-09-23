--[[ F5：DA267 三轴加速度 / 震动中断（原始寄存器写法，来自出厂工程）；维护 STATE.motion
与摄像头共用 I2C1 → 二选一：camera_app 打开传感器时调 M.pause()，摄像头空闲断电后调 M.resume()（2026-09-22）。
读取用 i2c.readReg（带重复起始位）：板2 实测 send+recv 约 30% NACK；失败保留上次值，连续失败才标 ready=false。 ]]
local cfg = _G.CFG
local G = cfg.gsensor
local activity = require("activity_app")
local REG = { WHO_AM_I = 0x01, RANGE = 0x0F, BW_ODR = 0x10, MODE = 0x11, INT_EN = 0x16, INT_CFG = 0x19,
              THS_X = 0x39, THS_Y = 0x3A, THS_Z = 0x3B, X_L = 0x02 }
local M = { FAIL_LIMIT = 20 }
local S = _G.STATE.motion
local paused, running, generation = false, false, 0
local last_int, motion_timer = 0, nil
S.reads, S.read_fails = 0, 0

local function wr(reg, v) return i2c.send(G.i2c_id, G.addr, { reg, v }, 1) end
local function rd1(reg, n)
    local d
    if i2c.readReg and G.use_readreg ~= false then d = i2c.readReg(G.i2c_id, G.addr, reg, n)
    else if i2c.send(G.i2c_id, G.addr, reg, 1) then d = i2c.recv(G.i2c_id, G.addr, n) end end
    if type(d) == "string" and #d == n then return d end
    return nil
end
-- 一次 NACK 不算失败：官方出厂工程注释“i2c -6 多由时序导致，重试通常可恢复”
local function rd(reg, n) return rd1(reg, n) or rd1(reg, n) end

local function on_int()
    local now = mcu.ticks()
    if paused or now - last_int < 3000 then return end   -- 中断节流 3 s
    last_int = now
    S.state = "moving"
    log.info("gsensor", "MOTION")
    sys.publish("GSENSOR_MOTION")
    if motion_timer then sys.timerStop(motion_timer) end
    motion_timer = sys.timerStart(function() S.state = "still"; log.info("gsensor", "STILL") end, G.motion_timeout_s * 1000)
end

local function power_off()
    pcall(gpio.setup, G.int_gpio, nil)
    gpio.setup(G.power_gpio, 0); gpio.setup(G.pullup_gpio, 0)   -- 26 不动：摄像头也靠它
    pcall(i2c.close, G.i2c_id)
    S.ready = false
end

-- 上电 + 识别 + 配置；返回 true/false（须在 task 内调用）
local function init()
    -- 官方 Air8201G DA267 例程上电三根脚：24 传感器供电、28 I2C1 上拉、26 I2C1 外围供电。之前漏了 26（2026-09-22 实板 40% 读失败）
    if G.bus_power_gpio then gpio.setup(G.bus_power_gpio, 1) end
    gpio.setup(G.power_gpio, 1, gpio.PULLUP); sys.wait(50)
    gpio.setup(G.pullup_gpio, 1, gpio.PULLUP); sys.wait(150)      -- 上电总延时 ≥200 ms
    pcall(i2c.close, G.i2c_id); i2c.setup(G.i2c_id, G.i2c_fast and i2c.FAST or i2c.SLOW)
    local id
    for attempt = 1, 5 do
        local d = rd(REG.WHO_AM_I, 1)
        id = d and d:byte(1)
        if id == 0x13 then break end
        log.warn("gsensor", "WHO_AM_I retry", attempt, id); sys.wait(100)
    end
    if id ~= 0x13 then log.error("gsensor", "DA267 not found, power off"); power_off(); return false end
    log.info("gsensor", "DA267 ok chipid 0x13")
    wr(REG.RANGE, 0x01); wr(REG.BW_ODR, 0x07); wr(REG.INT_EN, 0x87)
    wr(REG.THS_X, G.threshold); wr(REG.THS_Y, G.threshold); wr(REG.THS_Z, G.threshold)
    wr(REG.INT_CFG, 0x04); wr(REG.MODE, 0x30)
    gpio.debounce(G.int_gpio, 100)
    gpio.setup(G.int_gpio, on_int, gpio.PULLDOWN, gpio.RISING)
    log.info("gsensor", "int on GPIO", G.int_gpio, "threshold", G.threshold)
    S.ready = true; S.read_fails = 0
    return true
end

local function loop()
    if running then return end
    running = true; generation = generation + 1
    local gen = generation
    sys.taskInit(function()
        if not init() then running = false; return end
        local consecutive = 0
        while gen == generation and not paused do
            local d = rd(REG.X_L, 6)
            S.reads = S.reads + 1
            if d then
                consecutive = 0
                local function ax(lo, hi) local v = (hi << 8 | lo); if v >= 32768 then v = v - 65536 end; return v / 4 / 2048 end  -- 12bit 左对齐, 4g 量程
                activity.sample(ax(d:byte(1),d:byte(2)),ax(d:byte(3),d:byte(4)),ax(d:byte(5),d:byte(6)),mcu.ticks())
                S.ready = true
            else
                S.read_fails = S.read_fails + 1; consecutive = consecutive + 1
                if consecutive == M.FAIL_LIMIT then log.warn("gsensor", "I2C read failing; data stale"); S.ready = false end
            end
            sys.wait(G.sample_ms or 100) -- 默认 10Hz 估计活动，不把中断次数当作真实步数
        end
        running = false
    end)
end

function M.pause(why)
    if paused then return end
    paused = true; generation = generation + 1
    if motion_timer then sys.timerStop(motion_timer); motion_timer = nil end
    power_off(); S.paused = why or true; S.state = "unknown"
    log.info("gsensor", "paused", why)
end
function M.resume()
    if not paused then return end
    paused = false; S.paused = nil; S.state = "still"
    log.info("gsensor", "resumed"); loop()
end
-- 运行时调参（云端/USB）：fast 0|1、readreg 0|1、sample <ms>；改完重启传感器并清零计数
function M.tune(key, val)
    if key == "fast" then G.i2c_fast = (val == "1")
    elseif key == "readreg" then G.use_readreg = (val ~= "0")
    elseif key == "sample" then local ms = tonumber(val or ""); if not ms or ms < 20 or ms > 5000 then return false, "invalid_sample" end; G.sample_ms = math.floor(ms)
    else return false, "unknown_key" end
    S.reads, S.read_fails = 0, 0
    if not paused then M.pause("tune"); M.resume() end
    return true
end
function M.status() return { ready = S.ready, paused = S.paused, reads = S.reads, read_fails = S.read_fails, state = S.state, steps = S.steps, activity = S.activity } end

loop()
_G.GSENSOR = M
return M
