#!/usr/bin/env python3
"""Summarise a current-log CSV (PPK2 export, Joulescope export, or generic) and
extrapolate battery life (TP-03).

CSV must contain a time column (s or ms) and a current column (A, mA or uA).
Column names are auto-detected; override with --time-col/--current-col.

Usage:
    power_analyzer.py routine.csv --scenario routine [--battery-mah 300] [--usable 0.85]
                      [--peak-threshold-ma 100] [--csv-out records/power_log.csv --device collar-evt-001]
"""
import argparse, csv, math, statistics, sys, datetime

UNIT = {"a": 1000.0, "ma": 1.0, "ua": 0.001, "µa": 0.001}
TUNIT = {"s": 1.0, "ms": 0.001, "us": 1e-6}

def detect(cols, hints):
    for c in cols:
        lc = c.lower()
        if any(h in lc for h in hints):
            return c
    return None

def unit_from(name, table, default):
    lc = name.lower()
    for u in sorted(table, key=len, reverse=True):
        if f"({u})" in lc or lc.endswith(u) or f"[{u}]" in lc:
            return table[u]
    return default

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv")
    ap.add_argument("--scenario", required=True)
    ap.add_argument("--battery-mah", type=float, default=300)
    ap.add_argument("--usable", type=float, default=0.85, help="usable fraction after cutoff/aging discount")
    ap.add_argument("--peak-threshold-ma", type=float, default=100, help="count wakeups when current crosses this")
    ap.add_argument("--time-col"); ap.add_argument("--current-col")
    ap.add_argument("--csv-out"); ap.add_argument("--device", default="")
    ap.add_argument("--fw", default=""); ap.add_argument("--notes", default="")
    a = ap.parse_args()

    with open(a.csv, newline="", encoding="utf-8-sig") as f:
        rd = csv.DictReader(f)
        cols = rd.fieldnames or []
        tcol = a.time_col or detect(cols, ["time", "timestamp", "t("])
        ccol = a.current_col or detect(cols, ["current", "i(", "ma", "ua"])
        if not tcol or not ccol:
            sys.exit(f"cannot detect columns in {cols}; use --time-col/--current-col")
        tm = unit_from(tcol, TUNIT, 1.0); cm = unit_from(ccol, UNIT, 1.0)
        t, i = [], []
        for row in rd:
            try:
                t.append(float(row[tcol]) * tm); i.append(float(row[ccol]) * cm)
            except (ValueError, TypeError):
                continue
    if len(t) < 2:
        sys.exit("not enough samples")
    if t[0] > 1e9:  # epoch seconds → relative
        t = [x - t[0] for x in t]
    dur = t[-1] - t[0]
    # trapezoidal integration → mAh
    mah = sum((i[k] + i[k+1]) / 2 * (t[k+1] - t[k]) for k in range(len(t)-1)) / 3600.0
    avg = mah * 3600.0 / dur
    peak = max(i); p99 = statistics.quantiles(i, n=100)[98] if len(i) > 100 else peak
    wake = sum(1 for k in range(1, len(i)) if i[k-1] < a.peak_threshold_ma <= i[k])
    usable = a.battery_mah * a.usable
    hours = usable / avg if avg > 0 else math.inf

    print(f"file={a.csv} scenario={a.scenario}")
    print(f"samples={len(i)} duration={dur:.1f}s ({dur/3600:.2f} h)")
    print(f"avg={avg:.3f} mA  peak={peak:.1f} mA  p99={p99:.1f} mA  energy={mah:.3f} mAh  wakeups(>{a.peak_threshold_ma:.0f}mA)={wake}")
    print(f"battery {a.battery_mah:.0f} mAh x usable {a.usable:.2f} = {usable:.0f} mAh -> {hours:.1f} h = {hours/24:.2f} days")
    target = {"routine": 5*24, "lost": 4}.get(a.scenario)
    if target:
        print(f"target {target} h: {'PASS' if hours >= target else 'FAIL'} (margin {hours/target*100-100:+.0f}%)")
    if a.csv_out:
        with open(a.csv_out, "a", newline="", encoding="utf-8") as f:
            csv.writer(f).writerow([datetime.date.today().isoformat(), a.device, a.fw, a.scenario, "", f"{dur:.0f}",
                                    f"{avg:.3f}", f"{peak:.1f}", f"{mah:.3f}", wake, "", "", "", "", "", a.csv,
                                    f"{hours/24:.2f}", "", a.notes])
            print(f"appended to {a.csv_out} (fill battery_id/pct/ambient/instrument/tester manually)")

if __name__ == "__main__":
    main()
