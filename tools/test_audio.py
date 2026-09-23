"""audio_app + console `audio`/`time` with a mocked exaudio. Synthetic only; not board acceptance."""
import io, unittest, wave
from pathlib import Path
from lupa import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]
PRELUDE=r'''
package.path=firmware_path.."/?.lua;"..firmware_path.."/libs/?.lua;"..package.path
local _tn=tonumber; tonumber=function(v,b) if v==nil then error("bad argument #1 to 'tonumber' (value expected)",2) end; if b then return _tn(v,b) end; return _tn(v) end
files={}; tick=0; played={}; stopped=0; vol=nil; subs={}; tasks={}; setup_modes={}
CFG={low_battery_pct=15,audio={max_volume=60},features={}}
STATE={battery={ready=true,pct=80,charging=false}}
io.exists=function(p) return files[p]~=nil end
io.writeFile=function(p,d) files[p]=d; return true end
rtos={version=function() return "V2030" end}
mcu={ticks=function() return tick end}
log={info=function() end,warn=function() end,error=function() end}
waiting=nil
sys={subscribe=function(k,f) subs[k]=f end,
     publish=function(topic,ev) if waiting and waiting.topic==topic then local w=waiting; waiting=nil; w.result={true,ev} end end,
     waitUntil=function(topic,ms) waiting={topic=topic}; local w=waiting; coroutine.yield(); if w.result then return true,w.result[2] end; return false end,
     taskInit=function(f) tasks[#tasks+1]=coroutine.create(f) end,timerStart=function() end}
fail_new=false
audio={}  -- mock core ships the classic audio library (like V2030_1), no audio_v2
package.loaded.exaudio={PLAY_DONE=1,
    setup=function(t) setup_modes[#setup_modes+1]=t.audio_mode; assert(t.model=="es8311" and t.i2c_id==0 and t.pa_ctrl==25 and t.dac_ctrl==2 and t.dac_delay==6); return not (fail_new and t.audio_mode=="new") end,
    vol=function(v) vol=v end,
    play_start=function(t) played[#played+1]=t; cb=t.cbfnc; return true end,
    play_stop=function() stopped=stopped+1 end}
'''

def u(src): return src.encode('utf-8').decode('latin-1')  # runtime is latin-1 (byte transparent) so WAV bytes survive

