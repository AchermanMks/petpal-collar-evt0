"""AIR-only iOS bench bridge. Real USB state, no simulator values. Loopback by default.
python air_bridge.py [--port /dev/cu.usbmodem...]
Windows LuaTools must release the USB device before macOS can use it.
"""
import argparse
import glob
import json
import os
import re
import threading
import time
import uuid
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import serial

class CameraTimeout(RuntimeError): pass

class USBGateway:
    def __init__(self,port=None,window=8192,prefetch=True,camera_config='',legacy=False):
        self.port=port
        self.lock=threading.RLock()
        self.cam=None; self.cam_buf=b''; self.cam_identity=None; self.headers={}; self.next_id=None
        self.window=window; self.max_window=max(window,16384); self.clean=0; self.prefetch=prefetch; self.camera_config=camera_config; self.legacy=legacy
        self.stream_cv=threading.Condition(); self.stream_thread=None; self.stream_error=None
        self.latest=None; self.served=0; self.seq=0; self.last_request=0; self.stats=None

    @staticmethod
    def exchange(port,line,prefixes,seconds=2.5):
        with serial.Serial(port,115200,timeout=.15,write_timeout=1) as s:
            s.reset_input_buffer()
            s.write((line+'\n').encode())
            buf=b''; deadline=time.monotonic()+seconds
            while time.monotonic()<deadline:
                buf+=s.read(4096)
                while b'\n' in buf:
                    row,buf=buf.split(b'\n',1)
                    row=row.decode('utf-8','replace').strip()
                    if row.startswith(prefixes): return row
                if len(buf)>8192: raise RuntimeError('Oversized console response')
        raise RuntimeError('开发板未回应：确认已烧录 AIR 002/003 命令台，并把 USB 从 Windows 释放给 macOS')

    def find(self):
        for p in sorted(glob.glob('/dev/cu.usbmodem*')+glob.glob('/dev/ttyACM*')):
            try:
                r=self.exchange(p,'ping',('pong ',),1)
                if r.startswith(('pong petpal_evt0 001.000.002','pong petpal_evt0 001.000.003')):
                    self.port=p; return
            except (RuntimeError,serial.SerialException): pass
        raise RuntimeError('未找到 AIR 002/003 USB 命令台；摄像头需 AIR 003 专用固件，并把 USB 从 Windows 释放给 macOS')

    def talk(self,line,prefixes):
        # One shared port handle for every command: a second open of the same tty races the camera reader for bytes.
        with self.lock:
            try:
                self._cam_open(); self._cam_send(line); return self._cam_wait(prefixes,2.5)
            except CameraTimeout:
                self._cam_drop(True); raise RuntimeError('开发板未回应：确认已烧录 AIR 002/003 命令台，并把 USB 从 Windows 释放给 macOS')
            except serial.SerialException: self._cam_drop(True); raise

    def snapshot(self,device):
        r=self.talk('snapshot',('ok {','err '))
        if not r.startswith('ok '): raise RuntimeError(r)
        t=json.loads(r[3:])
        if t.get('device_id')!=device: raise RuntimeError('实际开发板的设备编号不匹配')
        return {'device_id':device,'online':True,'last_seen_ts':time.time(),'transport':'usb-bench','telemetry':t}

    def command(self,c,_retried=False):
        # The port handle is persistent, so the final (asynchronous) ack of an EARLIER command may still be queued:
        # skip acks that belong to other ids instead of failing (seen on board 1, 2026-09-21: LED off -> BUZZ).
        with self.lock:
            try:
                self._cam_open(); self._cam_send('command '+json.dumps(c,separators=(',',':'),allow_nan=False))
                deadline=time.monotonic()+2.5
                while True:
                    r=self._cam_wait(('ack ','err '),max(.05,deadline-time.monotonic()))
                    if not r.startswith('ack '): raise RuntimeError(r)
                    a=json.loads(r[4:])
                    if a.get('id')==c['id']: break
            except CameraTimeout:
                self._cam_drop(True); raise RuntimeError('开发板未回应：确认已烧录 AIR 002/003 命令台，并把 USB 从 Windows 释放给 macOS')
            except serial.SerialException: self._cam_drop(True); raise
        if a.get('status')=='rejected' and a.get('reason')=='clock_unsynced' and not _retried:
            # Bench has no SIM/GNSS time: firmware accepts `time` only while its clock is invalid (docs/16 §4.3).
            if self.talk(f'time {int(time.time())}',('ok time','err time')).startswith('ok time'): return self.command(c,True)
        return a

    @staticmethod
    def camera_exchange(s,line,prefixes,seconds):
        s.write((line+'\n').encode())
        pending=b''; deadline=time.monotonic()+seconds
        while time.monotonic()<deadline:
            pending+=s.readline(2300)
            if len(pending)>2300: raise RuntimeError('Oversized camera response')
            if not pending.endswith(b'\n'): continue
            row=pending.decode('ascii','replace').strip(); pending=b''
            if row.startswith('err '): raise RuntimeError(row)
            if row.startswith(prefixes): return row
        raise CameraTimeout('摄像头响应超时；未收到新画面')

    def camera_frame_legacy(self,device):
        # Hex chunk protocol of AIR 003 r2 firmware (9 s/frame); kept as automatic fallback.
        # Pull each chunk only after the preceding reply, avoiding UART buffer floods.
        # No image queue, no filesystem writes, no third-party image uploads.
        with self.lock:
            self._cam_drop()
            if not self.port: self.find()
            frame_id=uuid.uuid4().hex
            try:
                with serial.Serial(self.port,115200,timeout=.15,write_timeout=1) as s:
                    s.reset_input_buffer()
                    identity=self.camera_exchange(s,'snapshot',('ok {','err '),3)  # not ('ok ',): an async `ok led done` must not be parsed as the snapshot
                    if not identity.startswith('ok '): raise RuntimeError(identity)
                    if json.loads(identity[3:]).get('device_id')!=device: raise RuntimeError('摄像头设备编号不匹配')
                    busy_until=time.monotonic()+6
                    while True:  # r2 firmware stays busy ~1 s after a frame while it powers the sensor down
                        try: header=self.camera_exchange(s,'camera capture '+frame_id,('frame '+frame_id+' ',),10).split(); break
                        except RuntimeError as e:
                            if 'camera_busy' not in str(e) or time.monotonic()>busy_until: raise
                            time.sleep(.3); s.reset_input_buffer()
                    size=int(header[2]); checksum=int(header[3],16)
                    if not 4<=size<=262144: raise RuntimeError('Camera frame size limit')
                    frame=bytearray(); deadline=time.monotonic()+90
                    try:
                        while len(frame)<size:
                            offset=len(frame)
                            # USB full packets are occasionally lost: re-request the same offset (idempotent read), never skip bytes.
                            for attempt in range(5):
                                if time.monotonic()>deadline: raise RuntimeError('Camera transfer deadline')
                                if attempt: time.sleep(.15); s.reset_input_buffer()
                                try:
                                    row=self.camera_exchange(s,f'camera chunk {frame_id} {offset}',(f'jpeg {frame_id} {offset} ',),.6).split()
                                    chunk=bytes.fromhex(row[3])
                                except (CameraTimeout,ValueError,IndexError): continue
                                if len(chunk)==min(1024,size-offset): break
                            else: raise RuntimeError(f'Camera chunk failed after 5 attempts at offset {offset}')
                            frame.extend(chunk)
                        if zlib.adler32(frame)!=checksum: raise RuntimeError('Camera frame checksum mismatch')
                        if not frame.startswith(b'\xff\xd8') or not frame.endswith(b'\xff\xd9'): raise RuntimeError('Invalid camera JPEG')
                        return bytes(frame)
                    finally:
                        self.camera_exchange(s,'camera close '+frame_id,('ok camera closed',),2)
            except serial.SerialException:
                self.port=None; raise


    # ---- fast path (firmware with `camera read`): persistent port, binary windows, sensor stays open ----
    def _cam_open(self,keep_identity=False):
        if self.cam is None:
            if not self.port: self.find()
            self.cam=serial.Serial(self.port,115200,timeout=.02,write_timeout=1); self.cam_buf=b''
            if keep_identity: self._cam_drain(.3)          # mid-stream reopen: keep async capture results
            else: self.cam_identity=None; time.sleep(.3); self.cam.reset_input_buffer()  # new session: stale replies are not ours
        return self.cam

    def _cam_drop(self,forget_port=False):
        try:
            if self.cam: self.cam.close()
        except Exception: pass
        self.cam=None; self.cam_buf=b''; self.headers={}
        if forget_port: self.port=None

    def _cam_drain(self,seconds):
        """Discard stale bytes for `seconds`, but keep any capture result line that arrives meanwhile: the header of a
        prefetched frame is asynchronous and dropping it costs a 4 s header timeout plus a re-capture (seen 2026-09-22)."""
        end=time.monotonic()+seconds; buf=self.cam_buf
        while time.monotonic()<end:
            got=self.cam.read(self.cam.in_waiting or 1)
            if got: buf+=got
            else: time.sleep(.01)
        for m in re.finditer(rb'(?:^|\n)((?:frame|err camera) [0-9a-f]{32} [^\r\n]*)',buf):
            row=m.group(1).decode('ascii','replace'); parts=row.split()
            if len(parts)>=3: self.headers[parts[1] if parts[0]=='frame' else parts[2]]=(parts,time.monotonic())
        self.cam_buf=b''

    def _cam_fill(self,deadline):
        if time.monotonic()>deadline: raise CameraTimeout('摄像头响应超时；未收到新画面')
        got=self.cam.read(self.cam.in_waiting or 1)
        self.cam_buf+=got
        if len(self.cam_buf)>400000: raise RuntimeError('Oversized camera response')

    def _cam_line(self,deadline):
        while b'\n' not in self.cam_buf: self._cam_fill(deadline)
        row,self.cam_buf=self.cam_buf.split(b'\n',1)
        return row.decode('ascii','replace').strip()

    ASYNC=re.compile(r'(frame|err camera) ([0-9a-f]{32}) ')
    def _cam_wait(self,prefixes,seconds):
        """Next reply line starting with one of prefixes. Every command is request->reply, except the result of a
        capture (`frame <id> ..` / `err camera <id> ..`), which arrives whenever the sensor is done: stash those."""
        deadline=time.monotonic()+seconds
        while True:
            row=self._cam_line(deadline)
            m=self.ASYNC.match(row)
            if m: self.headers[m.group(2)]=(row.split(),time.monotonic())
            elif row.startswith(prefixes): return row

    def _cam_capture(self,fid):
        """Schedule a capture; False if the sensor is still finishing the previous one."""
        self._cam_send('camera capture '+fid)
        row=self._cam_wait(('ok camera scheduled','err camera '),2)
        if row.startswith('ok'): return True
        if 'camera_busy' in row: return False
        raise RuntimeError(row)

    def _cam_send(self,line):
        self.cam.write((line+'\n').encode())

    def _cam_header(self,fid,seconds=12):
        deadline=time.monotonic()+seconds
        while fid not in self.headers:
            row=self._cam_line(deadline); m=self.ASYNC.match(row)
            if m: self.headers[m.group(2)]=(row.split(),time.monotonic())
        parts,t=self.headers.pop(fid)
        if parts[0]!='frame' or len(parts)<4: raise RuntimeError(' '.join(parts))
        return parts,t

    def _cam_fresh_capture(self):
        end=time.monotonic()+6
        while True:
            fid=uuid.uuid4().hex
            if self._cam_capture(fid): return fid
            if time.monotonic()>end: raise RuntimeError('err camera camera_busy')
            time.sleep(.2)

    def camera_pull(self,device,prefetch=True):
        """One fresh frame: (jpeg bytes, monotonic time its capture finished). Lock is taken per step so
        snapshot/command calls can interleave between windows."""
        with self.lock:
            try:
                s=self._cam_open()
                if self.cam_identity!=device:
                    s.reset_input_buffer(); self.cam_buf=b''; self._cam_send('snapshot')
                    identity=self._cam_wait(('ok {','err '),3)  # same narrowing as snapshot(): async `ok ...` lines are not the reply
                    if not identity.startswith('ok '): raise RuntimeError(identity)
                    if json.loads(identity[3:]).get('device_id')!=device: raise RuntimeError('摄像头设备编号不匹配')
                    self.cam_identity=device
                    if self.camera_config:
                        self._cam_send('camera config '+self.camera_config); self._cam_wait(('ok camera config',),2)
                fid=self.next_id
                prefetched=bool(fid); self.next_id=None
                if not fid: fid=self._cam_fresh_capture()
                try: parts,captured=self._cam_header(fid,1.2 if prefetched else 12)
                except CameraTimeout:
                    # A snapshot/command exchange on the same tty can swallow the async header of a prefetched capture.
                    if not prefetched: raise
                    fid=self._cam_fresh_capture(); parts,captured=self._cam_header(fid)
                size=int(parts[2]); checksum=int(parts[3],16); algo=parts[4] if len(parts)>4 else 'adler32'
                if not 4<=size<=262144: raise RuntimeError('Camera frame size limit')
                if prefetch:  # sensor captures the next frame while this one is transferred
                    nxt=uuid.uuid4().hex
                    if self._cam_capture(nxt): self.next_id=nxt
            except serial.SerialException:
                self._cam_drop(True); self.next_id=None; raise
            except Exception:
                self._cam_drop(); self.next_id=None; raise
        frame=bytearray(); deadline=time.monotonic()+30
        try:
            while len(frame)<size:
                offset=len(frame)
                attempt=0; busy_polls=0
                while True:
                    if time.monotonic()>deadline: raise RuntimeError('Camera transfer deadline')
                    if attempt>=12: raise RuntimeError(f'Camera window failed after 12 attempts at offset {offset}')
                    want=min(self.window,size-offset)
                    with self.lock:
                        try:
                            if attempt or busy_polls: self._cam_drain(.15)  # never tcflush mid-stream: macOS CDC can wedge with data in flight
                            self._cam_send(f'camera read {fid} {offset} {want}')
                            row=self._cam_wait((f'jpegbin {fid} {offset} ','err camera '),.6)
                            if row.startswith('err camera tx_busy'):
                                # device is still flushing a window we gave up on: let it finish, this is not a failed attempt
                                busy_polls+=1
                                if busy_polls>40: raise RuntimeError('Camera transmitter stuck busy')
                                continue
                            if row.startswith('err '): raise RuntimeError(row)  # `unknown operation` = 003 r2 firmware: caller falls back to hex chunks
                            row=row.split()
                            n=int(row[3]); end=time.monotonic()+.3+n/20000
                            while len(self.cam_buf)<n: self._cam_fill(end)
                            chunk,self.cam_buf=self.cam_buf[:n],self.cam_buf[n:]
                        except CameraTimeout:
                            # Board 1 (2026-09-22): after a lost window the module's USB TX wedges and stays silent until the host
                            # closes and reopens the tty. Reopening is ~0.3 s; blind retries on the same handle stalled 20 s+.
                            attempt+=1; self.window=max(1024,self.window//2); self.clean=0
                            self._cam_drop(); self._cam_open(keep_identity=True); continue
                        except (ValueError,IndexError): attempt+=1; continue
                    if n==want: break
                    attempt+=1
                frame.extend(chunk)
                # Adaptive: after 32 clean windows in a row try a bigger window again (loss rate depends on what else the module is doing)
                self.clean+=1
                if self.clean>=32 and self.window<self.max_window: self.window=min(self.max_window,self.window*2); self.clean=0
            digest=zlib.crc32(frame) if algo=='crc32' else zlib.adler32(frame)
            if digest!=checksum: raise RuntimeError('Camera frame checksum mismatch')
            if not frame.startswith(b'\xff\xd8') or not frame.endswith(b'\xff\xd9'): raise RuntimeError('Invalid camera JPEG')
            return bytes(frame),captured
        except serial.SerialException:
            with self.lock: self._cam_drop(True); self.next_id=None
            raise
        except Exception:
            with self.lock: self._cam_drop(); self.next_id=None
            raise
        finally:
            with self.lock:
                try:
                    if self.cam: self._cam_send('camera close '+fid); self._cam_wait(('ok camera closed','err camera '),.5)
                except Exception: pass

    def camera_frame(self,device):
        """HTTP entry: a frame never served before, captured after the previous one. A background streamer
        keeps capturing only while requests keep arriving (stops 2 s after the last one)."""
        if self.legacy: return self.camera_frame_legacy(device)
        with self.stream_cv:
            self.last_request=time.monotonic(); arrived=self.last_request; self.stream_error=None
            if not self.stream_thread:
                self.stream_thread=threading.Thread(target=self._stream,args=(device,),daemon=True); self.stream_thread.start()
            while True:
                # Fresh only: captured no earlier than 0.5 s before this request arrived (never a leftover of an earlier stream).
                if self.latest and self.latest[0]>self.served and self.latest[2]>=arrived-.5:
                    self.served=self.latest[0]; self.last_request=time.monotonic(); return self.latest[1]
                if self.stream_error and not self.stream_thread:
                    e=self.stream_error
                    if 'unknown operation' in str(e): self.legacy=True; break
                    raise e
                if time.monotonic()-arrived>40: raise RuntimeError('摄像头响应超时；未收到新画面')
                self.stream_cv.wait(.25)
                if not self.stream_thread and not self.stream_error:
                    self.stream_thread=threading.Thread(target=self._stream,args=(device,),daemon=True); self.stream_thread.start()
        return self.camera_frame_legacy(device)

    def _stream(self,device):
        try:
            while time.monotonic()-self.last_request<2.0:
                t=time.monotonic(); data,captured=self.camera_pull(device,prefetch=self.prefetch)
                with self.stream_cv:
                    self.seq+=1; self.latest=(self.seq,data,captured); self.stats=(len(data),time.monotonic()-t,self.window)
                    self.stream_cv.notify_all()
        except Exception as e:
            with self.stream_cv: self.stream_error=e
        finally:
            with self.lock:
                self.next_id=None
            with self.stream_cv: self.stream_thread=None; self.stream_cv.notify_all()

class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args): pass # don't log tokens, command payloads or GPS locations
    def send(self,status,payload):
        body=json.dumps(payload,ensure_ascii=False,allow_nan=False).encode()
        self.send_response(status); self.send_header('Content-Type','application/json; charset=utf-8')
        self.send_header('Cache-Control','no-store'); self.send_header('Content-Length',str(len(body)))
        self.end_headers(); self.wfile.write(body)
    def authorized(self):
        # Prevent browser CSRF/DNS rebinding; no CORS and no public unauthenticated listener.
        host=self.headers.get('Host','').split(':')[0]
        if self.headers.get('Origin') or host not in ('127.0.0.1','localhost'):
            self.send(403,{'error':'Loopback native client only'}); return False
        if self.server.token and self.headers.get('Authorization')!='Bearer '+self.server.token:
            self.send(401,{'error':'Invalid Bearer token'}); return False
        return True
    def route(self):
        return re.fullmatch(r'/v1/devices/([a-zA-Z0-9_-]{1,64})/(snapshot|commands)(?:/([a-zA-Z0-9-]{8,64}))?/?',self.path)
    def do_GET(self):
        if not self.authorized(): return
        cam=re.fullmatch(r'/v1/devices/([a-zA-Z0-9_-]{1,64})/camera/frame',self.path)
        if cam:
            if cam.group(1)!=self.server.device: return self.send(404,{'error':'Unknown device'})
            try:
                frame=self.server.gateway.camera_frame(cam.group(1))
                self.send_response(200); self.send_header('Content-Type','image/jpeg')
                self.send_header('Cache-Control','no-store'); self.send_header('Content-Length',str(len(frame)))
                self.end_headers(); self.wfile.write(frame); return
            except (RuntimeError,serial.SerialException,ValueError,IndexError,KeyError) as e:
                return self.send(503,{'error':str(e)})
        m=self.route()
        if not m: return self.send(404,{'error':'Unknown AIR endpoint'})
        device,kind,cid=m.groups()
        if device!=self.server.device: return self.send(404,{'error':'Unknown device'})
        try:
            if kind=='snapshot' and not cid: return self.send(200,self.server.gateway.snapshot(device))
            if kind=='commands' and cid:
                with self.server.command_lock: record=self.server.commands.get(cid)
                if not record: return self.send(404,{'error':'Unknown command'})
                c,created=record
                if time.monotonic()-created>180: return self.send(410,{'error':'Command observation expired'})
                # Replay SAME id to obtain firmware's persisted result; never issue another action id.
                return self.send(200,self.server.gateway.command(c))
            return self.send(404,{'error':'Unknown endpoint'})
        except (RuntimeError,serial.SerialException,ValueError) as e: self.send(503,{'error':str(e)})
    def do_POST(self):
        if not self.authorized(): return
        m=self.route()
        if not m or m.group(2)!='commands' or m.group(3): return self.send(404,{'error':'Unknown command endpoint'})
        device=m.group(1)
        if device!=self.server.device: return self.send(404,{'error':'Unknown device'})
        if self.headers.get('Content-Type','').split(';')[0]!='application/json': return self.send(415,{'error':'JSON required'})
        try:
            n=int(self.headers.get('Content-Length','0'))
            if not 0<n<=1800: return self.send(413,{'error':'Command size limit'})
            c=json.loads(self.rfile.read(n))
            if not isinstance(c,dict) or not isinstance(c.get('id'),str) or not re.fullmatch(r'[a-zA-Z0-9-]{8,64}',c['id']): return self.send(400,{'error':'Invalid command id'})
            if c.get('device_id')!=device: return self.send(400,{'error':'Wrong device'})
            if c.get('type') not in ('GET_STATE','LOCATE_NOW','SET_MODE','SET_GEOFENCE','LED','VIBRATE','STOP','BUZZ'): return self.send(422,{'error':'Hardware feature not implemented/verified'})
            with self.server.command_lock:
                self.server.commands={k:v for k,v in self.server.commands.items() if time.monotonic()-v[1]<=180}
                if len(self.server.commands)>=128: return self.send(429,{'error':'Too many commands'})
                previous=self.server.commands.get(c['id'])
                if previous and previous[0]!=c: return self.send(409,{'error':'Command id reused with different arguments'})
            a=self.server.gateway.command(c)
            with self.server.command_lock: self.server.commands[c['id']]=(c,time.monotonic())
            self.send(202 if a['status']=='accepted' else 200,a)
        except (RuntimeError,serial.SerialException,ValueError,KeyError) as e: self.send(503,{'error':str(e)})

