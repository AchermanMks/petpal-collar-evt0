"""Camera Lua + USB protocol tests (legacy hex chunks and fast binary windows). Synthetic bytes only; not board acceptance."""
import importlib.util
import json
import time
import unittest
import zlib
from pathlib import Path
from unittest.mock import patch
from lupa import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('camera_bridge',ROOT/'apps/bridge/air_bridge.py')
bridge=importlib.util.module_from_spec(spec); spec.loader.exec_module(bridge)
JPEG=b'\xff\xd8'+bytes(range(256))*10+b'\n\r\n'*40+b'\xff\xd9'  # newlines inside the payload must not confuse the binary reader

class Blob:
    def used(self): return len(JPEG)
    def query(self,offset,size): return JPEG[offset:offset+size]

class SerialFixture:
    """003 r2 firmware: hex chunk protocol, one reply line per request."""
    corrupt=False
    drop_offsets=()  # offsets whose first reply is lost, as seen with USB full-packet loss
    def __init__(self,*args,**kwargs): self.row=b''; self.frame_id=None; self.dropped=set()
    def __enter__(self): return self
    def __exit__(self,*args): pass
    def reset_input_buffer(self): pass
    def write(self,line):
        args=line.decode().split()
        if args[0]=='snapshot': self.row=('ok '+json.dumps({'device_id':'collar-evt-001'})+'\n').encode()
        elif args[1]=='capture':
            self.frame_id=args[2]
            self.row=f'frame {self.frame_id} {len(JPEG)} {zlib.adler32(JPEG)+(1 if self.corrupt else 0):08x}\n'.encode()
        elif args[1]=='chunk':
            assert args[2]==self.frame_id
            offset=int(args[3]); self.row=f'jpeg {self.frame_id} {offset} {JPEG[offset:offset+1024].hex()}\n'.encode()
            if offset in self.drop_offsets and offset not in self.dropped: self.dropped.add(offset); self.row=self.row[:700]
        elif args[1]=='close': self.row=b'ok camera closed\n'
        return len(line)
    def readline(self,limit):
        row,self.row=self.row,b''; return row

class FastFixture:
    """Firmware with `camera read`: persistent port, text header + raw bytes, async `frame` header for prefetched captures."""
    lose_first_window=False; algo='adler32'; old_firmware=False
    log=[]
    shared_frames={}  # the device keeps frames across a host-side reopen; only the tty handle changes
    lost=False  # class-level: the device state persists across a host-side reopen
    def __init__(self,*args,**kwargs): self.rx=b''; self.frames=FastFixture.shared_frames; self.closed=False
    def close(self): self.closed=True
    def reset_input_buffer(self): self.rx=b''
    @property
    def in_waiting(self): return len(self.rx)
    def read(self,n):
        if not self.rx: time.sleep(.002)
        out,self.rx=self.rx[:n],self.rx[n:]; return out
    def write(self,line):
        args=line.decode().split(); FastFixture.log.append(' '.join(args[:2]))
        if args[0]=='snapshot': self.rx+=('ok '+json.dumps({'device_id':'collar-evt-001'})+'\r\n').encode()
        elif args[1]=='config': self.rx+=b'ok camera config quality=1 sum=adler32 crop=off\r\n'
        elif args[1]=='capture':
            self.frames[args[2]]=JPEG
            digest=zlib.crc32(JPEG) if self.algo=='crc32' else zlib.adler32(JPEG)
            self.rx+=b'ok camera scheduled\r\n'+f'frame {args[2]} {len(JPEG)} {digest:08x}{" crc32" if self.algo=="crc32" else ""}\r\n'.encode()
        elif args[1]=='read':
            if self.old_firmware: self.rx+=b'err camera unknown operation\r\n'; return len(line)
            off,n=int(args[3]),int(args[4]); data=self.frames[args[2]][off:off+n]
            reply=f'jpegbin {args[2]} {off} {len(data)}\r\n'.encode()+data
            if self.lose_first_window and not FastFixture.lost: FastFixture.lost=True; reply=reply[:len(reply)-512]
            self.rx+=reply
        elif args[1]=='close': self.frames.pop(args[2],None); self.rx+=b'ok camera closed\r\n'
        return len(line)

