"""cloud_bridge HTTP contract with a fake MQTT client. No broker, no collar."""
import importlib.util, json, threading, time, unittest
from http.server import ThreadingHTTPServer
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError

spec=importlib.util.spec_from_file_location('cloud_bridge',Path(__file__).resolve().parents[1]/'apps/cloud/cloud_bridge.py')
cb=importlib.util.module_from_spec(spec); spec.loader.exec_module(cb)

class FakeMqtt:
    def __init__(self,fleet): self.fleet=fleet; self.published=[]; self.answer=True
    def publish(self,topic,payload,qos=1):
        self.published.append((topic,payload)); c=json.loads(payload)
        if self.answer:  # collar acks accepted immediately, executed 0.2 s later
            self.fleet.ingest('petpal/v1/collar-evt-003/ack',json.dumps({'id':c['id'],'device_id':'collar-evt-003','ts':1,'status':'accepted'}))
            threading.Timer(.2,lambda: self.fleet.ingest('petpal/v1/collar-evt-003/ack',json.dumps({'id':c['id'],'device_id':'collar-evt-003','ts':2,'status':'executed'}))).start()
        class R: rc=cb.mqtt.MQTT_ERR_SUCCESS
        return R()

class Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fleet=cb.Fleet(); cls.mq=FakeMqtt(cls.fleet)
        cls.server=ThreadingHTTPServer(('127.0.0.1',0),cb.Handler); cls.server.token='test-only-token-1234'; cls.server.fleet=cls.fleet; cls.server.mqtt=cls.mq
        cls.url=f'http://127.0.0.1:{cls.server.server_port}/v1/devices/'
        cb.LIVE_INTERVAL_S=1; cls.server.live=cb.LiveSessions(cls.fleet,cls.mq)
        threading.Thread(target=cls.server.serve_forever,daemon=True).start()
    @classmethod
    def tearDownClass(cls): cls.server.shutdown()
    def req(self,path,body=None,headers=None):
        h={'Authorization':'Bearer test-only-token-1234','Content-Type':'application/json'}; h.update(headers or {})
        r=Request(self.url+path,data=json.dumps(body).encode() if body else None,headers=h)
        try:
            with urlopen(r,timeout=12) as x: return x.status,json.load(x)
        except HTTPError as e: return e.code,json.load(e)
    def test_offline_until_reported(self):
        self.assertEqual(self.req('collar-evt-777/snapshot')[0],503)
        self.fleet.ingest('petpal/v1/collar-evt-777/state',json.dumps({'v':1,'online':True}))
        self.assertEqual(self.req('collar-evt-777/snapshot')[0],503,'state alone is not a snapshot')
        self.fleet.ingest('petpal/v1/collar-evt-777/telemetry',json.dumps({'device_id':'collar-evt-777','position':{'lat':1.0,'lng':2.0,'source':'gnss','fix_age_s':3,'sats':5,'alt_m':1,'speed_kmh':0},'outputs':{'led_on':False}}))
        s,d=self.req('collar-evt-777/snapshot'); self.assertEqual(s,200); self.assertTrue(d['online']); self.assertGreaterEqual(d['telemetry']['position']['fix_age_s'],3)
        self.fleet.ingest('petpal/v1/collar-evt-777/state',json.dumps({'v':1,'online':False,'reason':'lwt'}))
        self.assertFalse(self.req('collar-evt-777/snapshot')[1]['online'],'LWT marks the collar offline')
        self.fleet.ingest('petpal/v1/collar-evt-777/state',json.dumps({'v':1,'online':True}))
    def test_auth_and_camera(self):
        self.assertEqual(self.req('collar-evt-003/snapshot',headers={'Authorization':'Bearer nope'})[0],401)
        self.assertEqual(self.req('collar-evt-003/snapshot',headers={'Origin':'https://evil.invalid'})[0],403)
        self.assertEqual(self.req('collar-evt-777/camera/frame')[0],503,'offline collar: no live session')
    def test_live_over_mqtt(self):
        self.fleet.ingest('petpal/v1/collar-evt-003/telemetry',json.dumps({'device_id':'collar-evt-003'}))
        jpeg=b'\xff\xd8live\xff\xd9'
        def collar_frames(seq): self.fleet.ingest('petpal/v1/collar-evt-003/frame',b'PPF1%08x%08x'%(seq,seq*1000)+jpeg[:-1]+bytes([seq%250])+b'\xff\xd9')
        threading.Timer(.3,collar_frames,args=(1,)).start(); threading.Timer(.9,collar_frames,args=(2,)).start()
        req=Request(self.url+'collar-evt-003/camera/frame',headers={'Authorization':'Bearer test-only-token-1234'})
        with urlopen(req,timeout=20) as r: f1=r.read()
        self.assertEqual(r.headers['Content-Type'],'image/jpeg'); self.assertTrue(f1.startswith(b'\xff\xd8'))
        starts=[json.loads(p) for t,p in self.mq.published if t.endswith('/cmd') and json.loads(p)['type']=='LIVE']
        self.assertEqual(starts[-1]['args']['action'],'start'); self.assertIn('config',starts[-1]['args'])
        with urlopen(req,timeout=20) as r: f2=r.read()
        self.assertNotEqual(f1,f2,'each request gets a newer frame, never the same one twice')
        # a stale frame (older than seq served) is never returned: with no new frame the request fails instead
        cb.LIVE_INTERVAL_S=0
        try:
            with urlopen(req,timeout=20) as r: self.fail('served a stale frame')
        except HTTPError as e: self.assertEqual(e.code,503)
        finally: cb.LIVE_INTERVAL_S=1
    def test_command_roundtrip(self):
        self.fleet.ingest('petpal/v1/collar-evt-003/telemetry',json.dumps({'device_id':'collar-evt-003'}))
        c={'id':'cmd-12345678','device_id':'collar-evt-003','issued_at':1,'expires_at':121,'type':'LED','args':{'pattern':'on','duration_s':5}}
        s,a=self.req('collar-evt-003/commands',c); self.assertEqual((s,a['status']),(202,'accepted'))
        self.assertEqual(json.loads(self.mq.published[-1][1])['id'],'cmd-12345678')
        time.sleep(.4); s,a=self.req('collar-evt-003/commands/cmd-12345678'); self.assertEqual((s,a['status']),(200,'executed'))
        c['type']='ARC'; c['id']='cmd-arc-0001'; self.assertEqual(self.req('collar-evt-003/commands',c)[0],422)
        c['type']='LED'; c['device_id']='collar-evt-002'; self.assertEqual(self.req('collar-evt-003/commands',c)[0],400)
        self.assertEqual(self.req('collar-evt-999/commands',{**c,'device_id':'collar-evt-999'})[0],503,'never-seen collar: not sent')
    def test_logs_from_chunks_and_error_events(self):
        self.fleet.ingest('petpal/v1/collar-evt-003/telemetry',json.dumps({'device_id':'collar-evt-003'}))
        self.fleet.ingest('petpal/v1/collar-evt-003/log',json.dumps({'v':1,'chunk':1,'part':1,'parts':1,'lines':['10 I main boot','20 W net slow']}))
        self.fleet.ingest('petpal/v1/collar-evt-003/event',json.dumps({'v':1,'type':'log_error','data':{'lines':['30 E gsensor fail']}}))
        self.fleet.ingest('petpal/v1/collar-evt-003/event',json.dumps({'v':1,'type':'reboot','data':{}}))
        s,d=self.req('collar-evt-003/logs?lines=2'); self.assertEqual(s,200)
        self.assertEqual([l['line'] for l in d['lines']],['20 W net slow','30 E gsensor fail']); self.assertEqual(d['lines'][1]['source'],'log_error')
        self.assertEqual(self.req('collar-evt-777/logs')[0],503)
    def test_history(self):
        for i in range(3):
            self.fleet.ingest('petpal/v1/collar-evt-003/telemetry',json.dumps({'device_id':'collar-evt-003','seq':i,'ts':1790000000+60*i,'battery':{'pct':90-i,'mv':4000,'charging':False},'radio':{'rsrp_dbm':-85},'motion':{'state':'still','active_s':i},'position':None}))
        s,d=self.req('collar-evt-003/history?hours=1'); self.assertEqual(s,200)
        self.assertEqual([x['pct'] for x in d['samples'][-3:]],[90,89,88]); self.assertFalse(d['samples'][-1]['fix']); self.assertEqual(d['period_s'],60)
        self.assertEqual(self.req('collar-evt-777/history')[0],503)
    def test_no_ack_is_reported_not_invented(self):
        self.fleet.ingest('petpal/v1/collar-evt-003/telemetry',json.dumps({'device_id':'collar-evt-003'}))
        cb.ACK_WAIT_S=0.5; self.mq.answer=False
        try:
            s,a=self.req('collar-evt-003/commands',{'id':'cmd-silent-01','device_id':'collar-evt-003','issued_at':1,'expires_at':121,'type':'STOP','args':{}})
            self.assertEqual(s,504); self.assertEqual(self.req('collar-evt-003/commands/cmd-silent-01')[0],404)
        finally: cb.ACK_WAIT_S=8.0; self.mq.answer=True

if __name__=='__main__': unittest.main()
