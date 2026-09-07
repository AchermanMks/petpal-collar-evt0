--[[ F5：DA267 三轴加速度 / 震动中断（原始寄存器写法，来自出厂工程）；维护 STATE.motion
若底层固件带 exs_da267 扩展库，可改用 reference/gsensor/da267_app.lua 的写法 ]]
local cfg = _G.CFG
local G = cfg.gsensor
local REG = { WHO_AM_I = 0x01, RANGE = 0x0F, BW_ODR = 0x10, MODE = 0x11, INT_EN = 0x16, INT_CFG = 0x19,
              THS_X = 0x39, THS_Y = 0x3A, THS_Z = 0x3B, X_L = 0x02 }

local function wr(reg, v) return i2c.send(G.i2c_id, G.addr, { reg, v }, 1) end
local function rd(reg, n) i2c.send(G.i2c_id, G.addr, reg, 1); return i2c.recv(G.i2c_id, G.addr, n) end

local last_int = 0
local motion_timer

local function on_int()
    local now = mcu.ticks()
    if now - last_int < 3000 then return end        -- 中断节流 3 s
    last_int = now
    _G.STATE.motion.state = "moving"
    log.info("gsensor", "MOTION")
    sys.publish("GSENSOR_MOTION")
    if motion_timer then sys.timerStop(motion_timer) end
    motion_timer = sys.timerStart(function()
        _G.STATE.motion.state = "still"; log.info("gsensor", "STILL")
    end, G.motion_timeout_s * 1000)
end

sys.taskInit(function()
    gpio.setup(G.power_gpio, 1, gpio.PULLUP); sys.wait(50)
    gpio.setup(G.pullup_gpio, 1, gpio.PULLUP); sys.wait(150)      -- 上电总延时 ≥200 ms
    i2c.close(G.i2c_id); i2c.setup(G.i2c_id, i2c.SLOW)
    local id
    for attempt = 1, 5 do
        local d = rd(REG.WHO_AM_I, 1)
        id = d and d:byte(1)
        if id == 0x13 then break end
        log.warn("gsensor", "WHO_AM_I retry", attempt, id); sys.wait(100)
    end
    if id ~= 0x13 then
        log.error("gsensor", "DA267 not found, power off"); gpio.setup(G.power_gpio, 0); gpio.setup(G.pullup_gpio, 0); return
    end
    log.info("gsensor", "DA267 ok chipid 0x13")
    wr(REG.RANGE, 0x01); wr(REG.BW_ODR, 0x07); wr(REG.INT_EN, 0x87)
    wr(REG.THS_X, G.threshold); wr(REG.THS_Y, G.threshold); wr(REG.THS_Z, G.threshold)
    wr(REG.INT_CFG, 0x04); wr(REG.MODE, 0x30)
    gpio.debounce(G.int_gpio, 100)
    gpio.setup(G.int_gpio, on_int, gpio.PULLDOWN, gpio.RISING)
    log.info("gsensor", "int on GPIO", G.int_gpio, "threshold", G.threshold)
    -- 每 5 s 读一次三轴，便于确认 I2C 通路与方向
    while true do
        local d = rd(REG.X_L, 6)
        if d and #d == 6 then
            local function ax(lo, hi) local v = (hi << 8 | lo); if v >= 32768 then v = v - 65536 end; return v / 4 / 2048 end  -- 12bit 左对齐, 4g 量程
            log.info("gsensor", string.format("x=%.2f y=%.2f z=%.2f g", ax(d:byte(1), d:byte(2)), ax(d:byte(3), d:byte(4)), ax(d:byte(5), d:byte(6))), _G.STATE.motion.state)
        end
        sys.wait(5000)
    end
end)
