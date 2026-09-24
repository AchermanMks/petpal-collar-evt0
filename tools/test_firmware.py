"""Execute production Lua modules against deterministic hardware mocks (not hardware acceptance)."""
from pathlib import Path
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().firmware_path = str(ROOT / "firmware/wearable-evt0")
lua.execute(r'''
package.path=firmware_path.."/?.lua;"..package.path
local tick,epoch=0,1700000100
local kv,blobs={},{}
local function copy(t)
    if type(t)~="table" then return t end
    local out={}; for k,v in pairs(t) do out[k]=copy(v) end; return out
end
json={null="NULL",encode=function(t) local k="json"..tostring(#blobs+1); blobs[#blobs+1]=copy(t); return k end,
    decode=function(k) return copy(blobs[tonumber(k:match("json(%d+)"))]) end}
local _tn=tonumber; tonumber=function(v,b) if v==nil then error("bad argument #1 to 'tonumber' (value expected)",2) end; if b then return _tn(v,b) end; return _tn(v) end -- 实板 LuatOS V2030：tonumber(nil) 直接报错（2026-09-20 板1实测）
fskv={get=function(k) if kv[k]==nil then return end; return kv[k] end, -- 实板：键不存在时无返回值（不是 nil），tonumber()/type() 直接包它会报错
set=function(k,v) if _G.write_fail then return false end; kv[k]=v; return true end,
    del=function(k) if _G.write_fail then return false end; kv[k]=nil; return true end}
local tasks,events,subs,timers={},{},{},{}
sys={timerLoopStart=function() end, subscribe=function(k,f) subs[k]=subs[k] or {}; table.insert(subs[k],f) end,
    timerStart=function(f,ms) timers[#timers+1]={f=f,ms=ms} end,
    publish=function(k,v) events[#events+1]={type=k,data=copy(v)}; for _,f in ipairs(subs[k] or {}) do f(v) end end,
    taskInit=function(f) tasks[#tasks+1]=coroutine.create(f) end, wait=function(ms) coroutine.yield(ms) end}
local function step()
    for i=#tasks,1,-1 do
        local ok,ms=coroutine.resume(tasks[i]); assert(ok,ms)
        if coroutine.status(tasks[i])=="dead" then table.remove(tasks,i) else tick=tick+(ms or 0) end
    end
end
local function drain() local n=0; while #tasks>0 do step(); n=n+1; assert(n<10000,"scheduler stuck") end end
mcu={ticks=function() return tick end}
os.time=function() return epoch+math.floor(tick/1000) end
os.date=function() return "2026-09-16" end
local outputs,writes={},{}
gpio={setup=function(p,v) outputs[p]=v; writes[#writes+1]={p=p,v=v} end,
    set=function(p,v) outputs[p]=v; writes[#writes+1]={p=p,v=v} end}
log={info=function() end,warn=function() end,error=function() end}
CFG={device_id="collar-evt-001",low_battery_pct=15,gsensor={motion_timeout_s=10},
    actuator={led_gpio=16,led_on_level=1,motor_gpio=27,motor_on_level=1,motor_verified=false},outbox={max_records=8}}
STATE={mode="routine",seq=0,boot_count=0,battery={ready=false,charging=false},motion={ready=false,state="still",steps=0},gnss={ready=false}}
local R=require("runtime_app")
local ACT=require("actuator_app")
assert(outputs[16]==0 and outputs[27]==nil,"unverified GPIO touched")
assert(ACT.check_allowed()=="hardware_unverified")
CFG.actuator.motor_verified=true
CFG.actuator.motor_gpio=26; assert(ACT.check_allowed()=="hardware_unverified","GPIO26 powers the I2C1 bus on this board"); ACT.stop_motor(); assert(outputs[26]==nil)
CFG.actuator.motor_gpio=27
assert(ACT.check_allowed()=="battery_unknown")
STATE.battery={ready=true,pct=80,charging=false}
assert(ACT.check_allowed()=="temperature_unknown")
STATE.battery.temp_c=25
local a=ACT.clamp_vibrate({duration_ms=100000,count=100000}); assert(a.duration_ms==500 and a.count==3)
assert(ACT.clamp_vibrate({duration_ms=0/0})==nil)
assert(ACT.clamp_vibrate({count="3"})==nil)
sys.taskInit(function() assert(ACT.vibrate({duration_ms=200,count=2})) end)
step(); assert(ACT.check_allowed()=="busy"); drain(); assert(outputs[27]==0 and ACT.check_allowed()=="cooldown")
tick=tick+30000; STATE.battery.charging=true; assert(ACT.check_allowed()=="charging")
CFG.actuator.bench_allow_charging=true; assert(ACT.check_allowed()==nil,"bench override"); CFG.actuator.bench_allow_charging=nil
STATE.battery.charging=false; STATE.battery.pct=5; assert(ACT.check_allowed()=="low_battery")
STATE.battery.pct=80; STATE.battery.temp_c=46; assert(ACT.check_allowed()=="over_temp"); STATE.battery.temp_c=25
sys.taskInit(function() local ok,e=ACT.vibrate({duration_ms=500,count=3}); assert(not ok and e=="cancelled") end)
step(); ACT.stop_motor(); drain(); assert(outputs[27]==0)
assert(ACT.COOLDOWN_S==30,"wearable default stays 30 s")
-- bench profile may shorten the interval, never below 3 s
package.loaded.actuator_app=nil; CFG.actuator.cooldown_s=5; assert(require("actuator_app").COOLDOWN_S==5)
package.loaded.actuator_app=nil; CFG.actuator.cooldown_s=0; assert(require("actuator_app").COOLDOWN_S==3)
package.loaded.actuator_app=nil; CFG.actuator.cooldown_s=nil; ACT=require("actuator_app"); assert(ACT.COOLDOWN_S==30)
sys.taskInit(function() local ok,e=ACT.led("blink",30); assert(not ok and e=="cancelled") end)
step(); ACT.led("off",0); drain(); assert(outputs[16]==0)
assert(ACT.led("on",300) and STATE.outputs.led_on and outputs[16]==1)
local first=timers[#timers]; assert(first.ms==300000)
assert(ACT.led("off",0) and not STATE.outputs.led_on)
assert(ACT.led("on",5)); first.f(); assert(STATE.outputs.led_on,"obsolete timer switched off new command")
-- breathe = software PWM: LED on-fraction must be ~5% at the start of the 3 s period and ~100% in the middle, ending with LED off.
-- In this scheduler each step() yields the next wait, so "state after step" holds for (tick_after - tick_before).
outputs[16]=0; tick=0
sys.taskInit(function() assert(ACT.led("breathe",3)) end)
local on_early,tot_early,on_mid,tot_mid=0,0,0,0
local n=0
while #tasks>0 and n<5000 do
    local t=tick; step(); n=n+1
    local dur=tick-t; local st=outputs[16]
    if t<200 then tot_early=tot_early+dur; if st==1 then on_early=on_early+dur end
    elseif t>1300 and t<1700 then tot_mid=tot_mid+dur; if st==1 then on_mid=on_mid+dur end end
end
assert(#tasks==0 and outputs[16]==0,"breathe ended with LED off")
assert(tot_early>0 and tot_mid>0 and on_early/tot_early<0.15 and on_mid/tot_mid>0.9,string.format("breathe duty early=%.2f mid=%.2f",on_early/tot_early,on_mid/tot_mid))
timers[#timers].f(); assert(not STATE.outputs.led_on and outputs[16]==0)
assert(not STATE.outputs.motor_on)
assert(R.set_mode("lost",60)); assert(STATE.mode=="lost")
STATE.battery.charging=true; R.refresh_mode(); assert(STATE.mode=="charging")
STATE.battery.charging=false; R.refresh_mode(); assert(STATE.mode=="lost","charging overwrote lost request")
tick=tick+60001; R.refresh_mode(); assert(STATE.mode=="routine")
assert(not R.set_mode("lost",math.huge))
assert(R.set_fence({enabled=true,lat=0,lng=0,radius_m=100}))
local p={source="gnss",lat=.01,lng=0,accuracy_m=10}
R.position(p); R.position(p)
local exits=0; for _,e in ipairs(events) do if e.type=="PETPAL_EVENT" and e.data.type=="geofence_exit" then exits=exits+1 end end
assert(exits==1); R.position(p); assert(exits==1)
assert(R.set_fence({enabled=false})); assert(json.decode(kv.pp_fence).enabled==false)
local Q=require("outbox_app")
for i=1,8 do assert(Q.push("/telemetry","sample"..i)) end
assert(not Q.push("/ack","overflow")); local oldest=Q.oldest()
_G.write_fail=true; assert(not Q.confirm(oldest)); assert(Q.depth()==8); _G.write_fail=false
package.loaded.outbox_app=nil; Q=require("outbox_app"); assert(Q.depth()==8 and Q.oldest().replayed)
assert(Q.confirm(Q.oldest())); assert(Q.depth()==7)
local C=require("command_app")
local replies={}; local function reply(a) replies[#replies+1]=copy(a); return true end
local function cmd(id,kind,args) return {id=id,type=kind,args=args,issued_at=os.time(),expires_at=os.time()+120} end
assert(C.validate({id="12345678",type="GET_STATE"})=="invalid_time")
local expired=cmd("expired1","GET_STATE"); expired.expires_at=os.time()-1; assert(C.validate(expired)=="expired")
assert(C.validate(cmd("missing1","BUZZ"))=="unsupported")
local c=cmd("test-id1","SET_MODE",{mode="lost",ttl_s=60}); assert(C.handle(c,reply)); drain()
assert(replies[#replies].status=="executed")
local event_count=#events; assert(not C.handle(c,reply)); drain(); assert(#events==event_count,"duplicate executed")
package.loaded.command_app=nil; C=require("command_app"); assert(not C.handle(c,reply)); assert(replies[#replies].status=="executed")
_G.write_fail=true; assert(not C.handle(cmd("test-id2","SET_MODE",{mode="routine"}),reply)); assert(STATE.mode=="lost"); _G.write_fail=false
epoch=0; assert(C.validate(cmd("test-id3","GET_STATE"))=="clock_unsynced"); epoch=1700000100
local activity=require("activity_app"); local before=STATE.motion.steps
for i=1,100 do activity.sample(0,0,1,tick+i*100) end
assert(STATE.motion.steps==before,"stationary samples counted as steps")
for i=1,100 do activity.sample(0,0,i%10<2 and 1.7 or 1,tick+10000+i*100) end
assert(STATE.motion.steps>before and STATE.motion.active_s>0)
-- Verify API coordinate mode and fields against the current official library contract.
local configured
package.loaded.exgnss={TIMERORSUC=2,setup=function(t) configured=t end,is_fix=function() return true end,
    rmc=function(mode) assert(mode==2); return {lat=31.23,lng=121.47,speed=2} end,
    gga=function(mode) assert(mode==2); return {satellites_tracked=12,altitude=8,hdop=1.2} end,
    open=function(_,t) t.cb() end,close=function() end}
CFG.gnss={mode=1,nmea_debug=false,agps=false,uart_id=2,power_gpio=21,timeout_s=90}
sys.waitUntil=function() return true end
sys.taskInit=function() end -- periodic board job not part of this unit test
local gnss=require("gnss_app"); assert(gnss.locate(60))
assert(STATE.position.lat==31.23 and STATE.position.lng==121.47 and STATE.position.sats==12)
assert(math.abs(STATE.position.speed_kmh-3.704)<.001 and configured.agps_enable==false and configured.gnss_volgpio==21)
assert(STATE.gnss.fix==true and STATE.last_fix.tick~=nil and STATE.gnss.ttff_s~=nil)
-- Tracking mode (bench): GNSS stays on, 1 Hz polling; real libgnss returns nil / partial tables before a fix.
package.loaded.gnss_app=nil
local fixed,track_task,opened=false,nil,nil
package.loaded.exgnss={DEFAULT=1,TIMERORSUC=2,setup=function() end,is_fix=function() return fixed end,
    rmc=function() if not fixed then return nil end; return {lat=22.54,lng=114.05} end,  -- no speed field
    gga=function() if not fixed then error("no gga yet") end; return {satellites_tracked=7} end,   -- no hdop field at all
    gsv=function() return {total_sats=9,sats={{snr=31},{snr=0},{snr=18},{}}} end,
    open=function(mode,t) opened={mode,t.tag} end,close=function() end}
CFG.gnss={mode=1,nmea_debug=false,agps=false,uart_id=2,power_gpio=21,timeout_s=90,tracking=true}
STATE.position=nil; STATE.gnss={ready=false}
local waits=0
sys.taskInit=function(f) track_task=coroutine.create(f) end
sys.wait=function() waits=waits+1; tick=tick+1000; coroutine.yield() end
gnss=require("gnss_app"); coroutine.resume(track_task)
assert(opened[1]==1 and opened[2]=="petpal_track" and STATE.gnss.tracking==true)
for i=1,3 do assert(coroutine.resume(track_task)) end
assert(STATE.position==nil and STATE.gnss.fix==false)
local g=gnss.status(); assert(g.sats_in_view==9 and g.sats_with_signal==2 and g.snr_max==31)
fixed=true; assert(coroutine.resume(track_task))
assert(STATE.position.lat==22.54 and STATE.position.sats==7 and STATE.position.speed_kmh==0 and STATE.position.alt_m==0)
assert(STATE.position.accuracy_m==nil,"no hdop means no accuracy estimate")
assert(STATE.gnss.fix==true and STATE.gnss.ttff_s>=3)
fixed=false; for i=1,8 do assert(coroutine.resume(track_task)) end
assert(STATE.gnss.fix==false and STATE.position.lat==22.54,"lost fix keeps last position, flagged not fixed")
assert(gnss.locate()==false)
-- quality gate + stationary averaging
gnss.filter_reset(); STATE.gnss.filter.gated=0
local base={source="gnss",lat=22.5400,lng=114.0500,hdop=1.0,sats=8,speed_kmh=0,alt_m=10,accuracy_m=10}
local function fixat(dlat,dlng,extra) local r={}; for k,v in pairs(base) do r[k]=v end; r.lat=r.lat+dlat; r.lng=r.lng+dlng; for k,v in pairs(extra or {}) do r[k]=v end; return r end
assert(gnss.filter(fixat(0,0,{sats=4}))==nil and STATE.gnss.filter.gated==1,"few sats gated")
assert(gnss.filter(fixat(0,0,{hdop=3.1}))==nil and STATE.gnss.filter.gated==2,"bad hdop gated")
local p1=gnss.filter(fixat(0,0)); assert(p1 and p1.averaged_n==nil,"first point raw")
local p2=gnss.filter(fixat(0.00002,0)); assert(p2.averaged_n==nil,"needs 3 points before averaging")
local p3=gnss.filter(fixat(-0.00002,0.00002)); assert(p3.averaged_n==3 and math.abs(p3.lat-22.54)<1e-9 and math.abs(p3.lng-(114.05+0.00002/3))<1e-9 and p3.accuracy_m<10 and p3.speed_kmh==0,"3 still points averaged")
for i=1,10 do gnss.filter(fixat(0.00001*(i%2),0)) end; assert(STATE.gnss.filter.window==8,"window capped at avg_n")
local mv=gnss.filter(fixat(0.0020,0)); assert(mv.averaged_n==nil and STATE.gnss.filter.window==0 and STATE.gnss.filter.averaged==false,"a 200 m jump resets to raw immediately")
local sp=gnss.filter(fixat(0.0020,0,{speed_kmh=6})); assert(sp.averaged_n==nil,"speed > still_kmh -> raw")
-- camera/GNSS exclusion: pause closes the tracking app and drops the fix flag, resume reopens it; position is kept
local closed; package.loaded.exgnss.close=function(mode,t) closed={mode,t.tag} end; opened=nil
gnss.pause("camera"); assert(closed[1]==1 and closed[2]=="petpal_track" and STATE.gnss.paused=="camera" and STATE.gnss.fix==false and STATE.position.lat==22.54)
fixed=true; assert(coroutine.resume(track_task)); assert(STATE.gnss.fix==false,"paused loop must not read the receiver")
assert(gnss.locate()==false); gnss.pause("camera"); assert(opened==nil)
gnss.resume(); assert(opened[1]==1 and opened[2]=="petpal_track" and STATE.gnss.paused==nil); gnss.resume()
assert(coroutine.resume(track_task)); assert(STATE.gnss.fix==true)

-- G-sensor lifecycle with a mocked DA267 on I2C1: WHO_AM_I, 10 Hz reads via readReg with ~30% NACK, pause/resume around the camera
local pins,regs,nack,reads_done={}, {}, false, 0
gpio.setup=function(p,v) pins[p]=v end; gpio.debounce=function() end
i2c={SLOW=0,FAST=1,setup=function() return true end,close=function() end,send=function(_,_,t) if type(t)=="table" then regs[t[1]]=t[2] end; return true end,
     readReg=function(_,_,reg,n) reads_done=reads_done+1; if nack and reads_done%3==0 then return nil end; if reg==0x01 then return "\19" end; return string.rep("\0",n) end}
CFG.gsensor={i2c_id=1,addr=0x26,power_gpio=24,pullup_gpio=28,bus_power_gpio=26,int_gpio=20,threshold=0x20,motion_timeout_s=10}
STATE.motion={ready=false,state="still",steps=0}
local gs_task; sys.taskInit=function(f) gs_task=coroutine.create(f) end
local GS=require("gsensor_app")
local function run(n) for i=1,n do if coroutine.status(gs_task)=="suspended" then assert(coroutine.resume(gs_task)) end end end
run(4); assert(STATE.motion.ready==true and pins[24]==1 and pins[28]==1 and pins[26]==1 and regs[0x11]==0x30,"DA267 initialised with I2C1 bus power")
nack=true; run(30)
assert(STATE.motion.ready==true and STATE.motion.read_fails==0 and STATE.motion.reads>=30,"a single NACK is retried, not counted: "..tostring(STATE.motion.read_fails))
GS.pause("camera"); assert(pins[24]==0 and pins[28]==0 and pins[26]==1 and STATE.motion.ready==false and STATE.motion.paused=="camera","bus power stays for the camera")
run(1); assert(coroutine.status(gs_task)=="dead","paused loop exits")
nack=false; GS.resume(); run(4); assert(STATE.motion.ready==true and pins[24]==1 and STATE.motion.paused==nil)
GS.resume(); GS.pause("camera"); GS.pause("camera")  -- idempotent
-- sustained failure marks data stale
GS.resume(); run(4); i2c.readReg=function() reads_done=reads_done+1; return nil end
run(25); assert(STATE.motion.ready==false,"20 consecutive failures -> not ready")
assert(GS.tune("fast","1") and CFG.gsensor.i2c_fast==true and STATE.motion.reads==0); assert(not GS.tune("sample","5"))
print("PASS: GPIO defaults; finite limits; busy/cooldown; charge/low/temp guards; cancel; mode TTL; fence; durable queue; command expiry/dedup/reboot/storage; activity; gnss one-shot + tracking; gsensor init/NACK/pause/resume")
''')
