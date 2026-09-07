#!/usr/bin/env python3
"""Join command and ack JSONL logs; report final-ACK rate, duplicate executions,
latency percentiles and safety-limit enforcement (TP-04 B).

Usage:
    ack_checker.py commands.jsonl acks.jsonl [--json]
commands.jsonl lines: command payload plus optional "sent_at" (unix s, backend send time).
acks.jsonl lines: ack payload plus optional "recv_at" (unix s, backend receive time).
"""
import argparse, json, statistics, sys, collections

LIMITS = {"duration_ms": 500, "count": 3}

def load(path):
    with open(path, encoding="utf-8") as f:
        return [json.loads(l) for l in f if l.strip()]

def pct(v, p):
    if not v: return None
    v = sorted(v); k = (len(v)-1) * p
    lo, hi = int(k), min(int(k)+1, len(v)-1)
    return v[lo] + (v[hi]-v[lo]) * (k-lo)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("commands"); ap.add_argument("acks"); ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    cmds = {c["id"]: c for c in load(a.commands)}
    acks = collections.defaultdict(list)
    for k in load(a.acks):
        acks[k["id"]].append(k)

    final, dup_exec, unknown, latencies, clamp_fail, over_limit_sent = 0, [], [], [], [], 0
    by_type = collections.Counter(); by_reason = collections.Counter()
    for cid, c in cmds.items():
        ks = sorted(acks.get(cid, []), key=lambda k: k.get("recv_at", k["ts"]))
        statuses = [k["status"] for k in ks]
        n_exec = statuses.count("executed")
        if n_exec > 1: dup_exec.append(cid)
        if any(s in ("executed", "rejected", "error") for s in statuses):
            final += 1
            by_type[c["type"]] += 1
            last = [k for k in ks if k["status"] in ("executed", "rejected", "error")][-1]
            t0 = c.get("sent_at", c["issued_at"]); t1 = last.get("recv_at", last["ts"])
            latencies.append(t1 - t0)
            if last["status"] != "executed": by_reason[last.get("reason", "?")] += 1
        if c["type"] == "VIBRATE":
            args = c.get("args", {})
            over = any(args.get(k, 0) > v for k, v in LIMITS.items())
            if over:
                over_limit_sent += 1
                ex = [k for k in ks if k["status"] == "executed"]
                for k in ex:
                    ap_ = k.get("applied_args") or {}
                    if not ap_ or any(ap_.get(kk, 0) > vv for kk, vv in LIMITS.items()) or k.get("reason") != "limit_clamped":
                        clamp_fail.append(cid)
    for cid in acks:
        if cid not in cmds: unknown.append(cid)

    n = len(cmds)
    out = {
        "commands": n, "final_ack": final, "final_ack_rate": round(final / n, 4) if n else None,
        "duplicate_executions": dup_exec, "unknown_ack_ids": unknown,
        "latency_p50_s": pct(latencies, .5), "latency_p95_s": pct(latencies, .95), "latency_max_s": max(latencies) if latencies else None,
        "over_limit_vibrate_sent": over_limit_sent, "clamp_failures": clamp_fail,
        "by_type": dict(by_type), "reject_reasons": dict(by_reason),
        "pass": bool(n) and final / n >= 0.99 and not dup_exec and (pct(latencies, .95) or 0) <= 10 and not clamp_fail,
    }
    if a.json:
        print(json.dumps(out, indent=2))
    else:
        print(f"commands={n} final_ack={final} ({(out['final_ack_rate'] or 0)*100:.1f}%) dup_exec={len(dup_exec)} "
              f"p50={out['latency_p50_s']} p95={out['latency_p95_s']} max={out['latency_max_s']}")
        print(f"over-limit VIBRATE sent={over_limit_sent} clamp_failures={clamp_fail}")
        print(f"by_type={dict(by_type)} reject_reasons={dict(by_reason)} unknown_ack_ids={len(unknown)}")
        print("PASS" if out["pass"] else "FAIL")
    sys.exit(0 if out["pass"] else 1)

if __name__ == "__main__":
    main()
