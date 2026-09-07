#!/usr/bin/env python3
"""Simulated collar for backend / soak testing (方案 6 9/2, 9/25-27).

Publishes telemetry/state per the schemas, answers cmd with accepted→executed ACKs,
enforces the same safety limits the firmware must enforce, and can inject duplicates.

Env:  MQTT_HOST, MQTT_PORT (8883), MQTT_USER, MQTT_PASS, MQTT_TLS (1/0), MQTT_CA (path)
Usage:
    mqtt_sim.py --device collar-sim-001 [--period 30] [--mode routine] [--dup] [--lat 31.23 --lng 121.47]
                [--log-dir records/raw/sim]   # writes telemetry.jsonl / commands.jsonl / acks.jsonl
"""
import argparse, json, os, random, ssl, sys, time, threading
from pathlib import Path

LIMITS = {"duration_ms": 500, "count": 3}
COOLDOWN_S = 30

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--device", required=True)
    ap.add_argument("--period", type=float, default=30)
    ap.add_argument("--mode", default="routine", choices=["stationary", "routine", "lost", "low_power", "charging"])
    ap.add_argument("--dup", action="store_true", help="re-send every 10th telemetry with the same seq")
    ap.add_argument("--lat", type=float, default=31.2304); ap.add_argument("--lng", type=float, default=121.4737)
    ap.add_argument("--battery", type=int, default=90)
    ap.add_argument("--log-dir")
    a = ap.parse_args()
    try:
        import paho.mqtt.client as mqtt
    except ImportError:
        sys.exit("pip install -r tools/requirements.txt")

    host = os.environ.get("MQTT_HOST") or sys.exit("MQTT_HOST not set")
    port = int(os.environ.get("MQTT_PORT", "8883"))
    base = f"petpal/v1/{a.device}"
    logs = {}
    if a.log_dir:
        d = Path(a.log_dir); d.mkdir(parents=True, exist_ok=True)
        logs = {k: open(d / f"{k}.jsonl", "a", encoding="utf-8") for k in ("telemetry", "commands", "acks")}
    def log(k, obj):
        if k in logs: logs[k].write(json.dumps(obj) + "\n"); logs[k].flush()

    state = {"seq": 0, "mode": a.mode, "battery": a.battery, "last_cmd_ts": 0, "seen": set(), "lat": a.lat, "lng": a.lng}
    cl = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=a.device, clean_session=False)
    if os.environ.get("MQTT_USER"): cl.username_pw_set(os.environ["MQTT_USER"], os.environ.get("MQTT_PASS"))
    if os.environ.get("MQTT_TLS", "1") == "1":
        cl.tls_set(ca_certs=os.environ.get("MQTT_CA"), tls_version=ssl.PROTOCOL_TLS_CLIENT)
    cl.will_set(f"{base}/state", json.dumps({"v": 1, "device_id": a.device, "ts": int(time.time()), "online": False, "reason": "lwt"}), qos=1, retain=True)

    def ack(cid, status, reason=None, applied=None):
        m = {"id": cid, "device_id": a.device, "ts": int(time.time()), "status": status}
        if reason: m["reason"] = reason
        if applied: m["applied_args"] = applied
        cl.publish(f"{base}/ack", json.dumps(m), qos=1); m["recv_at"] = m["ts"]; log("acks", m)

    def on_cmd(client, userdata, msg):
        try: c = json.loads(msg.payload)
        except Exception: return
        c["sent_at"] = c.get("issued_at"); log("commands", c)
        cid, now = c.get("id"), int(time.time())
        if c.get("device_id", a.device) != a.device: return ack(cid, "rejected", "wrong_device")
        if cid in state["seen"]: return ack(cid, "rejected", "duplicate")
        state["seen"].add(cid)
        if c.get("expires_at", now+1) < now: return ack(cid, "rejected", "expired")
        ack(cid, "accepted")
        t = c.get("type"); args = dict(c.get("args") or {})
        if t == "VIBRATE":
            if state["mode"] in ("low_power", "charging"): return ack(cid, "rejected", state["mode"] if state["mode"] == "charging" else "low_battery")
            if now - state["last_cmd_ts"] < COOLDOWN_S: return ack(cid, "rejected", "cooldown")
            clamped = False
            for k, v in LIMITS.items():
                if args.get(k, 0) > v: args[k] = v; clamped = True
            state["last_cmd_ts"] = now
            time.sleep(min(args.get("duration_ms", 200)/1000 * args.get("count", 1), 2))
            return ack(cid, "executed", "limit_clamped" if clamped else None, args)
        if t == "SET_MODE":
            state["mode"] = args.get("mode", state["mode"]); return ack(cid, "executed")
        if t in ("LOCATE_NOW", "LED", "GET_STATE", "BUZZ"):
            return ack(cid, "executed")
        return ack(cid, "rejected", "unsupported")

    def on_connect(client, userdata, flags, rc, props=None):
        client.subscribe(f"{base}/cmd", qos=1)
        client.publish(f"{base}/state", json.dumps({"v": 1, "device_id": a.device, "ts": int(time.time()), "online": True,
                       "mode": state["mode"], "fw": "evt0.0.1", "reason": "boot", "cache_depth": 0}), qos=1, retain=True)
    cl.on_connect = on_connect; cl.on_message = on_cmd
    cl.connect(host, port, keepalive=60); cl.loop_start()

    try:
        while True:
            state["seq"] += 1
            state["lat"] += random.uniform(-2e-5, 2e-5); state["lng"] += random.uniform(-2e-5, 2e-5)
            if state["seq"] % 50 == 0 and state["battery"] > 5: state["battery"] -= 1
            m = {"v": 1, "device_id": a.device, "seq": state["seq"], "ts": int(time.time()), "mode": state["mode"],
                 "position": {"source": "gnss", "lat": round(state["lat"], 6), "lng": round(state["lng"], 6), "accuracy_m": round(random.uniform(4, 15), 1), "fix_age_s": random.randint(0, 10), "sats": random.randint(6, 12)},
                 "motion": {"state": "moving" if state["mode"] in ("routine", "lost") else "still", "steps": state["seq"] * 3},
                 "battery": {"pct": state["battery"], "mv": 3500 + state["battery"] * 7, "charging": state["mode"] == "charging"},
                 "radio": {"rsrp_dbm": random.randint(-110, -80), "rssi_dbm": random.randint(-85, -60)}, "fw": "evt0.0.1"}
            cl.publish(f"{base}/telemetry", json.dumps(m), qos=1); log("telemetry", m)
            if a.dup and state["seq"] % 10 == 0:
                cl.publish(f"{base}/telemetry", json.dumps(m), qos=1); log("telemetry", m)
            time.sleep(a.period if state["mode"] != "lost" else min(a.period, 15))
    except KeyboardInterrupt:
        pass
    finally:
        cl.publish(f"{base}/state", json.dumps({"v": 1, "device_id": a.device, "ts": int(time.time()), "online": False, "reason": "periodic"}), qos=1, retain=True)
        time.sleep(0.5); cl.loop_stop(); cl.disconnect()

if __name__ == "__main__":
    main()
