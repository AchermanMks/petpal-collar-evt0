#!/usr/bin/env python3
"""Mask IMEI / IMSI / ICCID / IMEISV style identifiers in LuatOS logs before sharing or archiving.

The Air780EGH base firmware prints the full IMEI (e.g. "self_info ... imei 86431701234567889");
the petpal script only masks its own log lines, so raw Luatools traces must be redacted before
they leave the machine.

Usage:
    redact_ids.py trace.txt                      # writes trace.redacted.txt next to it
    redact_ids.py trace.txt -o records/raw/collar-evt-001/log_F2_20260909.txt
    redact_ids.py trace.txt --check              # only report, do not write

Rule: any run of 14-20 digits (IMEI 15, IMEISV 16, IMSI 15, ICCID 19-20) becomes
first 3 + '*' * (n-6) + last 3, same length, matching net_app.lua's mask().
Digit runs inside longer alphanumeric tokens (hex dumps, hashes) are left alone.
"""
import argparse, re, sys
from pathlib import Path

ID_RE = re.compile(r"(?<![0-9A-Za-z])(\d{14,20})(?![0-9A-Za-z])")

def mask_str(s):
    return s[:3] + "*" * (len(s) - 6) + s[-3:]

def mask(m):
    return mask_str(m.group(1))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("-o", "--out")
    ap.add_argument("--check", action="store_true", help="report matches only, write nothing")
    a = ap.parse_args()
    src = Path(a.src)
    text = src.read_text(encoding="utf-8", errors="replace")
    hits = ID_RE.findall(text)
    print(f"{src}: {len(hits)} identifier(s) found, {len(set(hits))} distinct")
    if a.check:
        for h in sorted(set(hits)):
            print("  ", mask_str(h))
        return 0
    out = Path(a.out) if a.out else src.with_name(src.stem + ".redacted" + src.suffix)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(ID_RE.sub(mask, text), encoding="utf-8")
    left = ID_RE.findall(out.read_text(encoding="utf-8"))
    print(f"-> {out} ({'clean' if not left else str(len(left)) + ' LEFT'})")
    return 0 if not left else 1

if __name__ == "__main__":
    sys.exit(main())
