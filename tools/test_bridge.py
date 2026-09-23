"""HTTP contract/security checks with a mock gateway; never talks to physical USB."""
import importlib.util
import json
import threading
import unittest
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from http.server import ThreadingHTTPServer

spec=importlib.util.spec_from_file_location('air_bridge',Path(__file__).resolve().parents[1]/'apps/bridge/air_bridge.py')
module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)

class FakeGateway:
    def snapshot(self,device): return {'device_id':device,'online':True,'transport':'test-only','telemetry':None}
    def command(self,c): return {'id':c['id'],'status':'executed'}
    def camera_frame(self,device): return b'\xff\xd8test-only-frame\xff\xd9'

class Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server=ThreadingHTTPServer(('127.0.0.1',0),module.Handler)
        cls.server.device='collar-evt-001'; cls.server.token='test-only-token'
        cls.server.gateway=FakeGateway(); cls.server.commands={}; cls.server.command_lock=threading.Lock()
        cls.url=f'http://127.0.0.1:{cls.server.server_port}/v1/devices/collar-evt-001/'
        cls.thread=threading.Thread(target=cls.server.serve_forever,daemon=True); cls.thread.start()
    @classmethod
    def tearDownClass(cls): cls.server.shutdown(); cls.server.server_close()
    def request(self,path,body=None,headers=None):
        h={'Authorization':'Bearer test-only-token','Content-Type':'application/json'}
        h.update(headers or {})
        req=Request(self.url+path,data=json.dumps(body).encode() if body else None,headers=h)
        try:
            with urlopen(req,timeout=3) as r: return r.status,json.load(r)
        except HTTPError as e: return e.code,json.load(e)
    def test_snapshot(self): self.assertEqual(self.request('snapshot')[0],200)
    def test_camera(self):
        req=Request(self.url+'camera/frame',headers={'Authorization':'Bearer test-only-token'})
        with urlopen(req,timeout=3) as r:
            self.assertEqual(r.headers['Content-Type'],'image/jpeg')
            self.assertEqual(r.read(),b'\xff\xd8test-only-frame\xff\xd9')
        self.assertEqual(self.request('camera/frame',headers={'Authorization':'Bearer bad'})[0],401)
    def test_csrf(self): self.assertEqual(self.request('snapshot',headers={'Origin':'https://evil.invalid'})[0],403)
    def test_auth(self): self.assertEqual(self.request('snapshot',headers={'Authorization':'Bearer bad'})[0],401)
    def test_no_legacy(self): self.assertEqual(self.request('../../led/on')[0],404)
    def test_commands(self):
        c={'id':'test-123456','device_id':'collar-evt-001','type':'GET_STATE','issued_at':1700000000,'expires_at':1700000100}
        self.assertEqual(self.request('commands',c)[1]['status'],'executed')
        self.assertEqual(self.request('commands/test-123456')[0],200)
        c['type']='VIBRATE'; self.assertEqual(self.request('commands',c)[0],409)
        c['id']='new-123456'; c['type']='ARC'; self.assertEqual(self.request('commands',c)[0],422)

if __name__=='__main__': unittest.main()
