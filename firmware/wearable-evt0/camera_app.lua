-- Fresh, on-demand JPEG frames for the unchanged iOS MJPEG view.
-- GPIO wiring follows the official Air8201G + BTB AirCAMERA_1040/1050 demo.
-- 2026-09-20 提速：连拍期间传感器保持打开（空闲 IDLE_CLOSE_MS 后断电释放 I2C1）；最多保留 2 帧
-- （一帧在传、一帧预取）；二进制窗口读 slice() 供 console 的 camera read；画质/裁剪/校验算法可运行时配置。
local C=_G.CFG.camera or {}
local M={MAX_BYTES=262144,CHUNK_BYTES=1024,MAX_READ=16384,IDLE_CLOSE_MS=6000,FRAME_TTL_MS=20000,tx_busy=false}
local frames,order={},{}            -- id -> {data=string,expires=ticks}
local busy,ex,model,idle_timer=false,nil,nil,nil
local opt={quality=1,sum="adler32"} -- camera config quality=N sum=adler32|crc32 x= y= w= h= | crop=off
local function valid_id(s) return type(s)=="string" and #s>=8 and #s<=64 and s:match("^[%w%-]+$") end
local function off()
    gpio.set(22,0); gpio.set(5,1)
end
local function close_sensor()
    if ex then pcall(ex.close,false) else pcall(i2c.close,1) end
    ex,model=nil,nil; off()
    if _G.GNSS then _G.GNSS.resume() end   -- 摄像头空闲关闭后 GNSS 恢复
    if _G.GSENSOR then _G.GSENSOR.resume() end   -- I2C1 让回给 DA267
end
local function drop(fid)
    frames[fid]=nil
    for i=#order,1,-1 do if order[i]==fid then table.remove(order,i) end end
end
local function live(fid)
    local f=frames[fid]
    if f and mcu.ticks()>f.expires then drop(fid); f=nil end
    return f
end
local function checksum(s)
    if opt.sum=="crc32" and crypto and crypto.crc32 then return string.format("%08x",crypto.crc32(s)&0xFFFFFFFF),"crc32" end
    local a,b=1,0
    for n=1,#s do a=(a+s:byte(n))%65521; b=(b+a)%65521 end
    return string.format("%08x",b*65536+a),"adler32"
end
local function open_sensor()
    if _G.GNSS then _G.GNSS.pause("camera") end   -- 摄像头与 GNSS 二选一，避免 USB 实况卡顿
    if _G.GSENSOR then _G.GSENSOR.pause("camera") end   -- 共用 I2C1：先断开 DA267
    local probe
    local ok,err=pcall(function()
        gpio.setup(28,1); gpio.setup(24,1); gpio.setup(26,1)
        gpio.setup(22,1); gpio.setup(5,0); sys.wait(30)
        -- Provide the sensor MCLK before SCCB ID reads (same SPI format for both official sensors).
        probe=camera.init(1,24000000,1,1,2,1,0x00010101,0,0,640,480)
        if not probe then error("camera_clock_init_failed") end
        sys.wait(30)
        if not i2c.setup(1,i2c.FAST) then error("camera_i2c_setup_failed") end
        local function read(reg)
            if not i2c.send(1,0x21,string.char(reg)) then return nil end
            local s=i2c.recv(1,0x21,1); return type(s)=="string" and #s==1 and s:byte() or nil
        end
        local hi,lo=read(0xf0),read(0xf1)
        if hi==0x23 and lo==0x2a then model="gc032a"
        elseif hi==0xa3 and lo==0x10 then model="gc0310"
        else error("unsupported_camera_id_"..tostring(hi).."_"..tostring(lo)) end
        camera.close(probe); probe=nil
        local e=require("excamera")
        if not e.open({id=model,i2c_id=1,work_mode=0,save_path="ZBUFF",camera_pwr=22,camera_pwdn=5}) then error("camera_open_failed") end
        ex=e
    end)
    if probe then pcall(camera.close,probe) end
    if not ok then error(err,0) end
end
function M.release(wanted)
    if not frames[wanted] then return false,"wrong_frame" end
    drop(wanted)
    return true