if __name__=='__main__':
    p=argparse.ArgumentParser()
    p.add_argument('--port'); p.add_argument('--http-port',type=int,default=8210)
    p.add_argument('--device',default='collar-evt-001')
    p.add_argument('--window',type=int,default=4096,help='binary read window (bytes, halves itself on loss, max 16384)')
    p.add_argument('--no-prefetch',action='store_true',help='do not capture the next frame during transfer')
    # crc32 runs in the module's C core; the Lua adler32 loop costs ~1.3 s per 75 KB frame (measured 2026-09-20: 0.70 -> 6.9 fps)
    p.add_argument('--camera-config',default='sum=crc32',help="sent once as `camera config ...`, e.g. 'sum=crc32 x=160 y=120 w=320 h=240'")
    p.add_argument('--legacy-camera',action='store_true',help='force the 003 r2 hex chunk protocol')
    a=p.parse_args()
    server=ThreadingHTTPServer(('127.0.0.1',a.http_port),Handler)
    server.token=os.environ.get('PETPAL_BRIDGE_TOKEN','')
    server.device=a.device; server.gateway=USBGateway(a.port,min(16384,max(1024,a.window)),not a.no_prefetch,a.camera_config,a.legacy_camera)
    server.commands={}; server.command_lock=threading.Lock()
    print(f'AIR iOS bench bridge: http://127.0.0.1:{a.http_port} (real USB only, no mocked hardware)',flush=True)
    server.serve_forever()
