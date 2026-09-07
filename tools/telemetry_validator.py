#!/usr/bin/env python3
"""Validate a telemetry JSONL log against schemas/telemetry.schema.json and the
business rules in schemas/README.md (TP-04 A).

Usage:
    telemetry_validator.py telemetry.jsonl [--events events.jsonl] [--json]

Exit code 0 when every record passes and there are no unexplained seq gaps.
"""
import argparse, json, sys, collections
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def load_jsonl(path):
    out = []
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                out.append((n, json.loads(line)))
            except json.JSONDecodeError as e:
                out.append((n, {"__parse_error__": str(e)}))
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("telemetry")
    ap.add_argument("--events", help="event JSONL; reboot/watchdog events explain seq gaps")
    ap.add_argument("--json", action="store_true", help="machine-readable summary")
    a = ap.parse_args()

    try:
        import jsonschema
    except ImportError:
        sys.exit("pip install -r tools/requirements.txt")
    schema = json.load(open(ROOT / "schemas" / "telemetry.schema.json", encoding="utf-8"))
    validator = jsonschema.Draft202012Validator(schema)

    recs = load_jsonl(a.telemetry)
    reboot_ts = set()
    if a.events:
        for _, ev in load_jsonl(a.events):
            if ev.get("type") in ("reboot", "watchdog_reset"):
                reboot_ts.add((ev.get("device_id"), ev.get("ts")))

    per_dev = collections.defaultdict(list)
    errors, rule_errors = [], []
    for n, r in recs:
        if "__parse_error__" in r:
            errors.append((n, r["__parse_error__"])); continue
        errs = sorted(validator.iter_errors(r), key=lambda e: e.path)
        if errs:
            errors.append((n, "; ".join(e.message for e in errs))); continue
        p = r.get("position")
        if p and abs(p["lat"]) < 1e-6 and abs(p["lng"]) < 1e-6:
            rule_errors.append((n, "position 0,0 reported"))
        if p is None and "last_fix" not in r:
            rule_errors.append((n, "position null without last_fix"))
        per_dev[r["device_id"]].append((n, r))

    summary = {"records": len(recs), "schema_errors": len(errors), "rule_errors": len(rule_errors), "devices": {}}
    for dev, items in per_dev.items():
        items.sort(key=lambda x: x[1]["seq"])
        seqs = [r["seq"] for _, r in items]
        dups = [s for s, c in collections.Counter(seqs).items() if c > 1]
        gaps, unexplained = [], []
        for (n0, r0), (n1, r1) in zip(items, items[1:]):
            if r1["seq"] - r0["seq"] > 1:
                gap = (r0["seq"], r1["seq"])
                gaps.append(gap)
                explained = r1.get("replayed") or any(r0["ts"] <= ts <= r1["ts"] for d, ts in reboot_ts if d == dev)
                if not explained:
                    unexplained.append(gap)
        ts_back = sum(1 for (_, r0), (_, r1) in zip(items, items[1:]) if r1["ts"] < r0["ts"] and not r1.get("replayed"))
        summary["devices"][dev] = {
            "count": len(items), "seq_min": seqs[0], "seq_max": seqs[-1],
            "duplicates": len(dups), "gaps": len(gaps), "unexplained_gaps": unexplained,
            "ts_non_monotonic": ts_back,
            "position_null": sum(1 for _, r in items if r["position"] is None),
            "lbs": sum(1 for _, r in items if r["position"] and r["position"]["source"] == "lbs"),
            "modes": dict(collections.Counter(r["mode"] for _, r in items)),
        }

    if a.json:
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    else:
        print(f"records={summary['records']} schema_errors={len(errors)} rule_errors={len(rule_errors)}")
        for n, m in errors[:20]: print(f"  line {n}: {m}")
        for n, m in rule_errors[:20]: print(f"  line {n}: RULE {m}")
        for dev, d in summary["devices"].items():
            print(f"{dev}: n={d['count']} seq {d['seq_min']}..{d['seq_max']} dup={d['duplicates']} gaps={d['gaps']} "
                  f"unexplained={len(d['unexplained_gaps'])} null_pos={d['position_null']} lbs={d['lbs']} modes={d['modes']}")
            for g in d["unexplained_gaps"][:10]: print(f"    unexplained gap {g[0]} -> {g[1]}")
    ok = not errors and not rule_errors and all(not d["unexplained_gaps"] for d in summary["devices"].values())
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