class Tests(unittest.TestCase):
    def test_usb_roundtrip(self):
        with patch.object(bridge.serial,'Serial',SerialFixture):
            self.assertEqual(bridge.USBGateway('test-only').camera_frame_legacy('collar-evt-001'),JPEG)
    def test_usb_chunk_retry(self):
        with patch.object(bridge.serial,'Serial',SerialFixture),patch.object(SerialFixture,'drop_offsets',(1024,)),patch.object(bridge.time,'sleep',lambda s: None):
            self.assertEqual(bridge.USBGateway('test-only').camera_frame_legacy('collar-evt-001'),JPEG)
    def test_usb_checksum(self):
        with patch.object(bridge.serial,'Serial',SerialFixture),patch.object(SerialFixture,'corrupt',True):
            with self.assertRaisesRegex(RuntimeError,'checksum'):
                bridge.USBGateway('test-only').camera_frame_legacy('collar-evt-001')
    def test_fast_pull_and_prefetch(self):
        with patch.object(bridge.serial,'Serial',FastFixture):
            g=bridge.USBGateway('test-only',window=1024,camera_config='sum=adler32')
            a,_=g.camera_pull('collar-evt-001'); self.assertEqual(a,JPEG); self.assertIsNotNone(g.next_id)
            b,_=g.camera_pull('collar-evt-001'); self.assertEqual(b,JPEG)  # served from the prefetched capture
    def test_fast_crc32(self):
        with patch.object(bridge.serial,'Serial',FastFixture),patch.object(FastFixture,'algo','crc32'):
            self.assertEqual(bridge.USBGateway('test-only').camera_pull('collar-evt-001',prefetch=False)[0],JPEG)
    def test_fast_lost_packet_shrinks_window(self):
        with patch.object(bridge.serial,'Serial',FastFixture),patch.object(FastFixture,'lose_first_window',True):
            g=bridge.USBGateway('test-only',window=2048)
            self.assertEqual(g.camera_pull('collar-evt-001',prefetch=False)[0],JPEG); self.assertEqual(g.window,1024)
    def test_stream_serves_each_frame_once_then_stops(self):
        with patch.object(bridge.serial,'Serial',FastFixture):
            g=bridge.USBGateway('test-only')
            self.assertEqual(g.camera_frame('collar-evt-001'),JPEG); first=g.served
            self.assertEqual(g.camera_frame('collar-evt-001'),JPEG); self.assertGreater(g.served,first)
            deadline=time.time()+4
            while g.stream_thread and time.time()<deadline: time.sleep(.05)
            self.assertIsNone(g.stream_thread)  # no requests -> capturing stops
            stale=g.seq; time.sleep(.6)
            self.assertEqual(g.camera_frame('collar-evt-001'),JPEG); self.assertGreater(g.served,stale)  # leftover frame is never served later
    def test_command_skips_stale_async_ack(self):
        class AckFixture(FastFixture):
            def write(self,line):
                if line.startswith(b'command '):
                    c=json.loads(line[8:]); stale=json.dumps({'id':'previous-command-id','status':'executed'})
                    self.rx+=f'ack {stale}\r\n'.encode()+('ack '+json.dumps({'id':c['id'],'status':'accepted'})+'\r\nok command processed\r\n').encode()
                    return len(line)
                return super().write(line)
        with patch.object(bridge.serial,'Serial',AckFixture):
            a=bridge.USBGateway('test-only').command({'id':'current-command-id','type':'LED'})
            self.assertEqual((a['id'],a['status']),('current-command-id','accepted'))
    def test_old_firmware_falls_back_to_hex(self):
        class Both(FastFixture,SerialFixture):
            def __init__(self,*a,**k): FastFixture.__init__(self); SerialFixture.__init__(self)
            def __enter__(self): return self
            def __exit__(self,*a): pass
            def write(self,line):
                if b' chunk ' in line or self.legacy_mode: self.legacy_mode=True; return SerialFixture.write(self,line)
                return FastFixture.write(self,line)
            legacy_mode=False
        with patch.object(bridge.serial,'Serial',Both),patch.object(FastFixture,'old_firmware',True):
            g=bridge.USBGateway('test-only')
            with patch.object(g,'camera_frame_legacy',return_value=JPEG) as legacy:
                self.assertEqual(g.camera_frame('collar-evt-001'),JPEG); self.assertTrue(g.legacy); legacy.assert_called()
    def test_lua_capture_lifecycle(self):
        lua=LuaRuntime(unpack_returned_tuples=True)
        lua.globals().firmware_path=str(ROOT/'firmware/wearable-evt0')
        lua.globals().photo_blob=Blob()
        lua.execute(r'''
            package.path=firmware_path.."/?.lua;"..package.path
            local _tn=tonumber; tonumber=function(v,b) if v==nil then error("bad argument #1 to 'tonumber' (value expected)",2) end; if b then return _tn(v,b) end; return _tn(v) end
            CFG={camera={board="Air8201G_BTB_V1.4"},features={gsensor=false}}
            STATE={}; camera={init=function() return 1 end,close=function() end}; local tick=0; local pending; local pin={}; local reply
            mcu={ticks=function() return tick end}
            local timers={}
            sys={wait=function(ms) tick=tick+ms end,timerLoopStart=function() end,taskInit=function(f) pending=f end,
                timerStart=function(f,ms) timers[#timers+1]=f; return #timers end,timerStop=function(id) timers[id]=nil end}
            gpio={setup=function(p,v) pin[p]=v end,set=function(p,v) pin[p]=v end}
            log={info=function() end}
            local reg
            i2c={FAST=1,setup=function() return true end,send=function(_,_,s) reg=s:byte(); return true end,
                recv=function() return string.char(reg==0xf0 and 0x23 or 0x2a) end,close=function() end}
            local opens,closes,quality=0,0,nil
            package.loaded.excamera={open=function(p) assert(p.id=="gc032a" and p.i2c_id==1 and p.save_path=="ZBUFF"); opens=opens+1; return true end,
                photo=function(x,y,w,h,q) quality=q; return true,photo_blob end,close=function() closes=closes+1 end}
            local paused,resumed=0,0; GNSS={pause=function() paused=paused+1 end,resume=function() resumed=resumed+1 end}
            GSENSOR={pause=function() paused=paused+1 end,resume=function() resumed=resumed+1 end}
            local M=require("camera_app")
            assert(not M.capture("bad",function() end))
            assert(M.capture("frame-123456",function(s) reply=s end))
            local ok,e=M.capture("frame-abcdef",function() end); assert(not ok and e=="camera_busy")
            pending(); assert(reply:match("^frame frame%-123456 %d+ %x+$"))
            -- sensor stays powered between frames; a second capture must not re-probe/re-open
            assert(opens==1 and closes==0 and pin[22]==1 and STATE.camera.ready and quality==1)
            assert(paused==2 and resumed==0,"GNSS and G-sensor pause while the camera sensor is open")
            assert(M.capture("frame-second",function(s) reply=s end)); pending(); assert(opens==1 and reply:match("^frame frame%-second "))
            local s=M.chunk("frame-123456",0); assert(s:match("^jpeg frame%-123456 0 ffd8"))
            assert(M.slice("frame-second",0,2)=="\255\216" and #M.slice("frame-second",0,16384)==math.min(16384,photo_blob.used()))
            assert(not M.slice("frame-second",0,16385) and not M.slice("frame-second",-1,10) and not M.slice("nope-nope",0,10))
            -- only two frames are kept: a third capture evicts the oldest
            assert(M.capture("frame-third1",function() end)); pending(); assert(not M.chunk("frame-123456",0) and M.chunk("frame-second",0))
            -- runtime config
            assert(M.config({quality="3",sum="adler32"}) and M.config({x="160",y="120",w="320",h="240"}))
            assert(not M.config({w="700"}) and not M.config({quality="0"}) and not M.config({bogus="1"}) and not M.config({x="600",y="0",w="320",h="240"}))
            assert(M.config({crop="off"}):match("crop=off"))
            assert(M.capture("frame-fourth",function() end)); pending(); assert(quality==3)
            -- idle timer powers the sensor down; next capture re-opens
            for _,f in pairs(timers) do f() end
            assert(closes==1 and pin[22]==0 and pin[5]==1)
            assert(resumed==2,"GNSS and G-sensor resume when the camera sensor powers down")
            assert(M.capture("frame-fifth1",function() end)); pending(); assert(opens==2)
            assert(not M.chunk("other-frame",0) and not M.chunk("frame-fifth1",-1))
            tick=tick+20001; assert(not M.chunk("frame-fifth1",0))
            assert(not M.release("frame-fifth1"))
            camera=nil; assert(not M.capture("frame-abcdef",function() end))
        ''')
    def test_lua_live_over_mqtt(self):
        L=LuaRuntime(unpack_returned_tuples=True); L.globals().firmware_path=str(ROOT/'firmware/wearable-evt0'); L.globals().photo_blob=Blob()
        out=L.eval(r'''function()
            package.path=firmware_path.."/?.lua;"..package.path
            local _tn=tonumber; tonumber=function(v,b) if v==nil then error("tonumber(nil)",2) end; if b then return _tn(v,b) end; return _tn(v) end
            CFG={camera={board="Air8201G_BTB_V1.4"},features={gsensor=false}}
            STATE={}; camera={init=function() return 1 end,close=function() end}; local tick=0; local tasks={}; local pin={}
            mcu={ticks=function() return tick end}
            local timers={}; local waiting={}
            sys={wait=function(ms) tick=tick+ms; coroutine.yield() end,timerLoopStart=function() end,taskInit=function(f) tasks[#tasks+1]=coroutine.create(f) end,
                timerStart=function(f,ms) timers[#timers+1]=f; return #timers end,timerStop=function(id) timers[id]=nil end,
                publish=function(t) waiting[t]=true end,waitUntil=function(t,ms) if not waiting[t] then coroutine.yield() end; waiting[t]=nil; return true end}
            gpio={setup=function(p,v) pin[p]=v end,set=function(p,v) pin[p]=v end}
            log={info=function() end,warn=function() end}
            local reg; i2c={FAST=1,setup=function() return true end,send=function(_,_,s) reg=s:byte(); return true end,recv=function() return string.char(reg==0xf0 and 0x23 or 0x2a) end,close=function() end}
            package.loaded.excamera={open=function() return true end,photo=function() return true,photo_blob end,close=function() end}
            local published={}
            MQTT_RAW_PUB=function(topic,payload) published[#published+1]={topic,payload}; return true end
            local M=require("camera_app")
            assert(not M.live_start(0.2) and not M.live_start("x"))
            local ok,_,applied=M.live_start(3); assert(ok and applied.interval_s==3 and STATE.camera_live==true)
            local function pump() for _,co in ipairs(tasks) do while coroutine.status(co)=="suspended" do local ok,e=coroutine.resume(co); assert(ok,e); if coroutine.status(co)=="suspended" then break end end end end
            -- run the live loop: capture task + live task interleave until a frame is published
            for i=1,12 do pump(); if #published>0 then break end end
            assert(#published>=1,"frame published over MQTT")
            local p=published[1]; assert(p[1]=="/frame" and p[2]:sub(1,4)=="PPF1" and #p[2]==20+photo_blob.used() and p[2]:sub(21,22)=="\255\216")
            assert(M.live_active())
            -- renew keeps it alive; without renewal it stops after LIVE_TTL_MS
            local ok2,_,a2=M.live_start(5); assert(ok2 and a2.renewed and a2.interval_s==5)
            tick=tick+M.LIVE_TTL_MS+1; for i=1,20 do pump() end
            assert(not M.live_active() and STATE.camera_live==false,"expired without renewal")
            -- explicit stop
            assert(M.live_start(2)); M.live_stop(); for i=1,20 do pump() end; assert(not M.live_active())
            return #published
        end''')()
        self.assertGreaterEqual(out,1)
    def test_lua_console_binary_read(self):
        lua=LuaRuntime(unpack_returned_tuples=True)
        lua.globals().firmware_path=str(ROOT/'firmware/wearable-evt0')
        out=lua.eval(r'''function()
            package.path=firmware_path.."/?.lua;"..package.path
            local _tn=tonumber; tonumber=function(v,b) if v==nil then error("tonumber(nil)",2) end; if b then return _tn(v,b) end; return _tn(v) end
            PROJECT="petpal_evt0"; VERSION="001.000.003"; CFG={features={}}; STATE={}
            local written,tasks,rx,on_rx={}, {}, "", nil
            local full=2 -- first two writes report a full TX buffer
            uart={VUART_0=9,setup=function() end,on=function(_,_,f) on_rx=f end,
                read=function() local s=rx; rx=""; return s end,
                write=function(_,s) if #s>100 and full>0 then full=full-1; return 0 end; written[#written+1]=s; return #s end}
            sys={taskInit=function(f) tasks[#tasks+1]=f end,wait=function() end,timerStart=function() end,publish=function() end}
            log={info=function() end,warn=function() end}
            json={encode=function() return "{}" end,decode=function() return {} end}
            local data=string.rep("\255\216\n\r",500)
            CAMERA={tx_busy=false,slice=function(id,off,len) if id~="frame-123456" then return nil,"frame_expired" end; return data:sub(off+1,off+len) end,
                capture=function() return true end,chunk=function() end,release=function() return true end,config=function(kv) return kv.sum and "sum="..kv.sum end}
            require("console_app")
            rx="camera read frame-123456 0 2000\n"; on_rx()
            assert(#written==0 and CAMERA.tx_busy)       -- nothing until the task runs
            rx="ping\n"; on_rx()                          -- text reply arriving mid-transfer is deferred
            assert(#written==0)
            tasks[1]()
            local all=table.concat(written)
            assert(not CAMERA.tx_busy)
            assert(all:sub(1,33)=="jpegbin frame-123456 0 2000\r\n"..data:sub(1,4), all:sub(1,40))
            local body=all:sub(30,30+1999); assert(body==data)
            assert(all:sub(30+2000):match("^pong petpal_evt0"))
            for _,s in ipairs(written) do assert(#s<=480) end
            rx="camera read frame-zzzzzz 0 10\n"; on_rx(); assert(written[#written]:match("^err camera frame_expired"))
            rx="camera config sum=crc32\n"; on_rx(); assert(written[#written]:match("^ok camera config sum=crc32"))
            rx="camera config sum=crc32;x\n"; on_rx(); assert(written[#written]:match("^err camera bad_option"))
            return true
        end''')()
        self.assertTrue(out)

if __name__=='__main__': unittest.main()
