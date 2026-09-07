#!/usr/bin/env python3
"""Compare collar telemetry positions with a phone GPX reference track (TP-09).

Usage:
    gnss_accuracy.py telemetry.jsonl reference.gpx [--max-dt 5] [--route R1] [--json]
Error for each GNSS/LBS fix = haversine distance to the reference point nearest in time
(within --max-dt seconds, after subtracting fix_age_s).
"""
import argparse, json, math, sys, bisect, datetime, xml.etree.ElementTree as ET

def hav(lat1, lon1, lat2, lon2):
    R = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    h = math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return 2 * R * math.asin(math.sqrt(h))

def load_gpx(path):
    ns = {"g": "http://www.topografix.com/GPX/1/1"}
    root = ET.parse(path).getroot()
    pts = []
    for tp in root.iter("{http://www.topografix.com/GPX/1/1}trkpt"):
        t = tp.find("g:time", ns)
        if t is None: continue
        ts = datetime.datetime.fromisoformat(t.text.replace("Z", "+00:00")).timestamp()
        pts.append((ts, float(tp.get("lat")), float(tp.get("lon"))))
    pts.sort()
    return pts

def pct(v, p):
    if not v: return None
    v = sorted(v); k = (len(v)-1)*p; lo, hi = int(k), min(int(k)+1, len(v)-1)
    return v[lo] + (v[hi]-v[lo])*(k-lo)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("telemetry"); ap.add_argument("gpx")
    ap.add_argument("--max-dt", type=float, default=5.0); ap.add_argument("--route", default="")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    ref = load_gpx(a.gpx)
    if not ref: sys.exit("no trkpt with time in gpx")
    rts = [p[0] for p in ref]
    errs = {"gnss": [], "lbs": []}; attempts = 0; zero = 0; unmatched = 0
    with open(a.telemetry, encoding="utf-8") as f:
        for line in f:
            if not line.strip(): continue
            r = json.loads(line); attempts += 1
            p = r.get("position")
            if not p: continue
            if abs(p["lat"]) < 1e-6 and abs(p["lng"]) < 1e-6: zero += 1; continue
            t = r["ts"] - p.get("fix_age_s", 0)
            k = bisect.bisect_left(rts, t)
            cands = [ref[j] for j in (k-1, k) if 0 <= j < len(ref)]
            best = min(cands, key=lambda c: abs(c[0]-t), default=None)
            if best is None or abs(best[0]-t) > a.max_dt: unmatched += 1; continue
            errs[p["source"]].append(hav(p["lat"], p["lng"], best[1], best[2]))
    g = errs["gnss"]; l = errs["lbs"]
    out = {"route": a.route, "attempts": attempts, "gnss_fixes": len(g), "lbs_fixes": len(l),
           "fix_success_rate": round((len(g)+len(l))/attempts, 4) if attempts else None,
           "gnss_err_median_m": pct(g, .5), "gnss_err_p95_m": pct(g, .95), "gnss_err_max_m": max(g) if g else None,
           "lbs_err_median_m": pct(l, .5), "zero_coord_count": zero, "unmatched_to_reference": unmatched,
           "pass_median_le_10m": (pct(g, .5) or 1e9) <= 10 and zero == 0}
    if a.json: print(json.dumps(out, indent=2))
    else:
        for k, v in out.items(): print(f"{k}: {v}")
    sys.exit(0 if out["pass_median_le_10m"] else 1)

if __name__ == "__main__":
    main()
