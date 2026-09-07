--[[ F10：BLE 广播（LM 板载蓝牙，bluetooth 核心库，来自出厂工程 myble.lua）
若板子走 Air5101 外挂路径，用 reference/ble/peripheral/Air8201G_Air5101S 并 exril_5101.config_uart(2) ]]
local cfg = _G.CFG
local B = cfg.ble

if not bluetooth then log.error("ble", "bluetooth lib missing in this core firmware"); return end

local function cb(evt, param)
    if evt == bluetooth.EVENT_ADV_START then log.info("ble", "adv started")
    elseif evt == bluetooth.EVENT_ADV_STOP then log.info("ble", "adv stopped")
    elseif evt == bluetooth.EVENT_CONNECT then log.info("ble", "connected")
    elseif evt == bluetooth.EVENT_DISCONNECT then log.info("ble", "disconnected")
    elseif evt == bluetooth.EVENT_WRITE then log.info("ble", "write", param and json.encode(param))
    else log.info("ble", "event", evt) end
end

sys.taskInit(function()
    local dev = bluetooth.init()
    if not dev then log.error("ble", "bluetooth.init failed"); return end
    local ble = dev:ble(cb)
    if not ble then log.error("ble", "ble init failed"); return end
    local iv = math.floor(B.adv_interval_ms * 1.6)
    ble:adv_create({ interval_min = iv, interval_max = iv, adv_type = bluetooth.ADV_TYPE_ADV_IND,
                     own_addr_type = bluetooth.PUBLIC, direct_addr_type = bluetooth.PUBLIC, direct_addr = nil,
                     channel_map = 7, filter_policy = bluetooth.ADV_FILTER_ALLOW_ALL })
    ble:adv_data(bluetooth.make_ibeacon_data(B.ibeacon_uuid, B.major, B.minor, B.tx_power))
    local ok, err = ble:adv_start()
    log.info("ble", "adv_start", ok, err, "uuid", B.ibeacon_uuid)
end)