class Tests(unittest.TestCase):
    def lua(self):
        L=LuaRuntime(unpack_returned_tuples=True,encoding='latin-1')
        L.globals().firmware_path=str(ROOT/'firmware/wearable-evt0'); L.execute(PRELUDE)
        return L
    def test_plan_limits(self):
        L=self.lua(); L.execute(u(r'''
            local A=require("audio_app")
            local p=A.plan({kind="beep",freq_hz=1234,duration_ms=9999,volume=100})
            assert(p.volume==60 and p.freq_hz==1230 and p.duration_ms==3000 and p.clamped)
            p=A.plan({kind="beep",freq_hz=1000,duration_ms=500}); assert(p.volume==50 and not p.clamped)
            for _,bad in ipairs({{kind="beep",freq_hz=50,duration_ms=500},{kind="beep",freq_hz=1000,duration_ms=20000},{kind="beep"},
                {kind="tts",text=""},{kind="tts",text=string.rep("x",181)},{kind="file",name="../etc"},{kind="file",name="missing.mp3"},{kind="beep",freq_hz=1000,duration_ms=500,volume=101}}) do
                local ok,e=A.plan(bad); assert(not ok and e=="invalid_args",e) end
            local ok,e=A.plan({kind="meow"}); assert(not ok and e=="unsupported")   -- no real asset yet: never substitute another sound
            files["/luadb/ding.mp3"]="x"; assert(A.plan({kind="file",name="ding.mp3"}).path=="/luadb/ding.mp3")
            assert(STATE.outputs.speaker_on==false and STATE.audio.ready==false)
        '''))
    def test_beep_wav_and_completion(self):
        L=self.lua(); L.execute(u(r'''
            A=require("audio_app")
            co=coroutine.create(function() r={A.play({kind="beep",freq_hz=2000,duration_ms=300,volume=90})} end)
            assert(coroutine.resume(co))
            assert(STATE.outputs.speaker_on==true and vol==60 and played[1].type==0 and played[1].content=="/pp_beep.wav")
            local ok,e=A.play({kind="test"}); assert(not ok and e=="busy")
            cb(1); assert(coroutine.resume(co))
            assert(r[1]==true and r[2]=="limit_clamped" and r[3].volume==60 and STATE.outputs.speaker_on==false and stopped==1 and STATE.audio.ready)
        '''))
        data=L.eval('files["/pp_beep.wav"]').encode('latin-1')
        with wave.open(io.BytesIO(data)) as w:
            self.assertEqual((w.getnchannels(),w.getsampwidth(),w.getframerate(),w.getnframes()),(1,2,16000,4800))
            frames=w.readframes(4800)
        samples=[int.from_bytes(frames[i:i+2],'little',signed=True) for i in range(0,len(frames),2)]
        self.assertLessEqual(max(map(abs,samples)),9000); self.assertGreater(max(samples),8000)
        crossings=sum(1 for a,b in zip(samples,samples[1:]) if a<0<=b)
        self.assertAlmostEqual(crossings,600,delta=2)  # 2000 Hz for 0.3 s
        self.assertEqual(samples[:1600],samples[1600:3200])  # 100 ms blocks join without a phase jump
    def test_stop_cancels_and_low_battery(self):
        L=self.lua(); L.execute(u(r'''
            local A=require("audio_app")
            local r; local co=coroutine.create(function() r={A.play({kind="tts",text="你好",volume=30})} end)
            assert(coroutine.resume(co)); assert(played[1].type==1 and played[1].content=="你好" and vol==30)
            A.stop(); assert(coroutine.resume(co))
            assert(r[1]==false and r[2]=="cancelled" and STATE.outputs.speaker_on==false)
            STATE.battery.pct=5; local ok,e=A.play({kind="test"}); assert(not ok and e=="low_battery")
            A.stop() -- idle stop is harmless
        '''))
    def test_framework_is_chosen_by_core_capability(self):
        # Real board (V2030_1): no audio_v2 lib. Asking exaudio for "new" even once breaks it for good, so it must never be tried.
        L=self.lua(); L.execute(u(r'''
            audio={}; local A=require("audio_app")
            local co=coroutine.create(function() A.play({kind="test"}) end); assert(coroutine.resume(co))
            assert(#setup_modes==1 and setup_modes[1]=="old" and STATE.audio.mode=="old" and STATE.audio.ready)
        '''))
        L=self.lua(); L.execute(u(r'''
            audio_v2={}; audio={}; local A=require("audio_app")
            local co=coroutine.create(function() A.play({kind="test"}) end); assert(coroutine.resume(co))
            assert(#setup_modes==1 and setup_modes[1]=="new")
        '''))
        L=self.lua(); L.execute(u(r'''
            audio=nil; local A=require("audio_app")   -- core without any audio library
            local r; local co=coroutine.create(function() r={A.play({kind="test"})} end); assert(coroutine.resume(co))
            assert(r[1]==false and r[2]=="unsupported" and #setup_modes==0 and STATE.audio.error=="core_has_no_audio_lib")
        '''))
    def test_console_audio_and_time(self):
        L=self.lua(); L.execute(u(r'''
            PROJECT="petpal_evt0"; VERSION="001.000.003"
            local written,rx,on_rx={}, "", nil
            uart={VUART_0=9,setup=function() end,on=function(_,_,f) on_rx=f end,read=function() local s=rx; rx=""; return s end,
                write=function(_,s) written[#written+1]=s; return #s end}
            json={encode=function() return "{}" end,decode=function() return {} end}
            local now=100; os.time=function() return now end
            rtc={set=function(t) assert(t.year==2026 and t.mon==9 and t.day==21); now=1790000000; return true end}
            PETPAL={clock_valid=function() return now>=1700000000 end}
            require("audio_app"); require("console_app")
            local function cmd(s) rx=s.."\n"; on_rx(); return written[#written] end
            assert(cmd("time abc"):match("^err time invalid") and cmd("time 5"):match("^err time invalid"))
            assert(cmd("time 1790000000"):match("^ok time set 1790000000"))
            assert(cmd("time 1790009999"):match("^ok time kept 1790000000"))   -- never overrides a valid clock
            assert(cmd("audio meow"):match("^err audio unsupported"))
            assert(cmd("audio beep 1000 500 40"):match("^ok audio scheduled"))
            assert(coroutine.resume(tasks[#tasks])); assert(played[1].content=="/pp_beep.wav" and vol==40)
            assert(cmd("stop"):match("^ok outputs off")); assert(coroutine.resume(tasks[#tasks]))
            assert(written[#written]:match("^err audio cancelled"))
            assert(cmd("audio tts 你好 宠宝"):match("^ok audio scheduled")); assert(coroutine.resume(tasks[#tasks])); assert(played[2].content=="你好 宠宝")
        '''))

if __name__=='__main__': unittest.main()
