#!/usr/bin/env python3
"""Capture LuatOS USB/UART log to records/raw with host timestamps (works on macOS, no Luatools needed).

Usage:
    serial_log.py /dev/cu.usbmodem1101 [--baud 921600] [--device collar-evt-001] [--tag F2]
    serial_log.py --list
Output: records/raw/<device>/log_<tag>_<YYYYmmdd_HHMMSS>.txt ; also echoes to stdout.
Also extracts JSON telemetry/ack lines (log lines containing '{"v":1' or '"status":') into <same>.jsonl
for tools/telemetry_validator.py / ack_checker.py.
"""
import argparse, datetime, re, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("port", nargs="?")
    ap.add_argument("--baud", type=int, default=921600)
    ap.add_argument("--device", default="unknown")
    ap.add_argument("--tag", default="log")
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()
    try:
        import serial, serial.tools.list_ports
    except ImportError:
        sys.exit("pip install pyserial")
    if a.list or not a.port:
        for p in serial.tools.list_ports.comports():
            print(p.device, "-", p.description, p.hwid)
        return
    out_dir = ROOT / "records" / "raw" / a.device; out_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    txt = out_dir / f"log_{a.tag}_{stamp}.txt"; jl = out_dir / f"log_{a.tag}_{stamp}.jsonl"
    print(f"logging {a.port} @ {a.baud} -> {txt}")
    with serial.Serial(a.port, a.baud, timeout=1) as s, txt.open("a", encoding="utf-8") as f, jl.open("a", encoding="utf-8") as j:
        try:
            while True:
                line = s.readline()
                if not line: continue
                text = line.decode("utf-8", "replace").rstrip("\r\n")
                ts = datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]
                f.write(f"[{ts}] {text}\n"); f.flush()
                print(f"[{ts}] {text}")
                m = re.search(r'(\{"v":1.*\}|\{"id":".*"status":.*\})', text)
                if m: j.write(m.group(1) + "\n"); j.flush()
        except KeyboardInterrupt:
            print("\nstopped ->", txt)

if __name__ == "__main__":
    main()
