"""PetPal cloud bridge: the App's HTTP API (same contract as apps/bridge/air_bridge.py) backed by MQTT instead of USB.

  App  --HTTPS (Tailscale Funnel)-->  this service  --MQTT-->  Mosquitto  <--4G/TLS--  collars

Real data only: a device is "online" only while its retained state says so and telemetry keeps arriving; commands are
answered only with acknowledgements the collar itself published. No camera path here (4G bandwidth/traffic budget).

  MQTT_HOST/MQTT_PORT/MQTT_USER/MQTT_PASS   broker (backend account, ACL petpal/v1/#)
  PETPAL_BRIDGE_TOKEN                        required: every request needs `Authorization: Bearer <token>`
  HTTP_PORT (default 8211)                   listens on 127.0.0.1 only; publish it with `tailscale funnel 443`
"""
import json
import os
import re
import ssl
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import paho.mqtt.client as mqtt

TOPIC_RE = re.compile(r'^petpal/v1/([A-Za-z0-9_-]{1,64})/(state|telemetry|event|ack|log)$')
LOG_KEEP = 600            # lines kept per device (RAM only)
HISTORY_S = 24 * 3600     # telemetry samples kept per device for the App's data panel
HISTORY_FILE = os.environ.get('HISTORY_FILE', '')   # optional persistence across restarts
ONLINE_GRACE_S = 300        # telemetry period is 30..60 s on the bench; 5 min without any message = offline
ACK_WAIT_S = 8.0            # collar answered in ~1 s over 4G on 2026-09-22; wait a little longer before giving up
ACK_KEEP_S = 600


