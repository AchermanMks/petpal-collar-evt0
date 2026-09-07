#!/usr/bin/env python3
"""Generate synthetic data and run every analysis tool once. Exit 0 if all behave."""
import json, math, random, subprocess, sys, tempfile, time, datetime
from pathlib import Path
T = Path(__file__).resolve().parent
d = Path(tempfile.mkdtemp(prefix="petpal-selftest-"))
ok = True
def run(args, expect):
    r = subprocess.run([sys.executable, *args], capture_output=True, text=True)
    good = (r.returncode == 0) == expect
    print(("PASS" if good else "FAIL"), " ".join(str(x) for x in args), f"(rc={r.returncode})")
    if not good: print(r.stdout, r.stderr)
    return good

# telemetry: 300 good records, one reboot gap explained by event
now = int(time.time()); tel = d / "telemetry.jsonl"; ev = d / "events.jsonl"
with tel.open("w") as f, ev.open("w") as e:
    seq = 0
    for k in range(300):
        seq += 1
        if k == 150:
            seq += 5; e.write(json.dumps({"v": 1, "device_id": "collar-evt-001", "seq": seq, "ts": now + k*30 - 5, "type": "reboot"}) + "\n")
        f.write(json.dumps({"v": 1, "device_id": "collar-evt-001", "seq": seq, "ts": now + k*30, "mode": "routine",
            "position": None if k % 40 == 0 else {"source": "gnss", "lat": 31.23 + k*1e-5, "lng": 121.47, "accuracy_m": 8.0, "fix_age_s": 2},
            **({"last_fix": {"ts": now + k*30 - 60, "lat": 31.23, "lng": 121.47, "source": "gnss"}} if k % 40 == 0 else {}),
            "motion": {"state": "moving", "steps": k*3}, "battery": {"pct": 80, "mv": 3900, "charging": False},
            "radio": {"rsrp_dbm": -95, "rssi_dbm": -70}, "fw": "evt0.0.1"}) + "\n")
ok &= run([T/"telemetry_validator.py", tel, "--events", ev], True)
bad = d / "bad.jsonl"; bad.write_text(tel.read_text().replace('"lat": 31.23', '"lat": 0.0', 1).replace('"lng": 121.47', '"lng": 0.0', 1))
ok &= run([T/"telemetry_validator.py", bad], False)

# commands / acks: 100 commands, one over-limit clamped correctly
cm = d / "commands.jsonl"; ak = d / "acks.jsonl"
with cm.open("w") as c, ak.open("w") as a:
    for k in range(100):
        cid = f"cmd-{k:04d}"; t0 = now + k*40
        args = {"duration_ms": 2000, "count": 10} if k == 7 else {"duration_ms": 200, "count": 2}
        c.write(json.dumps({"id": cid, "device_id": "collar-evt-001", "issued_at": t0, "expires_at": t0+30, "type": "VIBRATE", "args": args, "sent_at": t0}) + "\n")
        a.write(json.dumps({"id": cid, "device_id": "collar-evt-001", "ts": t0+1, "status": "accepted", "recv_at": t0+1}) + "\n")
        lat = random.uniform(1.5, 6)
        applied = {"duration_ms": 500, "count": 3} if k == 7 else args
        a.write(json.dumps({"id": cid, "device_id": "collar-evt-001", "ts": int(t0+lat), "status": "executed", "recv_at": t0+lat,
                            **({"reason": "limit_clamped"} if k == 7 else {}), "applied_args": applied}) + "\n")
ok &= run([T/"ack_checker.py", cm, ak], True)

# power: 1 h synthetic routine profile: 0.8 mA sleep, 80 mA bursts every 5 min, 700 mA peaks
pw = d / "routine.csv"
with pw.open("w") as f:
    f.write("Timestamp(ms),Current(uA)\n")
    for ms in range(0, 3600*1000, 10):
        i = 800.0
        if (ms // 1000) % 300 < 20: i = 80000.0
        if (ms // 1000) % 300 == 10 and ms % 1000 < 20: i = 700000.0
        f.write(f"{ms},{i}\n")
ok &= run([T/"power_analyzer.py", pw, "--scenario", "routine"], True)

# gnss: telemetry along a line vs gpx with 3 m noise
gpx = d / "ref.gpx"; tl = d / "walk.jsonl"
with gpx.open("w") as g, tl.open("w") as f:
    g.write('<?xml version="1.0"?><gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg>')
    for k in range(600):
        ts = now + k; lat = 31.2300 + k*1e-5; lon = 121.4700
        g.write(f'<trkpt lat="{lat}" lon="{lon}"><time>{datetime.datetime.fromtimestamp(ts, datetime.timezone.utc).isoformat().replace("+00:00","Z")}</time></trkpt>')
        if k % 30 == 0:
            f.write(json.dumps({"v": 1, "device_id": "collar-evt-001", "seq": k, "ts": ts, "mode": "lost",
                "position": {"source": "gnss", "lat": lat + random.uniform(-3e-5, 3e-5), "lng": lon + random.uniform(-3e-5, 3e-5), "accuracy_m": 6.0, "fix_age_s": 0},
                "battery": {"pct": 70, "mv": 3800, "charging": False}, "radio": {"rsrp_dbm": -90, "rssi_dbm": -65}, "fw": "evt0.0.1"}) + "\n")
    g.write("</trkseg></trk></gpx>")
ok &= run([T/"gnss_accuracy.py", tl, gpx, "--route", "R1"], True)
print("ALL PASS" if ok else "SOME FAILED", "| data in", d)
sys.exit(0 if ok else 1)
