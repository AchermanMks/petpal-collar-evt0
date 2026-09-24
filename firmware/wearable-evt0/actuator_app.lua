-- All outputs off at boot. Unverified motor GPIOs are untouched.
local cfg, A = _G.CFG, _G.CFG.actuator
local M={MAX_PULSE_MS=500,MAX_COUNT=3,COOLDOWN_S=30,BREATHE_PERIOD_MS=3000,PWM_WINDOW_MS=20}
-- 命令间隔：佩戴固件按测试方案硬性规则 ≥30 s（默认）。actuator.cooldown_s 只给有人值守的开发板台架缩短，下限 3 s
if type(A.cooldown_s)=="number" and A.cooldown_s==A.cooldown_s then M.COOLDOWN_S=math.max(3,math.floor(A.cooldown_s)) end
local last_exec, busy, motor_gen, led_gen=nil,false,0,0
local led_off=A.led_on_level==1 and 0 or 1
local motor_off=A.motor_on_level==1 and 0 or 1
_G.STATE.outputs=_G.STATE.outputs or {}
_G.STATE.outputs.led_on,_G.STATE.outputs.motor_on=false,false
-- 本板已有用途的脚，永远不能当马达脚：26=I2C1 总线电源（拉低摄像头/DA267 一起消失，旧配置踩过）、24/28=I2C 供电与上拉、
-- 22/5=摄像头电源/PWDN、21=GNSS 电源、25=功放使能、2=ES8311 供电、20=DA267 中断、16=板载灯
local RESERVED={[26]=true,[24]=true,[28]=true,[22]=true,[5]=true,[21]=true,[25]=true,[2]=true,[20]=true,[16]=true}
local function motor_ok() return A.motor_verified==true and type(A.motor_gpio)=="number" and not RESERVED[A.motor_gpio] end
if A.motor_verified==true and type(A.motor_gpio)=="number" and RESERVED[A.motor_gpio] then log.error("actuator","motor_gpio",A.motor_gpio,"is reserved on this board; motor disabled") end
local function drive_led(on)
    gpio.set(A.led_gpio,on and A.led_on_level or led_off)
    _G.STATE.outputs.led_on=on
end
local function drive_motor(on)
    gpio.set(A.motor_gpio,on and A.motor_on_level or motor_off)
    _G.STATE.outputs.motor_on=on
end
gpio.setup(A.led_gpio,led_off)
if motor_ok() then gpio.setup(A.motor_gpio,motor_off) end
local function finite(n) return type(n)=="number" and n==n and math.abs(n)~=math.huge end
function M.clamp_vibrate(args)
    args=args or {}; local d,c=args.duration_ms or 200,args.count or 1
    if not finite(d) or not finite(c) then return nil,"invalid_args" end
    local out={duration_ms=math.floor(math.max(50,math.min(500,d))),count=math.floor(math.max(1,math.min(3,c)))}
    return out,out.duration_ms~=d or out.count~=c
end
function M.check_allowed()
    local S=_G.STATE
    if not motor_ok() then return "hardware_unverified" end
    if not S.battery.ready then return "battery_unknown" end
    -- 佩戴版：充电时拒绝（充电要摘下项圈）。bench_allow_charging 只给插着 USB 的开发板台架用，回执会标明
    if S.battery.charging and A.bench_allow_charging~=true then return "charging" end
    if S.battery.pct<cfg.low_battery_pct then return "low_battery" end
    if S.battery.temp_c==nil and not A.bench_allow_unknown_temp then return "temperature_unknown" end
    if S.battery.temp_c and S.battery.temp_c>45 then return "over_temp" end
    if busy then return "busy" end
    if last_exec and mcu.ticks()-last_exec<M.COOLDOWN_S*1000 then return "cooldown" end
end
function M.stop_motor()
    motor_gen=motor_gen+1
    if motor_ok() then drive_motor(false) end
end
function M.vibrate(args)
    local out,clamped=M.clamp_vibrate(args); if not out then return false,clamped end
    local reason=M.check_allowed(); if reason then return false,reason end
    busy=true; last_exec=mcu.ticks(); motor_gen=motor_gen+1
    local generation=motor_gen
    local ok=pcall(function()
        for i=1,out.count do
            if generation~=motor_gen then return end
            local S=_G.STATE
            if (S.battery.charging and A.bench_allow_charging~=true) or not S.battery.ready or S.battery.pct<cfg.low_battery_pct then error("safety_changed") end
            if S.battery.charging then out.bench_charging_override=true end
            drive_motor(true); sys.wait(out.duration_ms)
            drive_motor(false)
            if i<out.count then sys.wait(300) end
        end
    end)
    drive_motor(false); busy=false
    if not ok then return false,"execution_failed" end
    if generation~=motor_gen then return false,"cancelled" end
    return true,clamped and "limit_clamped" or nil,out
end
function M.led(pattern,duration_s)
    pattern=pattern or "blink"; duration_s=duration_s or 5
    if pattern~="off" and pattern~="on" and pattern~="blink" and pattern~="breathe" then return false,"invalid_pattern" end
    if not finite(duration_s) then return false,"invalid_duration" end
    duration_s=math.max(0,math.min(300,duration_s))
    led_gen=led_gen+1; local generation=led_gen
    drive_led(false)
    if pattern=="off" then return true end
    if pattern=="on" then
        drive_led(duration_s>0)
        sys.timerStart(function() if generation==led_gen then drive_led(false) end end,duration_s*1000)
        return true
    end
    local stop=mcu.ticks()+duration_s*1000
    if pattern=="breathe" then
        -- GPIO16 无硬件 PWM：软件 PWM，50 Hz 窗口(20 ms)内按占空比亮灭，占空比随三角波在 BREATHE_PERIOD_MS 内 5%→100%→5%
        -- （2026-09-24 用户要求真正的呼吸效果；之前是 500/500 ms 慢闪）。只在呼吸期间占 CPU，其它模式不受影响。
        local period=M.BREATHE_PERIOD_MS
        local t0=mcu.ticks()
        while generation==led_gen and mcu.ticks()<stop do
            local phase=((mcu.ticks()-t0)%period)/period*2
            local duty=0.05+0.95*(1-math.abs(phase-1))
            local on_ms=math.floor(duty*M.PWM_WINDOW_MS+0.5)
            if on_ms>0 then drive_led(true); sys.wait(on_ms) end
            if generation~=led_gen then return false,"cancelled" end
            if on_ms<M.PWM_WINDOW_MS then drive_led(false); sys.wait(M.PWM_WINDOW_MS-on_ms) end
        end
        if generation==led_gen then drive_led(false) end
        return generation==led_gen,generation~=led_gen and "cancelled" or nil
    end
    while generation==led_gen and mcu.ticks()<stop do
        drive_led(true)
        sys.wait(math.min(200,math.max(0,stop-mcu.ticks())))
        if generation~=led_gen then return false,"cancelled" end
        drive_led(false)
        sys.wait(math.min(800,math.max(0,stop-mcu.ticks())))
    end
    if generation==led_gen then drive_led(false) end
    return generation==led_gen,generation~=led_gen and "cancelled" or nil
end
sys.subscribe("CHARGING_START",function() if A.bench_allow_charging~=true then M.stop_motor() end end)
sys.subscribe("MODE_CHANGED",function(mode) if mode=="low_power" then M.stop_motor() end end)
_G.ACT=M
return M