class Fleet:
    """Latest known facts per device, filled only from what the collars publish."""
    def __init__(self):
        self.lock = threading.Lock()
        self.cv = threading.Condition(self.lock)
        self.devices = {}          # id -> {'state':..., 'telemetry':..., 'seen': monotonic, 'history': [...]}
        self.acks = {}             # command id -> (ack, monotonic)
        self.dirty = False
        if HISTORY_FILE and os.path.exists(HISTORY_FILE):
            try:
                for dev, h in json.load(open(HISTORY_FILE)).items():
                    if re.fullmatch(r'[A-Za-z0-9_-]{1,64}', dev) and isinstance(h, list):
                        self.devices.setdefault(dev, {'seen': time.monotonic() - ONLINE_GRACE_S})['history'] = h[-3000:]
            except Exception: pass

    def save(self):
        if not HISTORY_FILE or not self.dirty: return
        with self.lock:
            data = {dev: rec.get('history', []) for dev, rec in self.devices.items() if rec.get('history')}
            self.dirty = False
        tmp = HISTORY_FILE + '.tmp'
        with open(tmp, 'w') as f: json.dump(data, f)
        os.replace(tmp, HISTORY_FILE)

    def history(self, dev, hours):
        with self.lock:
            rec = self.devices.get(dev)
            if rec is None: return None
            cutoff = time.time() - hours * 3600
            return [x for x in rec.get('history', []) if x['received_ts'] >= cutoff]

    def ingest(self, topic, payload):
        m = TOPIC_RE.match(topic)
        if not m:
            return
        dev, kind = m.groups()
        try:
            d = json.loads(payload)
        except Exception:
            return
        if not isinstance(d, dict):
            return
        with self.cv:
            rec = self.devices.setdefault(dev, {})
            rec['seen'] = time.monotonic()
            if kind == 'ack':
                if isinstance(d.get('id'), str):
                    self.acks[d['id']] = (d, time.monotonic())
                    self.cv.notify_all()
            elif kind == 'log' or (kind == 'event' and d.get('type') in ('log_error', 'log_prev_boot')):
                # collar log lines: on-demand LOG_UPLOAD chunks, automatic error snapshots, previous-boot crash context
                src = d.get('lines') if kind == 'log' else (d.get('data') or {}).get('lines')
                if isinstance(src, list):
                    tag = kind if kind == 'log' else d.get('type')
                    logs = rec.setdefault('logs', [])
                    logs.extend({'received_ts': time.time(), 'source': tag, 'line': str(l)[:200]} for l in src if isinstance(l, str))
                    del logs[:-LOG_KEEP]
                if kind == 'event': rec[kind] = d
            else:
                rec[kind] = d
                if kind == 'telemetry':
                    # compact sample for trend charts; only fields the collar actually sent
                    b = d.get('battery') or {}; r = d.get('radio') or {}; mo = d.get('motion') or {}; p = d.get('position')
                    ts = d.get('ts') if isinstance(d.get('ts'), (int, float)) and d.get('ts') >= 1700000000 else time.time()
                    h = rec.setdefault('history', [])
                    h.append({'ts': ts, 'received_ts': time.time(), 'seq': d.get('seq'), 'pct': b.get('pct'), 'mv': b.get('mv'), 'charging': b.get('charging'),
                              'rsrp': r.get('rsrp_dbm'), 'rssi': r.get('rssi_dbm'), 'motion': mo.get('state'), 'activity': mo.get('activity'),
                              'active_s': mo.get('active_s'), 'steps': mo.get('steps'), 'fix': bool(p) and (p.get('fix_age_s') or 0) <= 120,
                              'sats': (p or {}).get('sats'), 'mode': d.get('mode')})
                    cutoff = time.time() - HISTORY_S
                    while h and h[0]['received_ts'] < cutoff: h.pop(0)
                    self.dirty = True
            if len(self.acks) > 512:
                cutoff = time.monotonic() - ACK_KEEP_S
                self.acks = {k: v for k, v in self.acks.items() if v[1] >= cutoff}

    def snapshot(self, dev):
        with self.lock:
            rec = self.devices.get(dev)
            if not rec or 'telemetry' not in rec:
                return None
            t = dict(rec['telemetry'])
            st = rec.get('state') or {}
            age = time.monotonic() - rec['seen']
            online = bool(st.get('online', True)) and age < ONLINE_GRACE_S
            # fix_age_s was computed on the collar when it sent this telemetry; add the time it has been sitting here
            p = t.get('position')
            if isinstance(p, dict) and isinstance(p.get('fix_age_s'), (int, float)):
                p = dict(p); p['fix_age_s'] = int(p['fix_age_s'] + age); t['position'] = p
            return {'device_id': dev, 'online': online, 'last_seen_ts': time.time() - age,
                    'transport': 'mqtt-4g', 'state': st, 'telemetry': t}

    def logs(self, dev, n):
        with self.lock:
            rec = self.devices.get(dev)
            if not rec: return None
            return list(rec.get('logs', []))[-n:]

    def wait_ack(self, cid, seconds, after=None):
        """Newest ack for cid; waits up to `seconds` for one newer than `after` (a monotonic time)."""
        deadline = time.monotonic() + seconds
        with self.cv:
            while True:
                a = self.acks.get(cid)
                if a and (after is None or a[1] >= after):
                    return a[0]
                left = deadline - time.monotonic()
                if left <= 0:
                    return a[0] if a else None
                self.cv.wait(left)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a): pass   # no tokens, command payloads or positions in logs

    def send(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False, allow_nan=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers(); self.wfile.write(body)

    def authorized(self):
        if self.headers.get('Origin'):
            self.send(403, {'error': 'Native client only'}); return False
        if self.headers.get('Authorization') != 'Bearer ' + self.server.token:
            self.send(401, {'error': 'Invalid Bearer token'}); return False
        return True

    def route(self):
        return re.fullmatch(r'/v1/devices/([A-Za-z0-9_-]{1,64})/(snapshot|commands|camera/frame|logs|history)(?:/([A-Za-z0-9-]{8,64}))?(?:\?[a-z]+=\d{1,4})?/?', self.path)

    def do_GET(self):
        if not self.authorized(): return
        m = self.route()
        if not m: return self.send(404, {'error': 'Unknown endpoint'})
        dev, kind, cid = m.groups()
        if kind == 'camera/frame':
            return self.send(503, {'error': '远程实况未启用：4G 链路只传状态与命令，实况请用 USB 台架'})
        if kind == 'logs' and not cid:
            m2 = re.search(r'[?&]lines=(\d+)', self.path); n = min(600, max(1, int(m2.group(1)) if m2 else 100))
            lines = self.server.fleet.logs(dev, n)
            if lines is None: return self.send(503, {'error': '项圈尚未通过 4G 上报过状态'})
            return self.send(200, {'device_id': dev, 'lines': lines, 'hint': '项圈只在 LOG_UPLOAD 命令后或出错时上传日志；平时这里为空'})
        if kind == 'history' and not cid:
            m2 = re.search(r'[?&]hours=(\d+)', self.path); hours = min(24, max(1, int(m2.group(1)) if m2 else 24))
            h = self.server.fleet.history(dev, hours)
            if h is None: return self.send(503, {'error': '项圈尚未通过 4G 上报过状态'})
            return self.send(200, {'device_id': dev, 'hours': hours, 'period_s': 60, 'samples': h})
        if kind == 'snapshot' and not cid:
            s = self.server.fleet.snapshot(dev)
            if not s: return self.send(503, {'error': '项圈尚未通过 4G 上报过状态'})
            return self.send(200, s)
        if kind == 'commands' and cid:
            a = self.server.fleet.wait_ack(cid, 0)
            if not a: return self.send(404, {'error': 'Unknown command'})
            return self.send(200, a)
        self.send(404, {'error': 'Unknown endpoint'})

    def do_POST(self):
        if not self.authorized(): return
        m = self.route()
        if not m or m.group(2) != 'commands' or m.group(3): return self.send(404, {'error': 'Unknown command endpoint'})
        dev = m.group(1)
        if self.headers.get('Content-Type', '').split(';')[0] != 'application/json': return self.send(415, {'error': 'JSON required'})
        try:
            n = int(self.headers.get('Content-Length', '0'))
            if not 0 < n <= 1800: return self.send(413, {'error': 'Command size limit'})
            c = json.loads(self.rfile.read(n))
        except Exception:
            return self.send(400, {'error': 'Invalid JSON'})
        if not isinstance(c, dict) or not isinstance(c.get('id'), str) or not re.fullmatch(r'[a-zA-Z0-9-]{8,64}', c['id']):
            return self.send(400, {'error': 'Invalid command id'})
        if c.get('device_id') != dev: return self.send(400, {'error': 'Wrong device'})
        if c.get('type') not in ('GET_STATE', 'LOCATE_NOW', 'SET_MODE', 'SET_GEOFENCE', 'LED', 'VIBRATE', 'STOP', 'BUZZ', 'LOG_UPLOAD', 'GSENSOR_TUNE'):
            return self.send(422, {'error': 'Hardware feature not implemented/verified'})
        if not self.server.fleet.snapshot(dev):
            return self.send(503, {'error': '项圈离线或从未上线，命令未发送'})
        # Same id again = replay of the same envelope; the collar's dedup answers with the stored ack, never re-executes.
        sent_at = time.monotonic()
        info = self.server.mqtt.publish(f'petpal/v1/{dev}/cmd', json.dumps(c, separators=(',', ':'), allow_nan=False), qos=1)
        if info.rc != mqtt.MQTT_ERR_SUCCESS:
            return self.send(503, {'error': 'MQTT publish failed'})
        a = self.server.fleet.wait_ack(c['id'], ACK_WAIT_S, after=sent_at)
        if not a:
            return self.send(504, {'error': '项圈未在 %d 秒内回执；命令可能仍在路上，不会自动重发' % ACK_WAIT_S})
        self.send(202 if a.get('status') == 'accepted' else 200, a)


def main():
    token = os.environ.get('PETPAL_BRIDGE_TOKEN', '')
    if len(token) < 16:
        sys.exit('PETPAL_BRIDGE_TOKEN (>=16 chars) is required: this service is reachable from the internet')
    fleet = Fleet()
    cl = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id='petpal-cloud-bridge', protocol=mqtt.MQTTv311)
    cl.username_pw_set(os.environ['MQTT_USER'], os.environ['MQTT_PASS'])
    if os.environ.get('MQTT_TLS') == '1':
        cl.tls_set(tls_version=ssl.PROTOCOL_TLS_CLIENT)
    cl.on_connect = lambda c, u, f, rc, p=None: c.subscribe([('petpal/v1/+/state', 1), ('petpal/v1/+/telemetry', 1), ('petpal/v1/+/event', 1), ('petpal/v1/+/ack', 1), ('petpal/v1/+/log', 1)])
    cl.on_message = lambda c, u, m: fleet.ingest(m.topic, m.payload)
    cl.reconnect_delay_set(2, 30)
    cl.connect(os.environ.get('MQTT_HOST', '127.0.0.1'), int(os.environ.get('MQTT_PORT', '1883')), keepalive=60)
    cl.loop_start()
    port = int(os.environ.get('HTTP_PORT', '8211'))
    server = ThreadingHTTPServer(('127.0.0.1', port), Handler)
    server.token = token; server.fleet = fleet; server.mqtt = cl
    def saver():
        while True:
            time.sleep(120)
            try: fleet.save()
            except Exception as e: print('history save failed:', e, flush=True)
    threading.Thread(target=saver, daemon=True).start()
    print(f'PetPal cloud bridge on 127.0.0.1:{port} (MQTT-backed, bearer token required)', flush=True)
    server.serve_forever()


if __name__ == '__main__':
    main()
