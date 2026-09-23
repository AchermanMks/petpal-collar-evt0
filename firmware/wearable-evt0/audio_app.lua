--[[ 声音输出：ES8311(I2C0, 供电 GPIO2) + AW8010B 功放(使能 GPIO25)，喇叭接核心板 SPK+/SPK-。
接口见 docs/16_APP_FIRMWARE_PROTOCOL.md 第 7 节：command type=BUZZ，args.kind = beep / test / tts / file / meow。
依据合宙官方 module/Air8201/demo/audio（exaudio.lua 原样放在 libs/；I2C0 复用脚靠随包烧录的 pins_air780egh.json）。
安全：音量硬上限 cfg.audio.max_volume；单次 ≤10 s；低电量拒绝；STOP 立即停声。首次播放才初始化编解码器，失败不影响其他功能。 ]]
local cfg, S = _G.CFG, _G.STATE
local A = cfg.audio or {}
local M = { MAX_MS = 10000, BEEP_MAX_MS = 3000, RATE = 16000 }
local ex, busy, cancelled, current_type = nil, false, false, nil
local beep_key
S.audio = { ready = false }
S.outputs = S.outputs or {}
S.outputs.speaker_on = false

local function max_volume() return math.min(100, math.max(0, tonumber(A.max_volume or "") or 60)) end

local function setup()
    if ex then return true end
    local ok, lib = pcall(require, "exaudio")
    if not ok then S.audio = { ready = false, error = "exaudio_missing" }; return false, "unsupported" end
    -- dac_delay 单位：底层 ≥V2026 为 100 ms，之前为 1 ms（官方例程同样判断）
    local v = tonumber((rtos.version() or ""):match("V(%d+)") or "") or 0
    -- exaudio 一旦被要求过 "new" 就整模块切到 audio_v2 且切不回来（板1 V2030_1 没有 audio_v2 库，2026-09-21 实测
    -- 因此两次 setup 都失败）。所以只在底层真的带 audio_v2 时才请求 "new"，否则只走旧框架，绝不先试 "new"。
    local mode = ((A.mode or "new") == "new" and _G.audio_v2 ~= nil) and "new" or "old"
    if mode == "old" and _G.audio == nil then S.audio = { ready = false, error = "core_has_no_audio_lib" }; return false, "unsupported" end
    local ok2, res = pcall(lib.setup, { model = "es8311", i2c_id = 0, dac_delay = v >= 2026 and 6 or 600,
        pa_ctrl = A.pa_gpio or 25, dac_ctrl = A.codec_pwr_gpio or 2, audio_mode = mode, codec_voltage = 1 })
    log.info("audio", "setup", mode, ok2, res)
    if ok2 and res then ex = lib; S.audio = { ready = true, mode = mode }; return true end
    S.audio = { ready = false, error = "codec_init_failed", mode = mode }
    return false, "hardware_unverified"
end

