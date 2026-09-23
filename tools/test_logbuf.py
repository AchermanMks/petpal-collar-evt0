"""logbuf_app: ring buffer, error snapshot event + KV, previous-boot flush, chunked upload. Mock only."""
import unittest
from pathlib import Path
from lupa import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
def u(s): return s.encode('utf-8').decode('latin-1')
class Tests(unittest.TestCase):
    def lua(self,prev=None):
        L=LuaRuntime(unpack_returned_tuples=True,encoding='latin-1'); L.globals().firmware_path=str(ROOT/'firmware/wearable-evt0')
        L.execute(u(r'''
            package.path=firmware_path.."/?.lua;"..package.path
            tick=0; mcu={ticks=function() return tick end}; kv={}; events={}; sent={}
            fskv={get=function(k) if kv[k]==nil then return end; return kv[k] end,set=function(k,v) kv[k]=v; return true end,del=function(k) kv[k]=nil; return true end}
            json={encode=function(t) local s="["; for i,l in ipairs(t) do s=s..(i>1 and "," or "").."\""..l.."\"" end; return s.."]" end,
                  decode=function(s) local t={}; for l in s:gmatch("\"(.-)\"") do t[#t+1]=l end; return t end}
            CFG={device_id="collar-evt-003"}
            printed={}; log=setmetatable({},{__index={debug=function() end,info=function(...) printed[#printed+1]=select("#",...) end,warn=function() end,error=function() end},
                __newindex=function() error("attempt to write to a read-only table (LuatOS rotable)") end})  -- like the real `log` library
        '''))
        if prev: L.execute(u('kv["pp_lastlog"]=%s'%prev))
        L.execute(u('L=require("logbuf_app"); PETPAL={event=function(k,d) events[#events+1]={k,d} end}'))
        return L
    def test_ring_and_upload(self):
        L=self.lua(); L.execute(u(r'''
            for i=1,250 do tick=i; log.info("mod","line",i,nil,true) end
            assert(L.size()==200 and #printed==250,"original log still called")
            local t=L.tail(3); assert(#t==3 and t[3]=="250 I mod line 250 nil true" and t[1]:match("^248 I mod line 248 "),t[3])
            log.info("x",string.rep("y",500)); assert(#L.tail(1)[1]==160,"line truncated")
            local n,why=L.upload(45,function(topic,tbl) assert(topic=="/log" and tbl.device_id=="collar-evt-003"); sent[#sent+1]=tbl; return true end)
            assert(n==3 and why==nil and #sent[1].lines==20 and #sent[3].lines==5 and sent[3].parts==3 and sent[3].part==3,tostring(n))
            local n2,why2=L.upload(10,function() return false end); assert(n2==0 and why2=="enqueue_failed")
            assert(#events==0,"info/warn never emit events")
        '''))
    def test_error_snapshot_rate_limited_and_persisted(self):
        L=self.lua(); L.execute(u(r'''
            for i=1,30 do tick=i*10; log.info("m","ok",i) end
            tick=1000; log.error("gsensor","DA267 not found")
            assert(#events==1 and events[1][1]=="log_error" and #events[1][2].lines==20 and events[1][2].lines[20]:match("E gsensor DA267 not found$"))
            assert(kv["pp_lastlog"]~=nil,"snapshot persisted for next boot")
            tick=30000; log.error("m","again"); assert(#events==1,"rate limited to one per 60 s")
            tick=70000; log.error("m","later"); assert(#events==2)
        '''))
    def test_prev_boot_flush(self):
        L=self.lua(prev='"[\\"1 E old crash line\\"]"'); L.execute(u(r'''
            L.flush_prev_boot("0 0 5"); assert(#events==1 and events[1][1]=="log_prev_boot" and events[1][2].reason=="0 0 5" and events[1][2].lines[1]=="1 E old crash line")
            assert(kv["pp_lastlog"]==nil,"consumed once"); L.flush_prev_boot("0 0 5"); assert(#events==1)
        '''))
if __name__=='__main__': unittest.main()