end
function M.config(kv)
    local n={quality=opt.quality,sum=opt.sum,x=opt.x,y=opt.y,w=opt.w,h=opt.h}
    for k,v in pairs(kv) do
        if k=="crop" and v=="off" then n.x,n.y,n.w,n.h=nil,nil,nil,nil
        elseif k=="sum" and (v=="adler32" or v=="crc32") then n.sum=v
        elseif k=="quality" or k=="x" or k=="y" or k=="w" or k=="h" then
            local i=tonumber(v or "")
            if not i or i%1~=0 or i<0 or i>640 or (k=="quality" and (i<1 or i>100)) or ((k=="w" or k=="h") and i<16) then return nil,"invalid_"..k end
            n[k]=i
        else return nil,"unknown_option_"..tostring(k) end
    end
    if (n.x or n.y or n.w or n.h) and not (n.x and n.y and n.w and n.h and n.x+n.w<=640 and n.y+n.h<=480) then return nil,"invalid_crop" end
    opt=n
    return string.format("quality=%d sum=%s crop=%s",opt.quality,opt.sum,opt.w and (opt.x..","..opt.y..","..opt.w..","..opt.h) or "off")
end
function M.capture(wanted,reply)
    if not valid_id(wanted) then return false,"invalid_frame_id" end
    if busy then return false,"camera_busy" end
    if C.board~="Air8201G_BTB_V1.4" then return false,"camera_wiring_unverified" end
    if not camera then return false,"camera_core_unavailable" end
    busy=true
    sys.taskInit(function()
        local t0=mcu.ticks()
        local ok,err=pcall(function()
            if not ex then open_sensor() end
            local t1=mcu.ticks()
            local result,data=ex.photo(opt.x,opt.y,opt.w,opt.h,opt.quality)
            if not result or type(data)~="userdata" then error("camera_capture_failed") end
            local bytes=data:used()
            if bytes<4 or bytes>M.MAX_BYTES then error("camera_frame_size_limit") end
            local s=data:query(0,bytes)
            if s:sub(1,2)~="\255\216" or s:sub(-2)~="\255\217" then error("camera_invalid_jpeg") end
            local sum,algo=checksum(s)
            while #order>=2 do drop(order[1]) end -- 只留一帧在传 + 本帧
            frames[wanted]={data=s,expires=mcu.ticks()+M.FRAME_TTL_MS}; order[#order+1]=wanted
            _G.STATE.camera={ready=true,model=model,frame_bytes=#s}
            log.info("camera","frame",#s,"open_ms",t1-t0,"photo_ms",mcu.ticks()-t1)
            reply("frame "..wanted.." "..#s.." "..sum..(algo=="crc32" and " crc32" or ""))
        end)
        if not ok then
            -- Any failure powers the sensor down; the next capture re-probes from scratch.
            close_sensor()
            _G.STATE.camera={ready=false,error=tostring(err):match("([^:]+)$")}
        end
        busy=false
        if idle_timer then sys.timerStop(idle_timer) end
        -- Free sensor/JPEG buffers once the stream goes idle; only bounded JPEG bytes remain in RAM.
        idle_timer=sys.timerStart(function() idle_timer=nil; if not busy then close_sensor() end end,M.IDLE_CLOSE_MS)
        if not ok then reply("err camera "..wanted.." "..tostring(_G.STATE.camera.error)) end
    end)
    return true
end
local function checked(wanted,offset)
    local f=live(wanted)
    if not f then return nil,"frame_expired" end
    if type(offset)~="number" or offset%1~=0 or offset<0 or offset>=#f.data then return nil,"invalid_offset" end
    f.expires=mcu.ticks()+M.FRAME_TTL_MS
    return f
end
function M.chunk(wanted,offset)
    local f,e=checked(wanted,offset)
    if not f then return nil,e end
    local s=f.data:sub(offset+1,offset+M.CHUNK_BYTES)
    return "jpeg "..wanted.." "..offset.." "..(s:gsub(".",function(c) return string.format("%02x",c:byte()) end))
end
-- Raw bytes for the binary window transfer (console: camera read <id> <offset> <len>).
function M.slice(wanted,offset,len)
    local f,e=checked(wanted,offset)
    if not f then return nil,e end
    if type(len)~="number" or len%1~=0 or len<1 or len>M.MAX_READ then return nil,"invalid_length" end
    return f.data:sub(offset+1,offset+len)
end
sys.timerLoopStart(function() for i=#order,1,-1 do live(order[i]) end end,1000)
_G.CAMERA=M
return M