-- 16 kHz 16 bit 单声道 WAV；频率取整到 10 Hz，使 100 ms 一块内是整数个周期，可直接重复拼接
local function beep_file(freq, ms)
    local key = freq .. "_" .. ms
    local path = "/pp_beep.wav"
    if beep_key == key and io.exists(path) then return path end
    local n = M.RATE // 10
    local t = {}
    for i = 0, n - 1 do
        local v = math.floor(9000 * math.sin(2 * math.pi * freq * i / M.RATE))
        if v < 0 then v = v + 65536 end
        t[#t + 1] = string.char(v % 256, v // 256)
    end
    local body = string.rep(table.concat(t), ms // 100)
    local function u32(x) return string.char(x % 256, (x // 256) % 256, (x // 65536) % 256, (x // 16777216) % 256) end
    local function u16(x) return string.char(x % 256, x // 256) end
    local wav = "RIFF" .. u32(36 + #body) .. "WAVEfmt " .. u32(16) .. u16(1) .. u16(1) .. u32(M.RATE) .. u32(M.RATE * 2) .. u16(2) .. u16(16) .. "data" .. u32(#body) .. body
    if not io.writeFile(path, wav) then return nil end
    beep_key = key
    return path
end

-- 校验并裁剪参数；返回 plan 或 nil, reason
function M.plan(a)
    if type(a) ~= "table" then return nil, "invalid_args" end
    local vol = a.volume == nil and 50 or a.volume
    if type(vol) ~= "number" or vol ~= vol or vol < 0 or vol > 100 then return nil, "invalid_args" end
    local p = { kind = a.kind, volume = math.floor(math.min(vol, max_volume())), clamped = vol > max_volume() }
    if a.kind == "beep" or a.kind == "test" then
        local f = a.kind == "test" and 1000 or a.freq_hz
        local ms = a.kind == "test" and 500 or a.duration_ms
        if type(f) ~= "number" or f ~= f or f < 100 or f > 8000 or type(ms) ~= "number" or ms ~= ms or ms < 100 or ms > M.MAX_MS then return nil, "invalid_args" end
        p.freq_hz = math.min(7000, math.max(100, math.floor(f / 10 + 0.5) * 10))
        p.duration_ms = math.min(M.BEEP_MAX_MS, math.floor(ms / 100) * 100)
        if p.freq_hz ~= f or p.duration_ms ~= ms then p.clamped = true end
    elseif a.kind == "tts" then
        if type(a.text) ~= "string" or #a.text == 0 or #a.text > 180 then return nil, "invalid_args" end
        p.text = a.text
    elseif a.kind == "file" then
        if type(a.name) ~= "string" or #a.name > 32 or not a.name:match("^[%w_.-]+$") then return nil, "invalid_args" end
        p.path = io.exists("/luadb/" .. a.name) and ("/luadb/" .. a.name) or (io.exists("/" .. a.name) and ("/" .. a.name) or nil)
        if not p.path then return nil, "invalid_args" end
    else
        return nil, "unsupported"      -- meow：还没有真实音效文件，不拿别的声音冒充
    end
    return p
end

function M.check_allowed()
    if busy then return "busy" end
    if S.battery and S.battery.ready and S.battery.pct and S.battery.pct < cfg.low_battery_pct then return "low_battery" end
end

-- 须在 task 内调用；返回 ok, reason, applied_args
function M.play(a)
    local p, why = M.plan(a); if not p then return false, why end
    why = M.check_allowed(); if why then return false, why end
    busy, cancelled = true, false
    local ok, result, reason = pcall(function()
        local ready, e = setup(); if not ready then return false, e end
        local content, ptype, wait_ms
        if p.kind == "tts" then content, ptype, wait_ms = p.text, 1, M.MAX_MS
        elseif p.kind == "file" then content, ptype, wait_ms = p.path, 0, M.MAX_MS
        else
            content = beep_file(p.freq_hz, p.duration_ms); ptype, wait_ms = 0, p.duration_ms + 3000
            if not content then return false, "storage_failed" end
        end
        ex.vol(p.volume)
        current_type = ptype
        local topic = "PP_AUDIO_DONE"
        if not ex.play_start({ type = ptype, content = content, cbfnc = function(ev) sys.publish(topic, ev) end }) then return false, "execution_failed" end
        S.outputs.speaker_on = true
        local done = sys.waitUntil(topic, wait_ms)
        pcall(ex.play_stop, { type = ptype })
        if cancelled then return false, "cancelled" end
        if not done then log.warn("audio", "no PLAY_DONE within", wait_ms, "ms; stopped") end
        return true
    end)
    S.outputs.speaker_on = false
    busy, current_type = false, nil
    if not ok then log.error("audio", result); return false, "execution_failed" end
    local applied = { kind = p.kind, volume = p.volume, freq_hz = p.freq_hz, duration_ms = p.duration_ms }
    if result then return true, p.clamped and "limit_clamped" or nil, applied end
    return false, reason, applied
end

-- 任何时候都可调用（STOP / 命令台 stop）
function M.stop()
    if busy and ex then
        cancelled = true
        pcall(ex.play_stop, { type = current_type or 0 })
        sys.publish("PP_AUDIO_DONE", "stopped")
    end
    S.outputs.speaker_on = false
end

sys.subscribe("MODE_CHANGED", function(mode) if mode == "low_power" then M.stop() end end)
_G.AUDIO = M
return M
