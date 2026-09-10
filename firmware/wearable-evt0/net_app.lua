--[[ F2：SIM 注册、IP_READY、信号；维护 STATE.radio ]]
local cfg = _G.CFG
local t0 = mcu.ticks()

local function mask(s)
    s = tostring(s or "")
    if #s <= 6 then return "***" end
    return s:sub(1, 3) .. string.rep("*", #s - 6) .. s:sub(-3)
end

-- BLMQ 板 SIM 座可能接在 SIM2：让底层自动扫两个卡槽（0/1 固定，2 自动）
if mobile.simid then
    local ok, e = pcall(mobile.simid, 2)
    log.info("net", "simid auto", ok, e)
end

sys.taskInit(function()
    log.info("net", "waiting SIM/network ...")
    local n = 0
    while not socket.adapter(socket.dft()) do
        sys.waitUntil("IP_READY", 1000)
        n = n + 1
        if n % 10 == 0 then   -- 每 10 s 打一次 SIM/网络诊断，便于 Mac 端看卡在哪
            log.info("net", "still waiting", n, "s", "status", mobile.status(),
                     "simid", mobile.simid and mobile.simid() or "?",
                     "iccid", mobile.iccid() and mask(mobile.iccid()) or "nil",
                     "csq", mobile.csq())
        end
    end
    local dt = (mcu.ticks() - t0) / 1000
    log.info("net", "IP_READY after", dt, "s", "status", mobile.status())
    -- 标识只打脱敏形式；完整值记到本地台账
    log.info("net", "imei", mask(mobile.imei()), "iccid", mask(mobile.iccid()))
    _G.STATE.online = true
    sys.publish("NET_READY", dt)
end)

sys.subscribe("IP_LOSE", function() _G.STATE.online = false; log.warn("net", "IP_LOSE") end)

-- 每 30 s 刷新信号
sys.timerLoopStart(function()
    local rsrp, rssi, csq = mobile.rsrp(), mobile.rssi(), mobile.csq()
    _G.STATE.radio.rsrp_dbm = rsrp or -140
    _G.STATE.radio.rssi_dbm = rssi or -114
    log.info("net", "rsrp", rsrp, "rssi", rssi, "csq", csq, "status", mobile.status())
end, 30000)
