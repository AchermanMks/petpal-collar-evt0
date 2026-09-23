"""Compile actual Foundation adapter; test fixture is never included in the app/bridge."""
import json
import os
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
commands=[]
class Fixture(BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def send(self,data):
        b=json.dumps(data).encode()
        self.send_response(200); self.send_header('Content-Length',str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_POST(self):
        c=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        assert self.path=='/v1/devices/collar-evt-001/commands'
        assert c['expires_at']>c['issued_at']
        commands.append(c)
        self.send({'id':c['id'],'status':'accepted'})
    def do_GET(self):
        if self.path.endswith('/camera/frame'):
            b=b'\xff\xd8test-only-frame\xff\xd9'
            self.send_response(200); self.send_header('Content-Type','image/jpeg'); self.send_header('Content-Length',str(len(b)))
            self.end_headers(); self.wfile.write(b)
        elif self.path.endswith('/snapshot'):
            self.send({'device_id':'collar-evt-001','online':True,'telemetry':{
                'position':{'source':'gnss','lat':31.23,'lng':121.47,'alt_m':8,'speed_kmh':3.704,'sats':12,'fix_age_s':2},
                'outputs':{'motor_on':False,'led_on':False}}})
        else:
            assert self.path.endswith('/commands/'+commands[-1]['id'])
            self.send({'id':commands[-1]['id'],'status':'executed'})

server=ThreadingHTTPServer(('127.0.0.1',0),Fixture)
threading.Thread(target=server.serve_forever,daemon=True).start()
try:
    with tempfile.TemporaryDirectory(prefix='petpal-adapter-test-') as temp:
        exe=Path(temp)/'adapter-test'
        core=ROOT/'apps/ios_air8201/PetCollar/Core'
        subprocess.run(['swiftc','-parse-as-library',str(core/'ESPClient.swift'),str(core/'AirCollar.swift'),str(ROOT/'tools/test_air_adapter.swift'),'-o',str(exe)],check=True)
        env=dict(os.environ,PETPAL_AIR_SERVICE_URL=f'http://127.0.0.1:{server.server_port}',PETPAL_AIR_DEVICE_ID='collar-evt-001',PETPAL_BRIDGE_TOKEN='')
        subprocess.run([str(exe)],env=env,check=True,timeout=30)
        assert [c['type'] for c in commands]==['LED','LED','VIBRATE','STOP']
        assert commands[0]['args']['pattern']=='on' and commands[1]['args']['pattern']=='off'
        assert len({c['id'] for c in commands})==4
finally:
    server.shutdown(); server.server_close()
