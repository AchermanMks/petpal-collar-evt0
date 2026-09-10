#!/usr/bin/env python3
"""Read the Air780EGH USB *log port* on macOS/Linux without Luatools.

The module's USB composite device (AirM2M Compo USB, VID:PID 19D1:0001) enumerates as three
usbmodem ports. One carries Luatools' framed log stream: every frame holds a printf-style format
string plus raw arguments (decoded by Luatools), but Lua-side log lines (I/user.*, W/..., E/...)
are embedded as complete text after a ">> " marker, and most bsp lines (I/main, I/pm, +CPIN ...)
also appear as plain text. This tool extracts the readable text from the stream, timestamps it,
masks IMEI/ICCID/IMSI-length numbers, and writes it to records/raw like serial_log.py.

Usage:
    usb_log.py --list                      # show candidate ports
    usb_log.py --auto [--device ID] [--tag F2] [--seconds N]
    usb_log.py /dev/cu.usbmodem0000000000013 --device collar-evt-001 --tag F2
Stop with Ctrl-C (or --seconds). --lua keeps only I/ W/ D/ E/ lines (hides bsp format-string noise).
On the Mac mini the log port was /dev/cu.usbmodem0000000000013; ...15 is the binary CP trace, ...17 is silent.
The log port must be opened at 115200 and polled with a write every ~0.5 s, otherwise it emits nothing.
"""
import argparse, datetime, glob, re, sys, time
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
BAUD = 115200   # at 921600 the port stays silent (measured 2026-09-10)
POLL = b"\r\n"  # the log port only releases data while the host keeps writing; Luatools polls the same way
ID_RE = re.compile(r"(?<![0-9A-Za-z])(\d{14,20})(?![0-9A-Za-z])")
TEXT_RE = re.compile(rb"[\x20-\x7e\t]{4,}")
LUA_RE = re.compile(r"^(?:>> .{0,3})?([IWDE]/\S.*)$")

def mask(m):
    s = m.group(1); return s[:3] + "*" * (len(s) - 6) + s[-3:]

def extract(buf):
    """Return readable strings from raw frame bytes. Frames are delimited by 0x7e."""
    lines = []
    for frame in buf.split(b"\x7e"):
        if not frame: continue
        j = frame.find(b">> ")
        if j >= 0:
            # Lua log line: ">> " + one length byte + padding + text
            t = frame[j + 4:]   # skip the length byte
            t = t.decode("utf-8", "replace").strip("\x00 \t\r\n")
            if t: lines.append(ID_RE.sub(mask, t))
            continue
        for m in TEXT_RE.finditer(frame):
            t = m.group(0).decode("ascii", "replace").strip()
            if t: lines.append(ID_RE.sub(mask, t))
    return lines

def candidates():
    return sorted(glob.glob("/dev/cu.usbmodem*") + glob.glob("/dev/ttyACM*"))

def find_log_port(serial, secs=40.0):
    """Listen on every candidate port at once; return the first one that emits a Lua log line.
    The script logs only every 30 s when idle, so a short probe window misses it."""
    import threading
    found = {}
    def worker(p):
        try:
            s = serial.Serial(p, BAUD, timeout=0.5)
        except Exception:
            return
        t0 = time.time()
        while time.time() - t0 < secs and not found:
            try: s.write(POLL)
            except Exception: break
            for l in extract(s.read(65536)):
                if LUA_RE.match(l):
                    found.setdefault(p, l); break
        s.close()
    ts = [threading.Thread(target=worker, args=(p,), daemon=True) for p in candidates()]
    [t.start() for t in ts]; [t.join() for t in ts]
    return found

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("port", nargs="?")
    ap.add_argument("--auto", action="store_true", help="probe ports and pick the log port")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--device", default="unknown")
    ap.add_argument("--tag", default="log")
    ap.add_argument("--seconds", type=float, default=0, help="stop after N seconds (0 = until Ctrl-C)")
    ap.add_argument("--lua", action="store_true", help="only print I/ W/ D/ E/ lines")
    a = ap.parse_args()
    try:
        import serial
    except ImportError:
        sys.exit("pip install pyserial")
    if a.list:
        for p in candidates(): print(p)
        return
    port = a.port
    if a.auto or not port:
        print("probing ports for up to 40 s (script logs every 30 s when idle)...", file=sys.stderr)
        found = find_log_port(serial)
        if not found: sys.exit("no port produced Lua log lines; is the board on and the battery switch closed?")
        port = sorted(found)[0]
        print(f"log port {port}: {found[port]}", file=sys.stderr)
    out_dir = ROOT / "records" / "raw" / a.device; out_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    txt = out_dir / f"log_{a.tag}_{stamp}.txt"
    print(f"logging {port} -> {txt}", file=sys.stderr)
    t0 = time.time()
    with serial.Serial(port, BAUD, timeout=0.3) as s, txt.open("a", encoding="utf-8") as f:
        try:
            while not a.seconds or time.time() - t0 < a.seconds:
                s.write(POLL)           # the port releases buffered log only while the host keeps writing
                buf = s.read(65536)
                if not buf: continue
                ts = datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]
                for l in extract(buf):
                    if a.lua and not LUA_RE.match(l): continue
                    line = f"[{ts}] {l}"
                    f.write(line + "\n"); print(line)
                f.flush()
        except KeyboardInterrupt:
            pass
    print(f"stopped -> {txt}", file=sys.stderr)

if __name__ == "__main__":
    main()
